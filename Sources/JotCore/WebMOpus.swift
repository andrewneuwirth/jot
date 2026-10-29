import AVFoundation

/// Minimal WebM reader for Opus voice notes (Chromium/Electron MediaRecorder).
/// Walks the EBML tree, keeps the Opus track's frames and decodes them with
/// macOS's own Opus decoder. No ffmpeg, no network.
enum WebMOpus {
    struct Parsed { var channels = 1; var packets: [Data] = [] }
    // Segment, Cluster, Tracks, TrackEntry, BlockGroup, Audio. Children follow inline,
    // so live recordings' unknown-size Segment/Cluster need no special case.
    private static let masters: Set<UInt64> = [0x18538067, 0x1F43B675, 0x1654AE6B, 0xAE, 0xA0, 0xE1]

    static func isWebM(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 4)) == Data([0x1A, 0x45, 0xDF, 0xA3])
    }

    static func parse(_ data: Data) throws -> Parsed {
        let bytes = [UInt8](data)
        var i = 0, track: UInt64 = 0
        var opusTrack: UInt64?
        var result = Parsed()
        while let id = vint(bytes, i, marker: true), let size = vint(bytes, i + id.length, marker: false) {
            i += id.length + size.length
            if masters.contains(id.value) { if id.value == 0xAE { track = 0 }; continue }
            // A truncated tail (recording cut off mid-write) keeps everything before it.
            guard !size.unknown, size.value <= UInt64(bytes.count - i) else { break }
            let body = Array(bytes[i..<i + Int(size.value)])
            i += body.count
            switch id.value {
            case 0xD7: track = body.reduce(0) { $0 << 8 | UInt64($1) }
            case 0x86: if String(decoding: body, as: UTF8.self) == "A_OPUS" { opusTrack = track }
            case 0x63A2: if body.count > 9, body.starts(with: Array("OpusHead".utf8)) { result.channels = max(1, Int(body[9])) }
            case 0xA3, 0xA1: // SimpleBlock / Block: track vint, 16-bit timecode, flags, frame
                guard let number = vint(body, 0, marker: false), number.value == opusTrack, body.count > number.length + 3 else { continue }
                // shortcut: laced blocks are rejected; Chromium and Firefox never lace Opus. Add Xiph/EBML lacing if a recorder does.
                guard body[number.length + 2] & 0x06 == 0 else { throw JotError.message("Laced WebM audio is not supported.") }
                result.packets.append(Data(body[(number.length + 3)...]))
            default: break
            }
        }
        guard opusTrack != nil else { throw JotError.message("This WebM file has no Opus audio track.") }
        return result
    }

    /// EBML variable-length integer. `marker` keeps the length bit (element IDs).
    private static func vint(_ b: [UInt8], _ at: Int, marker: Bool) -> (value: UInt64, length: Int, unknown: Bool)? {
        guard at < b.count, b[at] != 0 else { return nil }
        let length = b[at].leadingZeroBitCount + 1
        guard at + length <= b.count else { return nil }
        let mask = UInt8(0xFF >> length)
        var value = UInt64(marker ? b[at] : b[at] & mask)
        var allOnes = b[at] & mask == mask
        for k in 1..<length { value = value << 8 | UInt64(b[at + k]); allOnes = allOnes && b[at + k] == 0xFF }
        return (value, length, allOnes)
    }

    /// Samples at 48 kHz in one Opus packet, from its TOC byte (RFC 6716 §3.1).
    static func frames(_ packet: Data) -> UInt32 {
        guard let toc = packet.first else { return 0 }
        let config = Int(toc >> 3)
        let units: Int // frame duration in 2.5 ms units (120 samples)
        if config < 12 { units = [4, 8, 16, 24][config % 4] } // SILK 10/20/40/60 ms
        else if config < 16 { units = [4, 8][config % 2] }   // hybrid 10/20 ms
        else { units = [1, 2, 4, 8][config % 4] }            // CELT 2.5/5/10/20 ms
        let count: Int
        switch toc & 3 {
        case 0: count = 1
        case 3: count = packet.count > 1 ? Int(packet[packet.startIndex + 1] & 0x3F) : 0
        default: count = 2
        }
        return UInt32(units * 120 * count)
    }

    /// Mono 48 kHz float PCM; FluidAudio resamples to the model's 16 kHz.
    static func decode(_ url: URL) throws -> AVAudioPCMBuffer {
        let parsed = try parse(Data(contentsOf: url, options: .mappedIfSafe))
        guard let first = parsed.packets.first else { throw JotError.message("No audio in \(url.lastPathComponent).") }
        // Recorders use one frame size throughout, so the first packet sets it.
        var description = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatOpus, mFormatFlags: 0, mBytesPerPacket: 0,
                                                      mFramesPerPacket: frames(first), mBytesPerFrame: 0,
                                                      mChannelsPerFrame: UInt32(parsed.channels), mBitsPerChannel: 0, mReserved: 0)
        let total = parsed.packets.reduce(0) { $0 + Int(frames($1)) }
        guard let input = AVAudioFormat(streamDescription: &description),
              let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: input, to: output),
              let pcm = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: AVAudioFrameCount(total + 5760)) else {
            throw JotError.message("This Mac can't decode Opus audio.")
        }
        converter.downmix = true
        var next = 0
        var error: NSError?
        let status = converter.convert(to: pcm, error: &error) { _, state in
            guard next < parsed.packets.count else { state.pointee = .endOfStream; return nil }
            let packet = parsed.packets[next]; next += 1
            let buffer = AVAudioCompressedBuffer(format: input, packetCapacity: 1, maximumPacketSize: max(1, packet.count))
            packet.copyBytes(to: buffer.data.assumingMemoryBound(to: UInt8.self), count: packet.count)
            buffer.byteLength = UInt32(packet.count); buffer.packetCount = 1
            buffer.packetDescriptions?.pointee = AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(packet.count))
            state.pointee = .haveData
            return buffer
        }
        guard status != .error, pcm.frameLength > 0 else {
            throw JotError.message("Couldn't decode the Opus audio in \(url.lastPathComponent)\(error.map { ": \($0.localizedDescription)" } ?? ".")")
        }
        return pcm
    }
}

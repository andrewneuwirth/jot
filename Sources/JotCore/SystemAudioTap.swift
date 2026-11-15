import AudioToolbox
import CoreAudio
import Foundation

/// Mic + everything the Mac is playing (FaceTime, Zoom, a video) as one input device.
/// A Core Audio process tap captures system output; a private aggregate device puts the
/// microphone and the tap side by side, so the normal `Recorder` can record it like a mic.
/// Needs "System Audio Recording" permission (NSAudioCaptureUsageDescription); macOS asks on first use.
public final class SystemAudioTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    public private(set) var deviceID = AudioObjectID(kAudioObjectUnknown)

    public init() {}

    /// `microphoneID` 0 = the system default input.
    public func start(microphoneID: AudioDeviceID) throws -> AudioDeviceID {
        stop()
        let mic = microphoneID == 0 ? try Self.defaultInput() : microphoneID
        let micUID = try Self.uid(of: mic)

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "Jot call audio"
        description.isPrivate = true
        description.muteBehavior = .unmuted // you still hear the call
        var tap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &tap)
        guard status == noErr else { throw JotError.message("Could not capture Mac audio (\(status)). Allow Jot in Privacy & Security → Screen & System Audio Recording.") }
        tapID = tap

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Jot Call Capture",
            kAudioAggregateDeviceUIDKey: "app.newitools.jot.call.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: micUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: micUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        var device = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device)
        guard status == noErr else { stop(); throw JotError.message("Could not combine the mic with Mac audio (\(status)).") }
        deviceID = device
        return device
    }

    public func stop() {
        if deviceID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(deviceID); deviceID = AudioObjectID(kAudioObjectUnknown) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID); tapID = AudioObjectID(kAudioObjectUnknown) }
    }

    deinit { stop() }

    private static func defaultInput() throws -> AudioDeviceID {
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr, id != kAudioObjectUnknown else {
            throw JotError.message("No microphone is available.")
        }
        return id
    }

    private static func uid(of device: AudioDeviceID) throws -> String {
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr, let value = uid?.takeRetainedValue() else {
            throw JotError.message("Could not read the microphone's ID.")
        }
        return value as String
    }
}

/// Sum every channel into one (mic + both sides of the call), clamped so loud moments don't wrap.
public func mixToMono(_ channels: [UnsafePointer<Float>], frames: Int, into out: UnsafeMutablePointer<Float>) {
    for i in 0..<frames {
        var s: Float = 0
        for c in channels { s += c[i] }
        out[i] = max(-1, min(1, s))
    }
}

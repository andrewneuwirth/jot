import Foundation

/// SpeechAnalyzer revises individual audio ranges, not the entire utterance.
/// Keep distinct ranges across pauses; replace revisions instead of appending them.
struct PreviewTranscript {
    private struct Segment {
        var start: Double
        var end: Double
        var text: String
        var final: Bool
    }
    private var segments: [Segment] = []
    var text: String {
        segments.reduce("") { output, segment in
            guard !output.isEmpty else { return segment.text }
            let punctuation = ".,!?;:’'"
            let separator = segment.text.first.map { punctuation.contains($0) } == true ? "" : " "
            return output + separator + segment.text
        }
    }
    mutating func update(start: Double, end: Double, text: String, isFinal: Bool) -> String {
        guard start.isFinite, end.isFinite, end >= start else { return self.text }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Apple's empty volatile result retracts a hypothesis. For a recording
        // preview, keep what the user has already seen until final transcription.
        guard !cleaned.isEmpty else { return self.text }
        if let index = segments.firstIndex(where: { abs($0.start - start) < 0.0001 }) {
            let previous = segments[index]
            if previous.final { return self.text }
            // Shorter revisions must not erase a sentence during a pause.
            let oldWords = previous.text.split(whereSeparator: \.isWhitespace).count
            let newWords = cleaned.split(whereSeparator: \.isWhitespace).count
            guard newWords >= oldWords else { return self.text }
            segments[index] = Segment(start: start, end: max(end, previous.end), text: cleaned, final: isFinal)
        } else {
            // A new phrase can overlap the tail of the preceding audio range.
            // Never remove the preceding phrase simply because ranges overlap.
            segments.append(Segment(start: start, end: end, text: cleaned, final: isFinal))
        }
        segments.sort { $0.start < $1.start }
        return self.text
    }
}

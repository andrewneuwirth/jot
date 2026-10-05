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
        let sameOrOverlapping: (Segment) -> Bool = {
            abs($0.start - start) < 0.0001 || ($0.start < end - 0.0001 && start < $0.end - 0.0001)
        }
        // A late provisional update must not undo already committed speech.
        if !isFinal, segments.contains(where: { $0.final && sameOrOverlapping($0) }) { return self.text }
        segments.removeAll(where: sameOrOverlapping)
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty { segments.append(Segment(start: start, end: end, text: cleaned, final: isFinal)) }
        segments.sort { $0.start < $1.start }
        return self.text
    }
}

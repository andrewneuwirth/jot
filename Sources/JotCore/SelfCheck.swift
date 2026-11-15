import Foundation

/// `Jot --self-check`: pure-logic checks that run in CI. Nothing records, downloads or touches your library.
public enum SelfCheck {
    @MainActor public static func run() {
        func check(_ label: String, _ ok: Bool) { print(ok ? "ok  \(label)" : "FAIL \(label)"); if !ok { exit(1) } }
        Migration.selfCheck(check)
        check("vocabulary: explicit rules only", TranscriptTools.applyVocabulary("my eye phone", rules: "eye phone = iPhone") == "my iPhone")
        check("word error rate: one substitution in four words", TranscriptTools.wordErrorRate(reference: "a b c d", hypothesis: "a b x d") == 0.25)
        print("self-check ok")
    }
}

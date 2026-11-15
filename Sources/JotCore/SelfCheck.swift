import Foundation

/// `Jot --self-check`: pure-logic checks that run in CI. Nothing records, downloads or touches your library.
public enum SelfCheck {
    @MainActor public static func run() async {
        func check(_ label: String, _ ok: Bool) { print(ok ? "ok  \(label)" : "FAIL \(label)"); if !ok { exit(1) } }
        Migration.selfCheck(check)
        DictationShortcut.selfCheck(check)
        check("vocabulary: explicit rules only", TranscriptTools.applyVocabulary("my eye phone", rules: "eye phone = iPhone") == "my iPhone")
        check("word error rate: one substitution in four words", TranscriptTools.wordErrorRate(reference: "a b c d", hypothesis: "a b x d") == 0.25)
        var legacy = ClassSession(title: "Call · Mon Nov 3", isCall: false); legacy.kind = nil
        var renamed = ClassSession(title: "Call with the bank", isCall: false); renamed.kind = "class"
        check("recordings: sessions from before the split are sorted by title; new ones by kind",
              legacy.isCall && !renamed.isCall && ClassSession(title: "Lecture", isCall: true).isCall)
        await ModelStore.selfCheck(check)
        print("self-check ok")
    }
}

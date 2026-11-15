import Foundation

/// One-time copy of settings from the app's previous bundle id. The Application Support folder (`Jot`) didn't change,
/// so notes, history, recordings and downloaded models carry over on their own. Jot keeps nothing in the Keychain.
public enum Migration {
    /// The previous bundle id, from the optional `JotPreviousBundleID` Info.plist key that build.sh writes from
    /// config.local.env; a build without it has nothing to migrate.
    public static var oldDomain: String? { Bundle.main.object(forInfoDictionaryKey: "JotPreviousBundleID") as? String }

    /// Settings macOS keeps per bundle id don't carry over: Open at Login, Microphone and Accessibility are granted to
    /// the new id again. Jot asks macOS for their state live, so no stored flag needs leaving behind; this is where one goes.
    static let perBundle: Set<String> = []

    public static func run(into new: UserDefaults = .standard, from old: String? = oldDomain) {
        // persistentDomain reads only that domain's own keys, not the global ones a UserDefaults(suiteName:) would add.
        guard let old, new.string(forKey: "migratedFrom") == nil,
              let keys = UserDefaults.standard.persistentDomain(forName: old), !keys.isEmpty else { return }
        for (k, v) in keys where new.object(forKey: k) == nil && !perBundle.contains(k) { new.set(v, forKey: k) }   // never overwrite
        new.set(old, forKey: "migratedFrom")
    }

    /// The distributed notification other tools listen to while Jot records, plus the previous id's name while
    /// listeners still use it (only when the build names a previous id).
    static var recordingNotifications: [Notification.Name] {
        [Notification.Name("app.newitools.jot.recording")] + (oldDomain.map { [Notification.Name("\($0).recording")] } ?? [])
    }

    public static func selfCheck(_ check: (String, Bool) -> Void) {
        let oldName = "jot-selfcheck-old-\(UUID().uuidString)", newName = "jot-selfcheck-new-\(UUID().uuidString)"
        guard let old = UserDefaults(suiteName: oldName), let new = UserDefaults(suiteName: newName) else { return check("migration: suites", false) }
        defer { UserDefaults.standard.removePersistentDomain(forName: oldName); UserDefaults.standard.removePersistentDomain(forName: newName) }
        old.set("ultra", forKey: "mode"); old.set(true, forKey: "keepAudio"); new.set(false, forKey: "keepAudio")
        run(into: new, from: oldName)
        check("migration: copies the old domain once, keeps keys already set, marks it",
              new.string(forKey: "mode") == "ultra" && new.bool(forKey: "keepAudio") == false && new.string(forKey: "migratedFrom") == oldName)
        new.removeObject(forKey: "mode")
        run(into: new, from: oldName)
        check("migration: never runs twice", new.object(forKey: "mode") == nil)
        run(into: new, from: nil)
        check("migration: no previous id, nothing happens", new.object(forKey: "mode") == nil)
    }
}

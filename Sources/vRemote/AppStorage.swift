import Foundation

enum AppStorage {
    static let loggingEnabledKey = "loggingEnabled"
    static let recordingEnabledKey = "recordingEnabled"
    static let macInputEnabledKey = "macInputEnabled"
    static let remoteInputEnabledKey = "remoteInputEnabled"
    static let inputTriggerKeyKey = "inputTriggerKey"
    static let shortcutKey = "voiceShortcut"
    static let shortcutKeyCodeField = "keyCode"
    static let shortcutModifiersField = "modifierFlags"

    static let logsDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/vRemote", isDirectory: true)
    }()

    static let logFile = logsDirectory.appendingPathComponent("vRemote.log")

    static let applicationSupportDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/vRemote", isDirectory: true)
    }()

    static let recordingsDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/vRemote/Recordings",
                isDirectory: true
            )
    }()

    static func prepare() {
        UserDefaults.standard.register(defaults: [
            loggingEnabledKey: false,
            recordingEnabledKey: false,
            macInputEnabledKey: true,
            remoteInputEnabledKey: true,
        ])
        ensureDirectory(logsDirectory)
        ensureDirectory(applicationSupportDirectory)
        ensureDirectory(recordingsDirectory)

        // vRemote has its own storage namespace and never touches V1 data.
    }

    static var loggingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: loggingEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: loggingEnabledKey) }
    }

    static var recordingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: recordingEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: recordingEnabledKey) }
    }

    static var macInputEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: macInputEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: macInputEnabledKey) }
    }

    static var remoteInputEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: remoteInputEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: remoteInputEnabledKey) }
    }

    static var shortcut: Shortcut? {
        get { migratedShortcut }
        set { setShortcut(newValue) }
    }

    /// Replaces the old fixed trigger picker.
    ///
    /// The value read back through `UserDefaults.standard` cannot answer
    /// whether a user ever chose a trigger, because `prepare()` registers a
    /// default for the legacy key: every install, old or new, reports the same
    /// value. So the decision reads the **persisted** domain instead, which
    /// contains only what was actually written, and runs once.
    private static let migratedShortcut: Shortcut? = {
        if let stored = readShortcut() { return stored }

        let domain = persistedDomain
        let decision = ShortcutMigration.decide(
            persistedTriggerKey: domain[inputTriggerKeyKey] as? String,
            hasOtherPersistedSettings: !domain.isEmpty
        )
        UserDefaults.standard.removeObject(forKey: inputTriggerKeyKey)

        switch decision {
        case .stored(let shortcut), .legacyImplicit(let shortcut):
            setShortcut(shortcut)
            return shortcut
        case .freshInstall:
            return nil
        }
    }()

    private static func readShortcut() -> Shortcut? {
        guard let stored = UserDefaults.standard.dictionary(
            forKey: shortcutKey
        ) else { return nil }
        guard let keyCode = stored[shortcutKeyCodeField] as? NSNumber,
              let modifierFlags = stored[shortcutModifiersField] as? NSNumber
        else { return nil }
        return Shortcut(
            keyCode: UInt16(truncating: keyCode),
            modifierFlags: modifierFlags.uint64Value
        )
    }

    private static func setShortcut(_ shortcut: Shortcut?) {
        guard let shortcut else {
            UserDefaults.standard.removeObject(forKey: shortcutKey)
            return
        }
        UserDefaults.standard.set(
            [
                shortcutKeyCodeField: NSNumber(value: shortcut.keyCode),
                shortcutModifiersField: NSNumber(
                    value: shortcut.modifierFlags
                ),
            ],
            forKey: shortcutKey
        )
    }

    /// What was actually written to disk, as opposed to what
    /// `UserDefaults.standard` reports after registered defaults are applied.
    ///
    /// A bare debug executable has no bundle identifier and therefore no
    /// persisted domain; verification against a packaged build is the only way
    /// to observe a realistic value here.
    private static var persistedDomain: [String: Any] {
        guard let identifier = Bundle.main.bundleIdentifier else { return [:] }
        return UserDefaults.standard.persistentDomain(forName: identifier) ?? [:]
    }

    static func ensureDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }

    static func byteSize(of url: URL) -> UInt64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            ), values.isRegularFile == true else { continue }
            total += UInt64(values.fileSize ?? 0)
        }
        return total
    }

    static func clearFiles(in directory: URL) {
        let fm = FileManager.default
        ensureDirectory(directory)
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for file in files {
            try? fm.removeItem(at: file)
        }
    }

    static func formattedSize(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(bytes),
            countStyle: .file
        )
    }
}

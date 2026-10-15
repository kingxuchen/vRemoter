import Foundation

/// Decides what a user upgrading from the old fixed trigger picker should get.
///
/// Foundation-only and side-effect free: the decision is a pure function of what
/// is actually persisted, so it can be asserted directly.
enum ShortcutMigration: Equatable {
    /// The user had explicitly chosen a trigger under the old picker.
    case stored(Shortcut)

    /// A legacy user who never touched the picker. The old default was never
    /// written to storage, so it has to be reconstructed here.
    case legacyImplicit(Shortcut)

    /// A fresh install. There is nothing to guess at, so there is no shortcut.
    case freshInstall

    /// - Parameters:
    ///   - persistedTriggerKey: the raw value found in the **persisted** domain.
    ///     Not the value read through `UserDefaults.standard`, which is polluted
    ///     by registered defaults and therefore identical for every install.
    ///   - hasOtherPersistedSettings: whether the persisted domain holds any
    ///     other vRemoter setting, which is what identifies a legacy install.
    static func decide(
        persistedTriggerKey: String?,
        hasOtherPersistedSettings: Bool
    ) -> ShortcutMigration {
        if let persistedTriggerKey,
           let shortcut = legacyShortcuts[persistedTriggerKey]
        {
            return .stored(shortcut)
        }
        guard hasOtherPersistedSettings else { return .freshInstall }
        return .legacyImplicit(defaultLegacyShortcut)
    }

    /// The trigger the old picker behaved as when nothing was stored.
    static let defaultLegacyShortcut = Shortcut(
        keyCode: ShortcutKey.leftOption,
        modifierFlags: ShortcutModifier.option
    )

    private static let legacyShortcuts: [String: Shortcut] = [
        "option": defaultLegacyShortcut,
        "command": Shortcut(
            keyCode: ShortcutKey.leftCommand,
            modifierFlags: ShortcutModifier.command
        ),
        "control": Shortcut(
            keyCode: ShortcutKey.leftControl,
            modifierFlags: ShortcutModifier.control
        ),
        "shift": Shortcut(
            keyCode: ShortcutKey.leftShift,
            modifierFlags: ShortcutModifier.shift
        ),
        "function": Shortcut(
            keyCode: 0x3F,
            modifierFlags: ShortcutModifier.function
        ),
    ]
}

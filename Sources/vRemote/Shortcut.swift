import Foundation

/// One key plus the modifiers held with it.
///
/// Deliberately Foundation-only: this type is exercised by the framework-free
/// self-test, so nothing here may touch CoreGraphics or AppKit. Conversion to
/// `CGKeyCode` / `CGEventFlags` happens at the boundary, in the caller.
struct Shortcut: Equatable {
    /// macOS virtual key code, stored exactly as the event tap reported it.
    let keyCode: UInt16

    /// Raw modifier flag value held with the key, stored verbatim.
    let modifierFlags: UInt64

    init(keyCode: UInt16, modifierFlags: UInt64) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
    }

    /// Whether the key may be offered to the user as a recorded shortcut.
    static func isCapturable(keyCode: UInt16) -> Bool {
        !reservedKeys.contains(keyCode)
    }

    /// The event to post for the press half of a toggle.
    ///
    /// Modifiers travel on the main key event rather than as their own
    /// press/release pairs; that is how the target app recognises a chord.
    ///
    /// A modifier key always reports its own flag on the press, even when it was
    /// recorded bare. Without that the press and the release would be byte for
    /// byte identical, the target would see the key pressed twice and never
    /// released, and a bare right-hand modifier would not work at all.
    func downEvent() -> ShortcutKeyEvent {
        var flags = modifierFlags
        if let own = Self.sideModifierFlags[keyCode] {
            flags |= own
        }
        return ShortcutKeyEvent(keyCode: keyCode, modifierFlags: flags)
    }

    /// The event to post for the release half of a toggle.
    ///
    /// Modifiers are cleared so the target app sees a clean release, matching
    /// how the previous single-modifier trigger already behaved.
    ///
    /// - Warning: clearing modifiers on the main key's release is verified only
    ///   for a bare modifier, where it is unambiguous. Whether a target app
    ///   listening for a chord recognises a release shaped this way is not
    ///   established — it must be checked against a real voice input app before
    ///   shipping combinations with a main key. See the plan's risk table.
    func upEvent() -> ShortcutKeyEvent {
        ShortcutKeyEvent(keyCode: keyCode, modifierFlags: 0)
    }

    /// The whole event sequence one toggle consists of.
    ///
    /// Expressed as data so the toggle's shape can be asserted without timing.
    func tapSequence() -> [ShortcutKeyEvent] {
        [downEvent(), upEvent()]
    }

    /// Whether an observed key event is this shortcut being pressed.
    ///
    /// A bare modifier may be reported either with or without its own flag set,
    /// depending on the source, so both forms count as the same press. This is
    /// how the app stops watching two variants of one concept at once.
    func matches(keyCode observedKeyCode: UInt16) -> Bool {
        guard observedKeyCode == keyCode else { return false }
        if Self.sideNames[keyCode] != nil {
            let held = Self.sideModifierFlags[keyCode] ?? 0
            return modifierFlags == 0 || modifierFlags == held
        }
        return true
    }

    /// A readable rendering, in the modifier order macOS itself uses.
    ///
    /// A left/right modifier key reads out by name and drops any flag the
    /// source may also have reported for it, so pressing left Command once shows
    /// the same text whether it arrived bare or flagged.
    var displayText: String {
        var symbols = ""
        if modifierFlags & ShortcutModifier.control != 0 { symbols += "⌃" }
        if modifierFlags & ShortcutModifier.option != 0 { symbols += "⌥" }
        if modifierFlags & ShortcutModifier.shift != 0 { symbols += "⇧" }
        if modifierFlags & ShortcutModifier.command != 0 { symbols += "⌘" }

        if let side = Self.sideName(forKeyCode: keyCode) { return side }
        if keyCode == ShortcutKey.fn { return Self.namesAlone[keyCode]! }
        if modifierFlags & ShortcutModifier.function != 0 { symbols += "fn" }
        return symbols + Self.keyName(forKeyCode: keyCode)
    }

    /// Keys macOS keeps for itself. Recording one of these looks like it worked
    /// and then silently does nothing, so they are refused outright and the
    /// user is told why.
    private static let reservedKeys: Set<UInt16> = [
        0x3F, // Fn / Globe
        0x6B, 0x71, // F14 / F15 — display brightness
        0x40, 0x4F, 0x50, // F17 / F18 / F19 — Mission Control, Launchpad, display sleep
    ]

    private static let sideNames: [UInt16: String] = [
        ShortcutKey.leftShift: "左 Shift",
        ShortcutKey.rightShift: "右 Shift",
        ShortcutKey.leftControl: "左 Control",
        ShortcutKey.rightControl: "右 Control",
        ShortcutKey.leftOption: "左 Option",
        ShortcutKey.rightOption: "右 Option",
        ShortcutKey.leftCommand: "左 Command",
        ShortcutKey.rightCommand: "右 Command",
    ]

    private static let sideModifierFlags: [UInt16: UInt64] = [        ShortcutKey.leftShift: ShortcutModifier.shift,
        ShortcutKey.rightShift: ShortcutModifier.shift,
        ShortcutKey.leftControl: ShortcutModifier.control,
        ShortcutKey.rightControl: ShortcutModifier.control,
        ShortcutKey.leftOption: ShortcutModifier.option,
        ShortcutKey.rightOption: ShortcutModifier.option,
        ShortcutKey.leftCommand: ShortcutModifier.command,
        ShortcutKey.rightCommand: ShortcutModifier.command,
    ]

    /// Keys whose name is the whole label, so nothing is appended to it.
    ///
    /// Fn is here because a 1.1.1 install may have stored it as its trigger. It
    /// is no longer offered for recording, but a migrated value still has to
    /// read back as something a person recognises rather than a key code.
    private static let namesAlone: [UInt16: String] = [
        ShortcutKey.fn: "Fn / Globe",
    ]

    /// `kVK_ANSI_*` follows the US keyboard layout, not the alphabet: `V` is
    /// 0x09 and `S` is 0x01, while 0x12 is the digit `1`. Deriving letter names
    /// arithmetically from the key code is wrong.
    private static let keyNames: [UInt16: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G",
        0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V", 0x0B: "B", 0x0C: "Q",
        0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y", 0x11: "T",
        0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5",
        0x18: "=", 0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0",
        0x24: "Return",
        0x30: "Tab",
        0x31: "空格",
        0x33: "Delete",
        0x35: "Escape",
        0x39: "Caps Lock",
        0x47: "Clear",
        0x4C: "数字键盘 Enter",
        0x4E: "数字键盘 −",
        0x60: "F5", 0x61: "F6", 0x62: "F7", 0x63: "F3", 0x64: "F8",
        0x65: "F9", 0x67: "F11", 0x6D: "F10", 0x6F: "F12",
        0x76: "F4", 0x78: "F2", 0x7A: "F1",
        0x73: "Home", 0x74: "Page Up", 0x75: "前向删除",
        0x77: "End", 0x79: "Page Down",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
    ]

    private static func sideName(forKeyCode keyCode: UInt16) -> String? {
        sideNames[keyCode]
    }

    private static func keyName(forKeyCode keyCode: UInt16) -> String {
        keyNames[keyCode] ?? "键码 \(keyCode)"
    }
}

/// A synthetic keyboard event described as plain data.
struct ShortcutKeyEvent: Equatable {
    let keyCode: UInt16
    let modifierFlags: UInt64
}

/// Receives the events a shortcut emits.
///
/// Foundation-only so the toggle's shape can be asserted in the framework-free
/// self-test; the implementation that talks to CoreGraphics lives elsewhere.
protocol ShortcutEventPosting: AnyObject {
    func post(_ event: ShortcutKeyEvent, marker: Int64)
}

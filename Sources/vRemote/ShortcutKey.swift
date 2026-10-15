import Foundation

/// Names for the key codes the value type needs to read back out loud, plus the
/// modifier flag values it stores.
enum ShortcutKey {
    static let leftCommand: UInt16 = 0x37
    static let rightCommand: UInt16 = 0x36
    static let leftShift: UInt16 = 0x38
    static let rightShift: UInt16 = 0x3C
    static let leftOption: UInt16 = 0x3A
    static let rightOption: UInt16 = 0x3D
    static let leftControl: UInt16 = 0x3B
    static let rightControl: UInt16 = 0x3E
    static let space: UInt16 = 0x31
    static let escape: UInt16 = 0x35
    static let v: UInt16 = 0x09

    /// The left/right modifier keys, which macOS reports through flag changes
    /// rather than ordinary key presses.
    static let sideKeyCodes: Set<UInt16> = [
        leftShift, rightShift, leftControl, rightControl,
        leftOption, rightOption, leftCommand, rightCommand,
    ]

    /// F15. On Apple keyboards this pair is display brightness, which macOS
    /// keeps for itself.
    static let brightnessUp: UInt16 = 0x71
}

enum ShortcutModifier {
    static let shift: UInt64 = 0x0002_0000
    static let control: UInt64 = 0x0004_0000
    static let option: UInt64 = 0x0008_0000
    static let command: UInt64 = 0x0010_0000
    static let function: UInt64 = 0x0080_0000
}

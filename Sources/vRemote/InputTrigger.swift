import CoreGraphics
import Foundation

/// Sends a shortcut's events to the system as real keyboard input.
///
/// The events are marked so the app's own event tap can tell them apart from a
/// physical press and from other remappers; without that marker a synthesized
/// trigger would be observed as a second physical press and drive the microphone
/// transition twice.
final class SystemShortcutEventPoster: ShortcutEventPosting {
    static let shared = SystemShortcutEventPoster()

    func post(_ event: ShortcutKeyEvent, marker: Int64) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let cgEvent = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(event.keyCode),
            keyDown: true
        ) else { return }
        cgEvent.flags = CGEventFlags(rawValue: event.modifierFlags)
        cgEvent.setIntegerValueField(.eventSourceUserData, value: marker)
        cgEvent.post(tap: .cghidEventTap)
    }
}

enum Key {
    /// Lets the event tap distinguish vRemoter-generated events from physical
    /// keyboards, Bluetooth buttons, and external remappers.
    static let syntheticMarker: Int64 = 0x4D_49_52_42 // "MIRB"

    /// A deliberate short click of the user's trigger.
    ///
    /// The press and release are separate posts with a gap between them, because
    /// a target app distinguishing a toggle from a hold needs to see both edges.
    static func triggerTap(
        _ shortcut: Shortcut,
        using poster: ShortcutEventPosting = SystemShortcutEventPoster.shared,
        gap: TimeInterval = 0.06,
        completion: (() -> Void)? = nil
    ) {
        let sequence = shortcut.tapSequence()
        guard let press = sequence.first else { return }
        poster.post(press, marker: syntheticMarker)
        DispatchQueue.main.asyncAfter(deadline: .now() + gap) {
            for release in sequence.dropFirst() {
                poster.post(release, marker: syntheticMarker)
            }
            completion?()
        }
    }
}

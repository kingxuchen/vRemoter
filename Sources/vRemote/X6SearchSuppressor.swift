import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Pure decision state for suppressing native macOS events emitted by the X6
/// remote while allowing vRemoter's own synthetic events through.
///
/// Because X6's primary HID usage is Keyboard (0x01/0x06), macOS refuses
/// non-root `kIOHIDOptionsTypeSeizeDevice` with `kIOReturnNotPrivileged`.
/// X6 therefore stays open in non-seized HID mode and relies on the event tap
/// to drop native Search and remapped button events.
struct X6NativeEventGate {
    let suppressionDuration: TimeInterval
    let keyReleaseGraceDuration: TimeInterval

    private(set) var armedUntil = Date.distantPast
    private(set) var heldSystemButtonCount = 0
    private(set) var heldMappedKeyCodes = Set<UInt16>()
    private(set) var pendingKeyReleaseUntil: [UInt16: Date] = [:]

    init(
        suppressionDuration: TimeInterval = 1.5,
        keyReleaseGraceDuration: TimeInterval = 0.5
    ) {
        self.suppressionDuration = suppressionDuration
        self.keyReleaseGraceDuration = keyReleaseGraceDuration
    }

    mutating func armSearch(at now: Date) {
        let candidate = now.addingTimeInterval(suppressionDuration)
        if candidate > armedUntil {
            armedUntil = candidate
        }
    }

    mutating func noteMappedSystemButtonEdge(isDown: Bool, at now: Date) {
        if isDown {
            heldSystemButtonCount += 1
        } else {
            heldSystemButtonCount = max(0, heldSystemButtonCount - 1)
        }
        armSearch(at: now)
    }

    mutating func noteMappedKeyEdge(keyCode: UInt16, isDown: Bool, at now: Date) {
        if isDown {
            heldMappedKeyCodes.insert(keyCode)
            pendingKeyReleaseUntil[keyCode] = now.addingTimeInterval(suppressionDuration)
        } else {
            heldMappedKeyCodes.remove(keyCode)
            pendingKeyReleaseUntil[keyCode] = now.addingTimeInterval(keyReleaseGraceDuration)
        }
    }

    mutating func resetMappedState() {
        heldSystemButtonCount = 0
        heldMappedKeyCodes.removeAll()
        pendingKeyReleaseUntil.removeAll()
    }

    mutating func resetAll() {
        armedUntil = .distantPast
        resetMappedState()
    }

    func isSearchOrSystemArmed(at now: Date) -> Bool {
        heldSystemButtonCount > 0 || now <= armedUntil
    }

    mutating func shouldSuppressMappedKey(
        keyCode: UInt16,
        isKeyDown: Bool,
        isKeyUp: Bool,
        at now: Date
    ) -> Bool {
        guard isKeyDown || isKeyUp else { return false }
        if heldMappedKeyCodes.contains(keyCode) {
            return true
        }
        guard let until = pendingKeyReleaseUntil[keyCode] else { return false }
        guard now <= until else {
            pendingKeyReleaseUntil.removeValue(forKey: keyCode)
            return false
        }
        if isKeyUp {
            pendingKeyReleaseUntil.removeValue(forKey: keyCode)
        }
        return true
    }
}
/// Suppresses the native macOS Search action immediately after X6 emits its
/// Consumer AC Search usage. The gate is armed from the exact VID/PID-matched
/// raw HID callback, so unrelated keyboard events are not globally remapped.
final class X6SearchSuppressor {
    private var tapPort: CFMachPort?
    private var gate = X6NativeEventGate()
    private var triggerKeysDown = Set<Int64>()
    private(set) var isAvailable = false
    var onTriggerDownObserved: ((Bool) -> Void)?
    var onTriggerUpObserved: ((Bool) -> Void)?

    func start() {
        if tapPort != nil { return }
        guard AXIsProcessTrusted() else {
            isAvailable = false
            print("[X6-FILTER] accessibility permission unavailable")
            return
        }
        isAvailable = true

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            // NSEvent.systemDefined is CoreGraphics event type 14, but this
            // SDK does not expose it as a CGEventType enum case.
            (1 << 14)
        let callback: CGEventTapCallBack = {
            _, type, event, context -> Unmanaged<CGEvent>?
            in
            guard let context else {
                return Unmanaged.passRetained(event)
            }
            let suppressor = Unmanaged<X6SearchSuppressor>
                .fromOpaque(context)
                .takeUnretainedValue()

            if type == .tapDisabledByTimeout
                || type == .tapDisabledByUserInput
            {
                if let tapPort = suppressor.tapPort {
                    CGEvent.tapEnable(tap: tapPort, enable: true)
                }
                return Unmanaged.passRetained(event)
            }

            let isSynthetic = event.getIntegerValueField(
                .eventSourceUserData
            ) == Key.syntheticMarker

            if isSynthetic {
                print(
                    "[X6-FILTER] delivered synthetic trigger " +
                    "type=\(type.rawValue) " +
                    "flags=0x\(String(event.flags.rawValue, radix: 16))"
                )
                return Unmanaged.passRetained(event)
            }

            let keyCode = event.getIntegerValueField(
                .keyboardEventKeycode
            )
            let now = Date()
            let rawKeyCode = UInt16(truncatingIfNeeded: keyCode)
            if suppressor.gate.shouldSuppressMappedKey(
                keyCode: rawKeyCode,
                isKeyDown: type == .keyDown,
                isKeyUp: type == .keyUp,
                at: now
            ) {
                print(
                    "[X6-FILTER] suppressed mapped key type=\(type.rawValue) " +
                    "keyCode=0x\(String(keyCode, radix: 16))"
                )
                return nil
            }

            let isArmed = suppressor.gate.isSearchOrSystemArmed(at: now)
            let isSearchKey =
                (type == .keyDown || type == .keyUp) && keyCode == 0xB1
            let isSearchSystemEvent = type.rawValue == 14
            let isDelayedX6Trigger = type == .flagsChanged
                && AppStorage.shortcut?.matches(keyCode: rawKeyCode) == true
            if isArmed && (
                isSearchKey || isSearchSystemEvent || isDelayedX6Trigger
            ) {
                print(
                    "[X6-FILTER] suppressed type=\(type.rawValue) " +
                    "keyCode=0x\(String(keyCode, radix: 16))"
                )
                return nil
            }

            suppressor.observeTriggerEvent(
                type: type,
                event: event,
                isSynthetic: false
            )
            return Unmanaged.passRetained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("[X6-FILTER] unable to create event tap")
            return
        }
        tapPort = tap
        guard let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
            print("[X6-FILTER] unable to create run-loop source")
            tapPort = nil
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[X6-FILTER] native Search suppression ready")
    }

    func arm() {
        if tapPort == nil { start() }
        gate.armSearch(at: Date())
    }

    func noteMappedKeyEdge(keyCode: CGKeyCode, isDown: Bool) {
        if tapPort == nil { start() }
        gate.noteMappedKeyEdge(keyCode: keyCode, isDown: isDown, at: Date())
    }

    func noteMappedSystemButtonEdge(isDown: Bool) {
        if tapPort == nil { start() }
        gate.noteMappedSystemButtonEdge(isDown: isDown, at: Date())
    }

    func resetMappedState() {
        gate.resetMappedState()
    }

    func triggerConfigurationDidChange() {
        triggerKeysDown.removeAll()
        let listened = AppStorage.shortcut?.displayText ?? "未设置"
        print("[INPUT-TRIGGER] listening for \(listened)")
    }

    func stop() {
        gate.resetAll()
        triggerKeysDown.removeAll()
        if let tapPort {
            CGEvent.tapEnable(tap: tapPort, enable: false)
        }
        tapPort = nil
    }

    private func observeTriggerEvent(
        type: CGEventType,
        event: CGEvent,
        isSynthetic: Bool
    ) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        // X6-generated Option events are handed to the coordinator directly
        // before posting. Observing them again here would execute the same
        // microphone transition twice.
        guard !isSynthetic else { return }
        guard let shortcut = AppStorage.shortcut,
              shortcut.matches(keyCode: UInt16(truncatingIfNeeded: keyCode))
        else { return }

        // macOS normally reports modifier edges as `flagsChanged`, but on
        // some keyboards/input-method paths the DOWN edge arrives as a plain
        // `keyDown` while the release still arrives as `flagsChanged`. V1 only
        // listened to flagsChanged, so the app opened but vRemote missed the
        // transition and kept its audio route closed.
        let isDown: Bool
        switch type {
        case .keyDown:
            isDown = true
        case .keyUp:
            isDown = false
        case .flagsChanged:
            // When another key sharing the same modifier stays held, the flag
            // remains set even while this key is released. The per-key set is
            // therefore a more reliable release signal than the flag alone.
            if triggerKeysDown.contains(keyCode) {
                isDown = false
            } else {
                let modifier = CGEventFlags(rawValue: shortcut.modifierFlags)
                guard modifier.isEmpty || event.flags.contains(modifier) else {
                    print(
                        "[TRIGGER-RAW] orphan UP ignored keyCode=0x" +
                        String(keyCode, radix: 16)
                    )
                    return
                }
                isDown = true
            }
        default:
            return
        }

        print(
            "[TRIGGER-RAW] type=\(type.rawValue) " +
            "keyCode=0x\(String(keyCode, radix: 16)) " +
            "edge=\(isDown ? "DOWN" : "UP")"
        )
        if isDown {
            guard triggerKeysDown.insert(keyCode).inserted else { return }
            onTriggerDownObserved?(isSynthetic)
        } else {
            guard triggerKeysDown.remove(keyCode) != nil else { return }
            onTriggerUpObserved?(isSynthetic)
        }
    }
}

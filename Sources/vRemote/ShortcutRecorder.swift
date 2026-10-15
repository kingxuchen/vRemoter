import AppKit
import Foundation

/// Captures the next key the user presses while this app's console has focus.
///
/// Deliberately scoped to the app's own windows instead of a global event tap:
/// a local monitor needs no extra permission and cannot swallow keystrokes aimed
/// at other applications. The trade-off is that recording only works while the
/// console is focused, which is also the moment the user is looking at the
/// control they just clicked.
@MainActor
final class ShortcutRecorder {
    private(set) var isRecording = false

    private var keyMonitor: Any?
    private var flagsMonitor: Any?
    private var onCapture: ((Shortcut) -> Void)?
    private var onReject: ((String) -> Void)?

    func start(
        onCapture: @escaping (Shortcut) -> Void,
        onReject: @escaping (String) -> Void
    ) {
        guard !isRecording else { return }
        isRecording = true
        self.onCapture = onCapture
        self.onReject = onReject

        keyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            self?.handleKeyDown(event)
        }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .flagsChanged
        ) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
    }

    func cancel() {
        stopMonitoring()
    }

    private func stopMonitoring() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
        }
        keyMonitor = nil
        flagsMonitor = nil
        isRecording = false
        onCapture = nil
        onReject = nil
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard isRecording else { return event }
        let keyCode = UInt16(event.keyCode)

        if keyCode == ShortcutKey.escape, event.modifierFlags.isEmpty {
            stopMonitoring()
            return nil
        }
        guard Shortcut.isCapturable(keyCode: keyCode) else {
            stopMonitoring()
            onReject?("这个按键由系统占用，换一个试试。")
            return nil
        }
        finish(
            with: Shortcut(
                keyCode: keyCode,
                modifierFlags: UInt64(event.modifierFlags.rawValue)
            )
        )
        return nil
    }

    /// A bare modifier — including the right-hand variants this feature exists
    /// for — arrives as a flags change rather than a key press, so it has to be
    /// read from here or it can never be recorded.
    private func handleFlagsChanged(_ event: NSEvent) -> NSEvent? {
        guard isRecording else { return event }
        let keyCode = UInt16(event.keyCode)
        guard ShortcutKey.sideKeyCodes.contains(keyCode) else { return event }

        let held = UInt64(event.modifierFlags.rawValue)
        guard held != 0 else { return nil }

        if !Shortcut.isCapturable(keyCode: keyCode) {
            stopMonitoring()
            onReject?("这个按键由系统占用，换一个试试。")
            return nil
        }
        finish(with: Shortcut(keyCode: keyCode, modifierFlags: held))
        return nil
    }

    private func finish(with shortcut: Shortcut) {
        let handler = onCapture
        stopMonitoring()
        handler?(shortcut)
    }
}

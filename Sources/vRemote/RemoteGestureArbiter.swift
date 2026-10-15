import Foundation

/// Owns the timing for one remote's mapped buttons.
///
/// Two paths live here, and what a button assigned decides which one it takes:
///
/// - **Immediate** — a button with no gesture of its own, only a single tap. The
///   tap fires on the press, so nothing feels slower than before, exactly as it
///   did before any of this existed.
/// - **Gesture** — a button the user gave a double tap or a long press. The
///   decision lives in `RemoteGestureClassifier`, which has no clock in it; this
///   type is the shell that feeds it edges and asks again when the clock says a
///   gesture may have become due.
///
/// Only a long press repeats, and only when it lands on an action that repeats.
/// A short press is a short press: it fires its action once and stops, so a
/// button mapped to Delete deletes one character per tap and keeps deleting only
/// when it is deliberately held.
///
/// A press resolves to exactly one slot, and a slot resolves to exactly one
/// action, so a button can never fire two things at once.
final class RemoteGestureArbiter {
    /// The window a button's double tap and long press are measured against.
    /// 0.28s is the threshold X6HIDBridge already ships for the physical voice
    /// key's hold, kept so a button and the voice key are recognised with one
    /// muscle memory.
    static let gestureWindow: TimeInterval = 0.28

    /// How often a held repeating action fires once it has started.
    static let repeatInterval: TimeInterval = 0.06

    private let remote: SupportedRemoteID
    private let classifier = RemoteGestureClassifier(
        longPressThreshold: gestureWindow,
        doubleTapWindow: gestureWindow
    )
    private var states: [String: RemoteGestureClassifier.State] = [:]
    private var ticks: [String: DispatchWorkItem] = [:]
    /// The slot whose action is currently held down, per button.
    private var held: [String: RemoteGesture] = [:]
    private var repeats: [String: DispatchSourceTimer] = [:]

    init(remote: SupportedRemoteID) {
        self.remote = remote
    }

    /// Feeds one edge from the remote.
    func edge(button: RemoteButtonDefinition, isDown: Bool, date: Date = Date()) {
        let store = RemoteMappingStore.shared
        let armed = store.armedGestures(for: button, remote: remote)

        // Nothing to decide: the tap is the whole answer and must not be
        // delayed. A short press never repeats, so nothing is held and the
        // release has nothing to close.
        guard !armed.isEmpty else {
            if isDown {
                store.fire(button: button, remote: remote, gesture: .tap)
            }
            return
        }

        // A held action has to be released before the classifier is asked, or a
        // long press that started repeating would never see its key-up.
        if !isDown { endHold(button: button) }

        let time = date.timeIntervalSinceReferenceDate
        var state = states[button.id] ?? RemoteGestureClassifier.State()
        let outcome: RemoteGestureClassifier.Outcome = isDown
            ? classifier.press(armed: armed, at: time, state: &state)
            : classifier.release(armed: armed, at: time, state: &state)
        states[button.id] = state
        scheduleTick(for: button, armed: armed)
        emit(outcome, for: button)
    }

    /// Releases anything still held and drops every pending timer.
    ///
    /// Called when the remote disconnects. Without it a button held at the
    /// moment of a disconnect would never see its key-up and stay stuck down in
    /// the target app.
    func reset() {
        for tick in ticks.values { tick.cancel() }
        ticks.removeAll()
        for timer in repeats.values { timer.cancel() }
        repeats.removeAll()
        for button in RemoteProfiles.buttons(for: remote) {
            guard let heldSlot = held[button.id] else { continue }
            RemoteMappingStore.shared.post(
                button: button,
                remote: remote,
                gesture: heldSlot,
                isDown: false
            )
        }
        held.removeAll()
        states.removeAll()
    }

    // MARK: - Starting and stopping an action

    /// Starts the action one gesture resolved to.
    ///
    /// Only a long press can be repeating: a short press or a double tap fires
    /// once and is done.
    private func begin(button: RemoteButtonDefinition, slot: RemoteGesture) {
        let store = RemoteMappingStore.shared
        let target = store.target(for: button, remote: remote, gesture: slot)
        let repeats = RemoteGesture.repeatsWhileHeld(
            gesture: slot,
            actionRepeats: RemoteMappingTarget.repeating.contains(target)
        )
        guard repeats else {
            store.fire(button: button, remote: remote, gesture: slot)
            return
        }
        // The hold threshold has already been waited out by the classifier, so
        // the first repeat follows one interval later rather than pausing for
        // the whole delay again.
        store.post(button: button, remote: remote, gesture: slot, isDown: true)
        held[button.id] = slot
        scheduleRepeat(for: button, slot: slot, after: Self.repeatInterval)
    }

    private func endHold(button: RemoteButtonDefinition) {
        repeats[button.id]?.cancel()
        repeats[button.id] = nil
        guard let slot = held.removeValue(forKey: button.id) else { return }
        RemoteMappingStore.shared.post(
            button: button,
            remote: remote,
            gesture: slot,
            isDown: false
        )
    }

    private func scheduleRepeat(
        for button: RemoteButtonDefinition,
        slot: RemoteGesture,
        after delay: TimeInterval
    ) {
        repeats[button.id]?.cancel()
        let remote = self.remote
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + delay,
            repeating: Self.repeatInterval,
            leeway: .milliseconds(5)
        )
        timer.setEventHandler { [weak self] in
            guard let self, self.held[button.id] != nil else {
                timer.cancel()
                return
            }
            RemoteMappingStore.shared.post(
                button: button,
                remote: remote,
                gesture: slot,
                isDown: true
            )
        }
        timer.resume()
        repeats[button.id] = timer
    }

    // MARK: - Gestures

    private func scheduleTick(
        for button: RemoteButtonDefinition,
        armed: Set<RemoteGesture>
    ) {
        ticks[button.id]?.cancel()
        ticks[button.id] = nil
        guard let state = states[button.id], state.tapPending else { return }

        // Long press is measured from the press, double tap from the release.
        let deadline: TimeInterval
        if let pressed = state.pressedAt {
            deadline = pressed + classifier.longPressThreshold
        } else if let released = state.releasedAt, armed.contains(.doubleTap) {
            deadline = released + classifier.doubleTapWindow
        } else {
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.ticks[button.id] = nil
            var state = self.states[button.id] ?? RemoteGestureClassifier.State()
            let outcome = self.classifier.tick(
                armed: armed,
                at: Date().timeIntervalSinceReferenceDate,
                state: &state
            )
            self.states[button.id] = state
            self.emit(outcome, for: button)
            if state.tapPending {
                self.scheduleTick(for: button, armed: armed)
            }
        }
        ticks[button.id] = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(0, deadline - Date().timeIntervalSinceReferenceDate),
            execute: work
        )
    }

    private func emit(
        _ outcome: RemoteGestureClassifier.Outcome,
        for button: RemoteButtonDefinition
    ) {
        guard case .emit(let slots) = outcome else { return }
        for slot in slots {
            begin(button: button, slot: slot)
            print("[GESTURE] \(remote.rawValue)/\(button.id) -> \(slot.rawValue)")
        }
    }
}

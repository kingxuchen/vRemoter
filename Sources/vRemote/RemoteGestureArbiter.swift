import Foundation

/// Owns the timing for one remote's mapped buttons.
///
/// Two paths live here, and which one a button takes is decided by what the
/// user assigned to it:
///
/// - **Hold** — the repeating actions, Delete and the four arrows. It fires on
///   the press, so nothing feels slower than before, and staying down keeps
///   firing, the way a real keyboard's Backspace or arrow does. Either slot can
///   ask for it: a single tap mapped to a repeating action, or a long press
///   mapped to one. It follows the mapping rather than the physical button —
///   remap Home to Delete and Home starts deleting too.
/// - **Gesture** — everything else. The behaviour lives in
///   `RemoteGestureClassifier`, which has no clock in it, and this type is the
///   shell that feeds it edges and asks again when the clock says a gesture may
///   have become due.
///
/// A button never takes both paths: assigning a gesture is what turns repeat
/// off, so a press can never mean two actions at once.
final class RemoteGestureArbiter {
    /// The window a button's double tap and long press are measured against.
    /// 0.28s is the threshold X6HIDBridge already ships for the physical voice
    /// key's hold, kept so a button and the voice key are recognised with one
    /// muscle memory.
    static let gestureWindow: TimeInterval = 0.28

    /// How long a repeating button must stay down before it starts repeating.
    /// Close to the macOS default so the remote does not feel twitchier than a
    /// real keyboard; a deliberate single press never reaches it.
    static let repeatDelay: TimeInterval = 0.45

    /// How often a held repeating button fires once it has started.
    static let repeatInterval: TimeInterval = 0.06

    private let remote: SupportedRemoteID
    private let classifier = RemoteGestureClassifier(
        longPressThreshold: gestureWindow,
        doubleTapWindow: gestureWindow
    )
    private var states: [String: RemoteGestureClassifier.State] = [:]
    private var ticks: [String: DispatchWorkItem] = [:]
    private var held: [String: RemoteGesture] = [:]
    private var repeats: [String: DispatchSourceTimer] = [:]

    init(remote: SupportedRemoteID) {
        self.remote = remote
    }

    /// Feeds one edge from the remote.
    func edge(button: RemoteButtonDefinition, isDown: Bool, date: Date = Date()) {
        let store = RemoteMappingStore.shared
        // Delete and the arrows repeat, whichever slot says so. Everything else
        // resolves as a gesture.
        if let repeating = store.repeatingGesture(for: button, remote: remote) {
            hold(button: button, isDown: isDown, gesture: repeating)
            return
        }
        gesture(
            button: button,
            armed: store.armedGestures(for: button, remote: remote),
            isDown: isDown,
            date: date
        )
    }

    /// Releases anything still held and drops every pending timer.
    ///
    /// Called when the remote disconnects. Without it a key held at the moment
    /// of a disconnect would never see its key-up and stay stuck down in the
    /// target app.
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

    // MARK: - Hold to repeat

    private func hold(
        button: RemoteButtonDefinition,
        isDown: Bool,
        gesture: RemoteGesture
    ) {
        if isDown {
            // Firing on the press is what keeps a short press exactly as fast
            // as it was before repeat existed.
            RemoteMappingStore.shared.post(
                button: button,
                remote: remote,
                gesture: gesture,
                isDown: true
            )
            held[button.id] = gesture
            scheduleRepeat(for: button, gesture: gesture, after: Self.repeatDelay)
        } else {
            release(button: button)
        }
    }

    private func release(button: RemoteButtonDefinition) {
        repeats[button.id]?.cancel()
        repeats[button.id] = nil
        guard let gesture = held.removeValue(forKey: button.id) else { return }
        RemoteMappingStore.shared.post(
            button: button,
            remote: remote,
            gesture: gesture,
            isDown: false
        )
    }

    private func scheduleRepeat(
        for button: RemoteButtonDefinition,
        gesture: RemoteGesture,
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
                gesture: gesture,
                isDown: true
            )
        }
        timer.resume()
        repeats[button.id] = timer
    }

    // MARK: - Gestures

    private func gesture(
        button: RemoteButtonDefinition,
        armed: Set<RemoteGesture>,
        isDown: Bool,
        date: Date
    ) {
        let time = date.timeIntervalSinceReferenceDate
        var state = states[button.id] ?? RemoteGestureClassifier.State()

        let outcome: RemoteGestureClassifier.Outcome = isDown
            ? classifier.press(armed: armed, at: time, state: &state)
            : classifier.release(armed: armed, at: time, state: &state)

        states[button.id] = state
        scheduleTick(for: button, armed: armed)
        emit(outcome, for: button)
    }

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
        guard case .emit(let gestures) = outcome else { return }
        for gesture in gestures {
            RemoteMappingStore.shared.fire(button: button, remote: remote, gesture: gesture)
            print("[GESTURE] \(remote.rawValue)/\(button.id) -> \(gesture.rawValue)")
        }
    }
}

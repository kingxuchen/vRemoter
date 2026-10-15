import Foundation

/// How one mapped remote button was pressed.
///
/// A button always has a single-tap mapping. The other two are armed only when
/// the user assigns something to them.
enum RemoteGesture: String, CaseIterable, Codable, Hashable, Identifiable {
    case tap
    case doubleTap
    case longPress

    var id: String { rawValue }

    /// The gestures the user has actually armed for a button.
    ///
    /// `assigned` holds only the gestures that were given something; the single
    /// tap is the fallback rather than an extra, so it is never listed.
    ///
    /// A long press that resolves to the same action as the single tap is not a
    /// separate gesture at all — the user is expressing "hold this to repeat
    /// it". Counting it as armed would take the button off the repeating path,
    /// which is the exact opposite of what they set up.
    static func armed<Target: Equatable>(
        tap: Target,
        assigned: [RemoteGesture: Target?]
    ) -> Set<RemoteGesture> {
        Set(
            RemoteGesture.allCases.filter { gesture in
                guard let target = assigned[gesture] ?? nil else { return false }
                return gesture != .longPress || target != tap
            }
        )
    }
}

/// Turns the press/release edges of a button into the gestures it produced.
///
/// Deliberately Foundation-only and free of timers, so the whole decision is
/// plain data: the caller feeds it edges with timestamps and asks what became
/// due. That keeps it assertable by the framework-free self-test, and keeps the
/// timing out of the behaviour so changing a threshold cannot change what
/// counts as a double tap.
///
/// The rule this encodes: a button with no gestures of its own fires on the
/// press, with no delay at all. A button the user has given a double tap or a
/// long press has to wait, because the first press no longer decides what the
/// gesture was.
struct RemoteGestureClassifier: Equatable {
    /// How long a button must stay down before it is a long press.
    let longPressThreshold: TimeInterval

    /// How long after a release a second press still counts as the second half
    /// of a double tap. Measured release-to-press, which is the only place a
    /// double tap is unambiguous — a press-to-press window would make one fast
    /// press look like the first half of a double tap.
    let doubleTapWindow: TimeInterval

    init(
        longPressThreshold: TimeInterval = 0.28,
        doubleTapWindow: TimeInterval = 0.28
    ) {
        self.longPressThreshold = longPressThreshold
        self.doubleTapWindow = doubleTapWindow
    }

    /// One button's in-flight press, held across the calls that resolve it.
    struct State: Equatable {
        /// When the current press started, or nil when nothing is held.
        var pressedAt: TimeInterval?
        /// When the last release happened, which opens the double-tap window.
        var releasedAt: TimeInterval?
        /// A single tap is owed but not yet emitted because a second press
        /// could still turn it into a double tap.
        var tapPending = false
        /// The current press has already been reported as a double tap.
        var pressConsumed = false
    }

    /// What one transition produced. `wait` means the timer must be asked again.
    enum Outcome: Equatable {
        case emit([RemoteGesture])
        case wait
    }

    /// Handles a press.
    func press(
        armed: Set<RemoteGesture>,
        at time: TimeInterval,
        state: inout State
    ) -> Outcome {
        // A second press inside the window after a release is the other half of
        // a double tap. The pending tap is replaced by it rather than sent
        // first, which is what stops a double tap reaching the target app as
        // two separate presses.
        if armed.contains(.doubleTap),
           let released = state.releasedAt,
           time - released <= doubleTapWindow {
            state = State(pressConsumed: true)
            return .emit([.doubleTap])
        }

        state.releasedAt = nil
        state.pressConsumed = false

        // Nothing extra was assigned to this button, so the press is already
        // the whole answer and must not be delayed.
        guard armed.contains(.longPress) || armed.contains(.doubleTap) else {
            return .emit([.tap])
        }

        state.pressedAt = time
        state.tapPending = true
        return .wait
    }

    /// Handles a release.
    func release(
        armed: Set<RemoteGesture>,
        at time: TimeInterval,
        state: inout State
    ) -> Outcome {
        // A press already reported as a double tap has nothing left to report.
        guard !state.pressConsumed else {
            state.pressConsumed = false
            state.tapPending = false
            state.releasedAt = nil
            return .wait
        }

        guard state.tapPending, let pressed = state.pressedAt else {
            state = State()
            return .wait
        }

        // A long press the timer had not reported yet still has to be
        // recognised here, or a release just after the threshold would be
        // mistaken for a tap.
        if armed.contains(.longPress), time - pressed >= longPressThreshold {
            state = State()
            return .emit([.longPress])
        }

        // A double tap could still follow, so the tap waits for its window to
        // close and `tick` emits it.
        if armed.contains(.doubleTap) {
            state.pressedAt = nil
            state.tapPending = true
            state.releasedAt = time
            return .wait
        }

        state = State()
        return .emit([.tap])
    }

    /// Reports whatever elapsed time alone has made due.
    func tick(
        armed: Set<RemoteGesture>,
        at time: TimeInterval,
        state: inout State
    ) -> Outcome {
        guard state.tapPending else { return .wait }

        if armed.contains(.longPress),
           let pressed = state.pressedAt,
           time - pressed >= longPressThreshold {
            // Fires while the button is still down, so a long press gives
            // feedback without waiting for the release.
            state.tapPending = false
            return .emit([.longPress])
        }

        guard state.pressedAt == nil,
              armed.contains(.doubleTap),
              let released = state.releasedAt,
              time - released >= doubleTapWindow
        else { return .wait }

        state.tapPending = false
        state.releasedAt = nil
        return .emit([.tap])
    }

    /// Forgets one button's in-flight press, e.g. when its remote disconnects.
    func reset(_ state: inout State) {
        state = State()
    }
}

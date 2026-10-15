import Foundation

enum VoiceRemoteID: String, CaseIterable {
    case x6
    case chromecast
}

enum RemoteMicrophoneOpenResult: Equatable {
    case sent
    case alreadyStreaming
    case retryAfter(TimeInterval)
    case unavailable
    case failed(String)
}

/// Coordinates the voice trigger toggle, supported remote gestures, and each
/// remote's independent ATVV transport.
///
/// The session belongs to this type, not to any voice input application: a press
/// opens the remote microphone and emits the user's shortcut, a second press
/// emits it again and closes. Nothing is observed about which application is
/// recording, so the shortcut works with whatever the user has configured.
///
/// A transport START/STOP is never itself a keyboard toggle. A physical
/// keyboard trigger already reaches the voice input app. A remote gesture synthesizes
/// exactly one trigger only when it changes the intended recognition state.
final class X6SessionCoordinator {
    private enum Phase: String {
        case closed
        case opening
        case open
        case closing
    }

    private enum Owner: String {
        case none
        case remote
        case keyboard
    }

    struct DebugSnapshot: Equatable {
        let phase: String
        let generation: UInt64
        let sessionRemote: VoiceRemoteID?
        let streamingRemotes: Set<VoiceRemoteID>
        let openRequestedRemote: VoiceRemoteID?
    }

    private static let maximumOpenAttempts = 3

    /// One physical press can be reported through more than one channel — an
    /// X6 announces it over both BLE audio and HID. Two edges that close
    /// together would toggle twice and leave the session unchanged, which
    /// reads as a dead button, so edges inside this window count as one.
    private static let pressEdgeDebounce: TimeInterval = 0.25
    private static let openConfirmationTimeout: TimeInterval = 1.0

    private let setRemoteRouteActive: (Bool) -> Void
    private let triggerTap: () -> Void
    private let triggerAvailable: () -> Bool
    private let now: () -> Date

    private var phase: Phase = .closed
    private var owner: Owner = .none
    private var generation: UInt64 = 0
    private var routeActive = false
    private var sessionRemote: VoiceRemoteID?
    private var streamingRemotes = Set<VoiceRemoteID>()
    private var openRequestedRemote: VoiceRemoteID?
    private var lastPressEdgeAt: Date?

    private var routeCloseWorkItem: DispatchWorkItem?
    private var startVerificationWorkItem: DispatchWorkItem?
    private var closeVerificationWorkItem: DispatchWorkItem?
    private var openRetryWorkItem: DispatchWorkItem?
    private var openConfirmationWorkItem: DispatchWorkItem?

    var preferredRemoteProvider: (() -> VoiceRemoteID?)?
    var onMicrophoneOpenRequested:
        ((VoiceRemoteID, Bool) -> RemoteMicrophoneOpenResult)?
    var onMicrophoneCloseRequested: (() -> Void)?
    var onStateChanged: ((String) -> Void)?

    init(
        setRemoteRouteActive: @escaping (Bool) -> Void = {
            AudioPipe.shared.setRemoteActive($0)
        },
        triggerTap: @escaping () -> Void = {
            guard let shortcut = AppStorage.shortcut else { return }
            Key.triggerTap(shortcut)
        },
        triggerAvailable: @escaping () -> Bool = { AppStorage.shortcut != nil },
        now: @escaping () -> Date = Date.init
    ) {
        self.setRemoteRouteActive = setRemoteRouteActive
        self.triggerTap = triggerTap
        self.triggerAvailable = triggerAvailable
        self.now = now
    }

    var debugSnapshot: DebugSnapshot {
        DebugSnapshot(
            phase: phase.rawValue,
            generation: generation,
            sessionRemote: sessionRemote,
            streamingRemotes: streamingRemotes,
            openRequestedRemote: openRequestedRemote
        )
    }

    func start() {}

    // MARK: - ATVV transport

    // MARK: - Toggle edges

    /// One physical press of the remote voice key, however it was announced.
    ///
    /// Toggle, not hold-to-talk: this opens the session and emits the user's
    /// shortcut, and the next press emits it again and closes. The remote's own
    /// release is deliberately not a stop signal, because the user asked for a
    /// toggle rather than a hold.
    func voiceKeyPressed(remote: VoiceRemoteID, reason: UInt8 = 0) {
        guard triggerAvailable() else {
            print("[VOICE-SESSION] no shortcut configured; voice key ignored")
            return
        }
        let at = now()
        if let last = lastPressEdgeAt,
           at.timeIntervalSince(last) < Self.pressEdgeDebounce
        {
            print(
                "[VOICE-SESSION] duplicate press edge ignored " +
                "remote=\(remote.rawValue) reason=" +
                String(format: "0x%02x", reason)
            )
            return
        }
        lastPressEdgeAt = at

        if openRequestedRemote == remote {
            openRequestedRemote = nil
            openConfirmationWorkItem?.cancel()
            openConfirmationWorkItem = nil
        }

        switch phase {
        case .closed, .opening:
            beginOpening(
                owner: .remote,
                remote: remote,
                sendTrigger: true,
                requestTransportImmediately: true
            )
        case .open:
            beginClosing(sendTrigger: true, reason: "voice key toggle")
        case .closing:
            // A press arriving mid-close is not a reversal. The user is most
            // likely still letting go of the previous one.
            print("[VOICE-SESSION] press edge while closing ignored")
        }
    }

    /// The remote released its own button.
    ///
    /// Under toggle semantics this is only the tail of the press that already
    /// opened the session, so it must not close anything. It does stop tracking
    /// the remote's spontaneous stream, which is what `streamingRemotes`
    /// records.
    func remoteAudioStopped(remote: VoiceRemoteID, reason: UInt8) {
        streamingRemotes.remove(remote)
        if openRequestedRemote == remote {
            openRequestedRemote = nil
            openConfirmationWorkItem?.cancel()
            openConfirmationWorkItem = nil
        }
        print(
            "[VOICE-SESSION] remote released remote=\(remote.rawValue) " +
            "reason=" + String(format: "0x%02x", reason) +
            " phase=\(phase.rawValue)"
        )

        // The remote's own stream is welded to its button, so releasing ends it.
        // Under a toggle the session has to outlive the button, so ask the same
        // remote to keep its microphone open.
        //
        // Without this the initial open request is swallowed as "already
        // streaming" — at press time the remote is streaming by itself — and
        // nothing is left to restart it once the button comes up, which looks
        // exactly like hold-to-talk.
        guard phase == .open, let active = sessionRemote else { return }
        guard active == remote || streamingRemotes.isEmpty else { return }
        print(
            "[VOICE-SESSION] re-requesting persistent stream remote=" +
            "\(active.rawValue) after physical release"
        )
        requestRemoteTransportOpen(active, bypassDebounce: true, attempt: 1)
    }

    func remoteHIDShortPress() {
        guard let remote = preferredRemoteProvider?() else {
            print("[VOICE-SESSION] HID short press with no remote attached")
            return
        }
        voiceKeyPressed(remote: remote)
    }

    func remoteHIDLongPressEnded() {
        print("[VOICE-SESSION] HID long release — session left as-is")
    }

    func remoteDisconnected(_ remote: VoiceRemoteID) {
        streamingRemotes.remove(remote)
        if openRequestedRemote == remote {
            openRequestedRemote = nil
            openRetryWorkItem?.cancel()
            openRetryWorkItem = nil
            openConfirmationWorkItem?.cancel()
            openConfirmationWorkItem = nil
        }

        guard sessionRemote == remote else { return }
        sessionRemote = preferredRemoteProvider?()
        guard phase == .opening || phase == .open,
              let replacement = sessionRemote
        else { return }
        requestRemoteTransportOpen(
            replacement,
            bypassDebounce: false,
            attempt: 1
        )
    }

    func remoteMicrophoneOpenFailed(remote: VoiceRemoteID, code: UInt16) {
        guard openRequestedRemote == remote,
              phase == .opening || phase == .open
        else { return }
        openRequestedRemote = nil
        openConfirmationWorkItem?.cancel()
        openConfirmationWorkItem = nil
        print(
            "[VOICE-SESSION] MIC_OPEN failed remote=\(remote.rawValue) " +
            String(format: "code=0x%04x", code)
        )
        scheduleOpenRetry(remote: remote, after: 0.20, attempt: 2)
    }

    // MARK: - Physical keyboard trigger

    /// Called before the real physical trigger reaches its target application.
    /// It moves the remote transport only; it never synthesizes a second
    /// keyboard event, because the physical key is already going through.
    func triggerDownObserved(isSynthetic: Bool) {
        guard !isSynthetic else { return }
        guard triggerAvailable() else {
            print("[TRIGGER] no shortcut configured; key ignored")
            return
        }
        switch phase {
        case .closed, .opening:
            guard let remote = preferredRemoteProvider?() else {
                beginOpeningWithoutRemote()
                return
            }
            beginOpening(
                owner: .keyboard,
                remote: remote,
                sendTrigger: false,
                requestTransportImmediately: true
            )
        case .open:
            beginClosing(sendTrigger: false, reason: "keyboard trigger")
        case .closing:
            print("[TRIGGER] DOWN while closing ignored")
        }
    }

    func triggerUpObserved(isSynthetic: Bool) {
        guard !isSynthetic else { return }
        print(
            "[TRIGGER] UP source=keyboard phase=\(phase.rawValue) " +
            "owner=\(owner.rawValue)"
        )
    }

    // MARK: - Lifecycle / manual control

    func forceClose() {
        generation &+= 1
        cancelScheduledWork()
        phase = .closed
        owner = .none
        sessionRemote = nil
        lastPressEdgeAt = nil
        closeRouteAndTransports()
        publish("已手动关闭")
    }

    func stop() {
        forceClose()
    }

    // MARK: - State transitions

    private func beginOpeningWithoutRemote() {
        generation &+= 1
        cancelScheduledWork()
        phase = .opening
        owner = .keyboard
        sessionRemote = nil
        activateRemoteRoute()
        publish("语音输入已开启 · 等待遥控器")
    }

    private func beginOpening(
        owner: Owner,
        remote: VoiceRemoteID,
        sendTrigger: Bool,
        requestTransportImmediately: Bool
    ) {
        generation &+= 1
        cancelScheduledWork()
        phase = .opening
        self.owner = owner
        sessionRemote = remote
        activateRemoteRoute()
        if sendTrigger {
            triggerTap()
        }
        if requestTransportImmediately {
            requestRemoteTransportOpen(
                remote,
                bypassDebounce: false,
                attempt: 1
            )
        }
        // Nothing is left to confirm: this type owns the session, and there is
        // no application whose state could be waited on. Linger in .opening
        // would make the next press read as another open instead of a close.
        phase = .open
        publish(
            owner == .keyboard
                ? "语音输入已开启 · 遥控器已预热"
                : "语音输入已开启 · 遥控器已接入"
        )
    }

    private func closeRecognitionFromRemote(reason: String) {
        guard phase == .opening || phase == .open else {
            print(
                "[VOICE-SESSION] \(reason) ignored phase=\(phase.rawValue)"
            )
            return
        }
        beginClosing(sendTrigger: true, reason: reason)
    }

    private func beginClosing(sendTrigger: Bool, reason: String) {
        guard phase != .closed, phase != .closing else {
            print(
                "[VOICE-SESSION] close ignored phase=\(phase.rawValue) " +
                "reason=\(reason)"
            )
            return
        }

        generation &+= 1
        cancelScheduledWork()
        phase = .closing
        owner = .none
        openRequestedRemote = nil
        if sendTrigger {
            triggerTap()
        }
        scheduleRouteClose(after: 0.10)
        publish("正在结束语音输入")
        print(
            "[VOICE-SESSION] begin closing reason=\(reason) " +
            "trigger=\(sendTrigger ? "synthetic" : "physical")"
        )
    }

    private func finalizeClosed(reason: String) {
        generation &+= 1
        cancelScheduledWork()
        phase = .closed
        owner = .none
        sessionRemote = nil
        closeRouteAndTransports()
        print("[VOICE-SESSION] closed reason=\(reason)")
    }

    // MARK: - Remote transport requests

    private func requestRemoteTransportOpen(
        _ remote: VoiceRemoteID,
        bypassDebounce: Bool,
        attempt: Int
    ) {
        guard phase == .opening || phase == .open,
              !streamingRemotes.contains(remote),
              openRequestedRemote != remote
        else { return }

        guard let request = onMicrophoneOpenRequested else {
            print(
                "[VOICE-SESSION] MIC_OPEN unavailable " +
                "remote=\(remote.rawValue)"
            )
            return
        }

        let result = request(remote, bypassDebounce)
        switch result {
        case .sent:
            openRequestedRemote = remote
            scheduleOpenConfirmation(
                remote: remote,
                attempt: attempt,
                generation: generation
            )
            print(
                "[VOICE-SESSION] MIC_OPEN sent remote=\(remote.rawValue) " +
                "attempt=\(attempt)"
            )

        case .alreadyStreaming:
            streamingRemotes.insert(remote)
            openRequestedRemote = nil
            print(
                "[VOICE-SESSION] MIC_OPEN already streaming " +
                "remote=\(remote.rawValue)"
            )

        case .retryAfter(let delay):
            scheduleOpenRetry(
                remote: remote,
                after: delay,
                attempt: attempt + 1
            )

        case .unavailable:
            print(
                "[VOICE-SESSION] MIC_OPEN target unavailable " +
                "remote=\(remote.rawValue)"
            )

        case .failed(let message):
            print(
                "[VOICE-SESSION] MIC_OPEN failed remote=\(remote.rawValue) " +
                "message=\(message)"
            )
            scheduleOpenRetry(
                remote: remote,
                after: 0.20,
                attempt: attempt + 1
            )
        }
    }

    private func scheduleOpenRetry(
        remote: VoiceRemoteID,
        after delay: TimeInterval,
        attempt: Int
    ) {
        guard attempt <= Self.maximumOpenAttempts else {
            print(
                "[VOICE-SESSION] MIC_OPEN retries exhausted " +
                "remote=\(remote.rawValue)"
            )
            return
        }
        openRetryWorkItem?.cancel()
        let expectedGeneration = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  self.generation == expectedGeneration,
                  self.phase == .opening || self.phase == .open
            else { return }
            self.openRetryWorkItem = nil
            self.requestRemoteTransportOpen(
                remote,
                bypassDebounce: true,
                attempt: attempt
            )
        }
        openRetryWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(0.01, delay),
            execute: work
        )
    }

    private func scheduleOpenConfirmation(
        remote: VoiceRemoteID,
        attempt: Int,
        generation expectedGeneration: UInt64
    ) {
        openConfirmationWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  self.generation == expectedGeneration,
                  self.openRequestedRemote == remote,
                  !self.streamingRemotes.contains(remote),
                  self.phase == .opening || self.phase == .open
            else { return }
            self.openRequestedRemote = nil
            self.openConfirmationWorkItem = nil
            print(
                "[VOICE-SESSION] MIC_OPEN confirmation timeout " +
                "remote=\(remote.rawValue) attempt=\(attempt)"
            )
            self.scheduleOpenRetry(
                remote: remote,
                after: 0.05,
                attempt: attempt + 1
            )
        }
        openConfirmationWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.openConfirmationTimeout,
            execute: work
        )
    }

    // MARK: - Verification and route lifecycle

    private func activateRemoteRoute() {
        routeCloseWorkItem?.cancel()
        routeCloseWorkItem = nil
        guard !routeActive else { return }
        routeActive = true
        setRemoteRouteActive(true)
        print(
            "[VOICE-SESSION] audio route ON phase=\(phase.rawValue) " +
            "owner=\(owner.rawValue)"
        )
    }

    private func scheduleRouteClose(after delay: TimeInterval) {
        routeCloseWorkItem?.cancel()
        let expectedGeneration = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == expectedGeneration else { return }
            self.routeCloseWorkItem = nil
            self.closeRouteAndTransports()
        }
        routeCloseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func closeAllRemoteTransports() {
        onMicrophoneCloseRequested?()
        streamingRemotes.removeAll()
        openRequestedRemote = nil
        openRetryWorkItem?.cancel()
        openRetryWorkItem = nil
        openConfirmationWorkItem?.cancel()
        openConfirmationWorkItem = nil
    }

    private func closeRouteAndTransports() {
        let hadTransport =
            !streamingRemotes.isEmpty || openRequestedRemote != nil
        routeActive = false
        setRemoteRouteActive(false)
        if hadTransport {
            closeAllRemoteTransports()
        }
        print("[VOICE-SESSION] audio route OFF")
    }

    private func cancelScheduledWork() {
        routeCloseWorkItem?.cancel()
        routeCloseWorkItem = nil
        startVerificationWorkItem?.cancel()
        startVerificationWorkItem = nil
        closeVerificationWorkItem?.cancel()
        closeVerificationWorkItem = nil
        openRetryWorkItem?.cancel()
        openRetryWorkItem = nil
        openConfirmationWorkItem?.cancel()
        openConfirmationWorkItem = nil
    }

    private func publish(_ status: String) {
        onStateChanged?(status)
    }
}

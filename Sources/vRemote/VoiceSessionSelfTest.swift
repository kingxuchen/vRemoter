#if DEBUG
import CoreAudio
import Foundation

enum VoiceSessionSelfTest {
    private final class Harness {
        let coordinator: X6SessionCoordinator
        var clock = Date(timeIntervalSince1970: 1_000)
        var triggerTapCount = 0
        var routeChanges = [Bool]()
        var openRequests = [(VoiceRemoteID, Bool)]()
        var closeRequestCount = 0
        var openResults = [RemoteMicrophoneOpenResult]()
        var preferredRemote: VoiceRemoteID? = .chromecast

        init(shortcutConfigured: Bool = true) {
            var routeSink: ((Bool) -> Void)?
            var triggerSink: (() -> Void)?
            var nowSink: (() -> Date)?
            coordinator = X6SessionCoordinator(
                setRemoteRouteActive: { routeSink?($0) },
                triggerTap: { triggerSink?() },
                triggerAvailable: { shortcutConfigured },
                now: { nowSink?() ?? Date(timeIntervalSince1970: 0) }
            )
            routeSink = { [weak self] active in
                self?.routeChanges.append(active)
            }
            triggerSink = { [weak self] in
                self?.triggerTapCount += 1
            }
            nowSink = { [weak self] in
                self?.clock ?? Date(timeIntervalSince1970: 0)
            }
            coordinator.preferredRemoteProvider = { [weak self] in
                self?.preferredRemote
            }
            coordinator.onMicrophoneOpenRequested = {
                [weak self] remote, bypass in
                guard let self else { return .unavailable }
                self.openRequests.append((remote, bypass))
                return self.openResults.isEmpty
                    ? .sent
                    : self.openResults.removeFirst()
            }
            coordinator.onMicrophoneCloseRequested = { [weak self] in
                self?.closeRequestCount += 1
            }
            coordinator.start()
        }

        func advance(_ seconds: TimeInterval) {
            clock = clock.addingTimeInterval(seconds)
        }

        /// One physical press of the voice key, as the remote announces it.
        func pressVoiceKey(_ remote: VoiceRemoteID = .chromecast, reason: UInt8 = 0x03) {
            coordinator.voiceKeyPressed(remote: remote, reason: reason)
        }

        /// The user letting go of that button.
        func releaseVoiceKey(_ remote: VoiceRemoteID = .chromecast, reason: UInt8 = 0x02) {
            coordinator.remoteAudioStopped(remote: remote, reason: reason)
        }

        /// Far enough apart that the debounce window has passed.
        func secondPress(_ remote: VoiceRemoteID = .chromecast) {
            advance(1.0)
            pressVoiceKey(remote)
        }
    }

    private final class CheckContext {
        private(set) var failures = 0

        func expect(
            _ condition: @autoclosure () -> Bool,
            _ message: String
        ) {
            if condition() {
                VoiceSessionSelfTest.emit("[SELF-TEST] PASS \(message)")
            } else {
                failures += 1
                VoiceSessionSelfTest.emit("[SELF-TEST] FAIL \(message)")
            }
        }
    }

    private static func emit(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    static func run() -> Bool {
        let checks = CheckContext()
        testFirstPressOpensAndEmits(checks)
        testSecondPressClosesAndEmits(checks)
        testReleaseDoesNotClose(checks)
        testReleaseReRequestsThePersistentStream(checks)
        testCloseStopsReRequesting(checks)
        testCloseSettlesBackToClosed(checks)
        testRepeatedTogglesKeepWorking(checks)
        testTransportAcknowledgementIsNotAPress(checks)
        testBothRemotesStillPressOnceEach(checks)
        testDuplicateEdgesToggleOnce(checks)
        testRapidDoublePressRoundTrips(checks)
        testKeyboardOpenAndRemoteClose(checks)
        testRemoteOpenAndKeyboardClose(checks)
        testNoShortcutMeansNoEmission(checks)
        testIndependentRemotesToggleOnce(checks)
        testDebouncedRetry(checks)
        emit("[SELF-TEST] completed failures=\(checks.failures)")
        return checks.failures == 0
    }

    private static func testFirstPressOpensAndEmits(_ c: CheckContext) {
        let h = Harness()
        h.pressVoiceKey()
        c.expect(h.triggerTapCount == 1, "the first press emits one shortcut")
        c.expect(h.routeChanges == [true], "the first press opens the audio route")
        c.expect(h.openRequests.count == 1, "the first press opens the remote microphone")
        c.expect(h.openRequests.first?.0 == .chromecast, "it opens the pressed remote")
        c.expect(h.coordinator.debugSnapshot.phase == "open", "the session is open immediately — there is nothing to confirm")
    }

    private static func testSecondPressClosesAndEmits(_ c: CheckContext) {
        let h = Harness()
        h.pressVoiceKey()
        h.secondPress()
        c.expect(h.triggerTapCount == 2, "the second press emits the shortcut again")
        c.expect(h.coordinator.debugSnapshot.phase == "closing", "the second press closes")
        c.expect(h.openRequests.count == 1, "the second press never reopens the microphone")
    }

    private static func testReleaseDoesNotClose(_ c: CheckContext) {
        // The user asked for a toggle, not hold-to-talk. Letting go of the button
        // is the tail of the press that already opened the session.
        let h = Harness()
        h.pressVoiceKey()
        h.releaseVoiceKey()
        c.expect(h.triggerTapCount == 1, "releasing must not emit a second shortcut")
        c.expect(h.coordinator.debugSnapshot.phase == "open", "releasing must not close the session")
        c.expect(h.routeChanges == [true], "releasing must not drop the audio route")
    }

    private static func testReleaseReRequestsThePersistentStream(_ c: CheckContext) {
        // Regression. The remote streams by itself while its button is down, so
        // the open request made on the press comes back "already streaming" and
        // no MIC_OPEN is ever sent. Once the button is up the remote stops, and
        // without asking again the microphone stays shut — which reads to the
        // user as hold-to-talk, the exact behaviour they asked to remove.
        let h = Harness()
        h.pressVoiceKey()
        c.expect(h.openRequests.count == 1, "the press asks once")
        h.releaseVoiceKey()
        c.expect(h.openRequests.count == 2, "the release must ask again for a persistent stream")
        c.expect(
            h.openRequests.last?.1 == true,
            "the re-request bypasses the transport debounce"
        )
        c.expect(
            h.coordinator.debugSnapshot.openRequestedRemote == .chromecast,
            "the re-request becomes the pending open"
        )
    }

    private static func testCloseStopsReRequesting(_ c: CheckContext) {
        let h = Harness()
        h.pressVoiceKey()
        h.secondPress()
        let before = h.openRequests.count
        h.releaseVoiceKey()
        c.expect(
            h.openRequests.count == before,
            "a release after the user stopped must not reopen the microphone"
        )
    }

    private static func testDuplicateEdgesToggleOnce(_ c: CheckContext) {
        // One physical press can arrive over BLE audio and HID at once. Two
        // edges would toggle twice and leave the session unchanged, which reads
        // as a dead button.
        let h = Harness()
        h.pressVoiceKey()
        h.advance(0.02)
        h.coordinator.remoteHIDShortPress()
        c.expect(h.triggerTapCount == 1, "a press announced twice still toggles once")
        c.expect(h.openRequests.count == 1, "a press announced twice opens once")
    }

    private static func testRapidDoublePressRoundTrips(_ c: CheckContext) {
        let h = Harness()
        h.pressVoiceKey()
        h.secondPress()
        c.expect(h.triggerTapCount == 2, "two separate presses emit twice")
        c.expect(h.coordinator.debugSnapshot.phase == "closing", "two presses return from opening")
    }

    private static func testKeyboardOpenAndRemoteClose(_ c: CheckContext) {
        let h = Harness()
        h.coordinator.triggerDownObserved(isSynthetic: false)
        c.expect(h.triggerTapCount == 0, "a physical keyboard press is not replayed")
        c.expect(h.openRequests.first?.0 == .chromecast, "the keyboard press picks the preferred remote")
        h.secondPress()
        // Opening by keyboard needed no synthetic trigger, because the physical
        // key already reached the app. Closing always needs one: without it
        // nothing would stop the app that the physical key started.
        c.expect(h.triggerTapCount == 1, "closing emits one shortcut so the app stops")
        c.expect(h.coordinator.debugSnapshot.phase == "closing", "the remote can close a keyboard-opened session")
    }

    private static func testRemoteOpenAndKeyboardClose(_ c: CheckContext) {
        let h = Harness()
        h.pressVoiceKey()
        h.advance(0.2)
        h.coordinator.triggerDownObserved(isSynthetic: false)
        c.expect(h.triggerTapCount == 1, "the keyboard close adds no synthetic trigger")
        c.expect(h.openRequests.count == 1, "closing cannot reopen the microphone")
        c.expect(h.coordinator.debugSnapshot.phase == "closing", "the keyboard can close a remote-opened session")
    }

    private static func testNoShortcutMeansNoEmission(_ c: CheckContext) {
        // With no shortcut configured the voice key must not start a session:
        // opening the microphone with nothing recording looks like a broken mic.
        let h = Harness(shortcutConfigured: false)
        h.pressVoiceKey()
        c.expect(h.triggerTapCount == 0, "no configured shortcut means no emission")
        c.expect(h.coordinator.debugSnapshot.phase == "closed", "no configured shortcut means no session")
    }

    private static func testIndependentRemotesToggleOnce(_ c: CheckContext) {
        let h = Harness()
        h.pressVoiceKey(.x6, reason: 0x00)
        c.expect(h.triggerTapCount == 1, "an X6 press emits one shortcut")
        h.advance(0.5)
        h.pressVoiceKey(.chromecast)
        c.expect(h.triggerTapCount == 2, "a press from the other remote still toggles")
        c.expect(h.coordinator.debugSnapshot.phase == "closing", "the session is not scoped to one remote")
    }


    private static func testCloseSettlesBackToClosed(_ c: CheckContext) {
        // Regression. The close path used to end in a verification step that also
        // returned the phase to .closed. Removing it left the session dangling in
        // .closing, so every later press was discarded as "while closing": the
        // third press did nothing and the user had to hold the button instead.
        let h = Harness()
        h.pressVoiceKey()
        h.secondPress()
        c.expect(h.coordinator.debugSnapshot.phase == "closing", "the second press begins closing")
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        c.expect(
            h.coordinator.debugSnapshot.phase == "closed",
            "closing must settle, or every later press is swallowed"
        )
    }

    private static func testRepeatedTogglesKeepWorking(_ c: CheckContext) {
        // The user asked for press/press/press/press to alternate open and
        // closed indefinitely. Two cycles is enough to catch a session that
        // latches after the first close.
        let h = Harness()
        for cycle in 1...2 {
            // A person cannot press twice inside the debounce window, so let the
            // fake clock reflect that rather than testing an unreachable timing.
            h.advance(1.0)
            h.pressVoiceKey(.chromecast)
            c.expect(
                h.coordinator.debugSnapshot.phase == "open",
                "cycle \(cycle): a press opens"
            )
            c.expect(
                h.triggerTapCount == cycle * 2 - 1,
                "cycle \(cycle): a press emits exactly one more shortcut"
            )

            h.secondPress(.chromecast)
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
            c.expect(
                h.coordinator.debugSnapshot.phase == "closed",
                "cycle \(cycle): the next press closes and settles"
            )
            c.expect(
                h.triggerTapCount == cycle * 2,
                "cycle \(cycle): closing emits the shortcut again"
            )
        }
        c.expect(h.openRequests.count == 2, "each open asks for the microphone once")
    }


    private static func testTransportAcknowledgementIsNotAPress(_ c: CheckContext) {
        // Regression. The remote answers a host mic-open request with an
        // AUDIO_START. On a Chromecast that arrives as reason 0x00, while a real
        // press is 0x03, so treating every AUDIO_START as a press made each open
        // immediately followed by a close.
        let h = Harness()
        h.pressVoiceKey(.chromecast, reason: 0x03)
        c.expect(h.coordinator.debugSnapshot.phase == "open", "a Chromecast 0x03 press opens")

        h.advance(1.0)
        h.coordinator.voiceKeyPressed(remote: .chromecast, reason: 0x00)
        c.expect(
            h.coordinator.debugSnapshot.phase == "open",
            "a Chromecast 0x00 is a transport acknowledgement and must not toggle"
        )
        c.expect(
            h.triggerTapCount == 1,
            "an acknowledgement must not emit the shortcut again"
        )
    }

    private static func testBothRemotesStillPressOnceEach(_ c: CheckContext) {
        // The physical-press reason differs per remote, so a rule that only fits
        // one of them would silently break the other.
        let chromecast = Harness()
        chromecast.pressVoiceKey(.chromecast, reason: 0x03)
        c.expect(
            chromecast.coordinator.debugSnapshot.phase == "open",
            "Chromecast still opens on its own press reason"
        )

        let x6 = Harness()
        x6.pressVoiceKey(.x6, reason: 0x00)
        c.expect(
            x6.coordinator.debugSnapshot.phase == "open",
            "X6 still opens on its own press reason"
        )
        x6.advance(1.0)
        x6.coordinator.voiceKeyPressed(remote: .x6, reason: 0x03)
        c.expect(
            x6.coordinator.debugSnapshot.phase == "open",
            "X6 treats 0x03 as an acknowledgement, not a second press"
        )
    }

    private static func testDebouncedRetry(_ c: CheckContext) {
        let h = Harness()
        h.openResults = [.retryAfter(0.02), .sent]
        h.pressVoiceKey()
        c.expect(h.coordinator.debugSnapshot.openRequestedRemote == nil, "a debounced request is not marked sent")
        RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        c.expect(h.openRequests.count == 2, "a debounced open receives a bounded retry")
        c.expect(
            h.coordinator.debugSnapshot.openRequestedRemote == .chromecast,
            "only the sent retry becomes pending"
        )
    }
}
#endif

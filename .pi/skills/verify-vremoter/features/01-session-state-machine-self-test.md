# Session state-machine self-test

## Sub-features

- **Voice session lifecycle.** Opening on a voice-key press, closing on the second press, cross-closing from keyboard or remote, and two remotes streaming independently.
- **Remote microphone transport.** Requests to open / close the remote's ATVV microphone channel, including debounce and bounded retry.
- **Phase reporting.** The coordinator's phase, generation counter, streaming-remote set, and pending open request, exposed for assertion.

This is the highest-value automated seam in the project: it drives the real coordinator through injected collaborators and a fake clock, with no hardware, no audio device, and no Bluetooth.

## How to get to it (user POV)

Not a user surface. It is the command-line entry the project ships for exactly this purpose — an engineer proving the session logic still behaves after a change.

## Driving it with terminal

```bash
cd <repo>
swift build
.build/debug/vRemote --voice-session-self-test
```

Exit code `0` = every assertion passed. Non-zero = at least one `FAIL`.

Read the transcript for the assertion messages; the count is not on stdout, so grep the final line:

```bash
.build/debug/vRemote --voice-session-self-test 2>&1 | tee "$EVIDENCE/self-test.txt"
echo "${PIPESTATUS[0]}" > "$EVIDENCE/self-test.exit"
```

Expect a final `[SELF-TEST] completed failures=0`.

**This mode is fully isolated.** The flag is handled before `NSApplication.shared`, so it creates no audio pipe, no BLE connection, and no menu-bar item, and never touches `vRemoteDr 2ch`. It is safe to run while the user's real app is open. No Doctor check needed for this feature.

## Gotchas

- **DEBUG only.** The flag lives behind `#if DEBUG`. A release binary silently ignores it and launches the GUI instead — that would make a verification run start a second app instance. Always use `.build/debug/`.
- **stdout and stderr both.** Assertions go to stderr. Redirecting only stdout produces an empty-looking transcript that looks like a hang.
- **The fake clock is injected.** Some cases advance time explicitly and one uses a real `RunLoop` wait. A run that appears to hang is usually that one; give it a bounded timeout rather than assuming failure.
- **Assertion names are the contract.** When the session semantics change, existing assertion messages are rewritten in place rather than deleted, so the transcript keeps naming the behavior that is being guaranteed. A dropped assertion is a silent coverage loss.
- **Proven when this skill was generated:** exit 0, 10 cases, `[SELF-TEST] completed failures=0`. Re-prove after every change to the coordinator.

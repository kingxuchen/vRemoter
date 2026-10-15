---
name: verify-vremoter
description: Verify vRemoter (macOS menu-bar app) by driving the real app — launch it, exercise the Studio Mixer, button mapping, voice trigger key, and the headless session self-test, and capture evidence. Use when changing vRemoter behavior, verifying a release build, or when a change needs proof beyond unit self-tests. NOT for vRemoter's web site (docs/) or the update/commerce server.
---

# Verify vRemoter

vRemoter is a **macOS accessory (menu-bar) app** — `LSUIElement=true`, no Dock icon. It turns a Bluetooth voice remote (X6-Remote, Chromecast Voice Remote) into a microphone for the Mac, mixing the remote mic with the MacBook mic into a CoreAudio input device named `vRemoteDr 2ch`.

This skill drives the real app. It is written to be read cold by an agent that has never seen this project.

---

## Hard constraint: singleton. Never double-drive.

**vRemoter must never run as two instances.**

The app creates an IOProc on `vRemoteDr 2ch`, a single system-wide CoreAudio input device. A second instance attaches a second IOProc to the same device and **breaks audio for the user**. There is also one menu-bar item, one shared `UserDefaults` domain, and one BLE connection.

**The Doctor refuses to proceed if an instance is already running.** Do not work around it. Do not kill an instance you did not start — on a developer machine that instance is usually the user's real running app, launched from `/Applications/vRemote.app`, not from this checkout.

If Doctor reports a foreign instance, stop and ask the user to quit it, or get explicit permission to take it over.

---

## Launch

There are two launch modes. Pick by what you are verifying.

### Mode A — headless state-machine self-test (isolated, preferred default)

```bash
cd <repo>
swift build
.build/debug/vRemote --voice-session-self-test
```

This mode is **fully isolated**: the flag is handled before `NSApplication.shared` is created, so it starts no audio pipe, opens no Bluetooth connection, installs no menu-bar item, and never touches `vRemoteDr 2ch`. Safe to run while the user has the real app open.

Ready when: it exits. Success is exit code `0` with a `[SELF-TEST] completed failures=0` final line; each assertion prints `[SELF-TEST] PASS|FAIL <message>`. Any failure exits non-zero.

Only available in DEBUG (`#if DEBUG`) — it will not exist in a release build.

### Mode B — the real GUI app

Requires exclusive ownership of the singleton. Quit any running instance first (ask the user; do not kill it yourself).

```bash
cd <repo>
swift build
MIA_DIAGNOSTICS=1 nohup .build/debug/vRemote > "$EVIDENCE/app-stdout.txt" 2>&1 &
disown
```

**Detach it, or it dies with your shell.** A backgrounded process is reaped when the launching shell session ends and the app goes with it — silently, leaving an empty log, which reads like a crash but is not one. Note the pid; cleanup needs it and must not substitute a name.

For a faithful release-surface run, build the bundle instead:

```bash
./package-app.sh                 # swift build -c release + bundle + ad-hoc sign
open dist/build/vRemote.app     # or: dist/build/vRemote.app/Contents/MacOS/vRemote
```

Ready when: a `vRemoter` menu-bar item appears. It is an image-only status item, so **there is no text label to match** — locate it by process (`pgrep -f vRemote`) then by window. Opening the console is the reliable readiness signal:

- Menu bar item → `控制台` / `Console` → `打开前台控制台` / `Open console`
- The console window's title is `vRemoter 控制台` / `vRemoter Console`. Its absence means the app did not finish launching.

Note `swift build` produces a bare executable, not a bundle, so `LSUIElement` does not apply and the app may also appear in the Dock. That is expected for a debug run and not a defect.

**A bare debug executable is invisible to app-level discovery.** Tools that enumerate applications by bundle id or `.app` path — including `list_apps` — will not find it. Address it by pid instead:

```bash
mcp_cua-driver_list_windows pid=<pid you launched>
```

The console window opens by itself on a first run, because the remote-mic hint stays up until the user completes that test. "The console is already open" is not evidence you skipped a step.

### Environment preconditions

| Precondition | How to check | If missing |
|---|---|---|
| Audio driver installed | `ls /Library/Audio/Plug-Ins/HAL/vRemoteDriver.driver` | The app runs but the console reports the driver unavailable, and **nothing audio-related can be verified**. Say so rather than reporting a product failure. |
| Paired remote | `system_profiler SPBluetoothDataType \| grep -i remote` | The session state machine can still be verified headlessly. Real remote audio cannot. |
| Accessibility / Input Monitoring / Microphone grants | console permission section | Grant via the console's permission walkthrough, or the `--permission-demo` flag for a dry look without real prompts. |
| Microphone grant, bare executable | console permission section | **A bare debug executable has no microphone grant.** TCC attributes grants to a bundle; without one they land elsewhere and the console reports `未授权`. Audio capture is unverifiable in this mode — that is the harness, not a product defect. Use the packaged app, or grant to the launching terminal. |

**The console window will not resize.** It is laid out at a fixed 775x686, and a request to make it taller reports that the geometry did not settle. Content below that height is unreachable and absent from the accessibility tree. Do not spend turns retrying the resize — use a demo flag to reach the screen you need.

---

## Doctor

Read-only. Run this first whenever anything looks off, and always before launching Mode B.

```bash
# The app process only. A naive `pgrep -fl vRemote` also matches the always-on
# HAL process "Core Audio Driver (vRemoteDriver.driver)" and would report a
# running instance on every machine that has the driver installed.
pgrep -fl 'MacOS/vRemote$|\.build/.*/vRemote$'
ls -d /Library/Audio/Plug-Ins/HAL/vRemoteDriver.driver
```

Interpretation:

- **Any app pid present** → a foreign instance is running. Mode B is blocked until it is gone. If its path is under `/Applications/`, it is almost certainly the user's own app: ask, do not kill.
- **A pid whose path is under this checkout's `.build/` or `dist/`** → it is a leftover from a previous verification run. You may kill that exact pid (see Cleanup).
- **`Core Audio Driver (vRemoteDriver.driver)` in the output is not the app.** It is the audio HAL process and is expected whenever the driver is installed. Ignore it; use the filtered command above.
- **Driver missing** → Mode A still works; Mode B is worthless for audio.

---

## Drive

Use `cua-driver` (macOS accessibility + screenshots). It is the right harness here: this is a native AppKit menu-bar app, so there is no web surface, no debug port, and no test-only HTTP endpoint to hit.

Order of operations to reach the app:

1. `mcp_cua-driver_list_windows` with `app: vRemote` (or `pgrep` for the pid) to find the console window id.
2. `mcp_cua-driver_get_window_state` with that pid/window id to get the accessibility tree. **Read this before clicking anything** — it gives you the element tokens.
3. Menu bar items are reachable by title. Stable titles, both languages:

| Menu path | Title (zh / en) |
|---|---|
| Console | `控制台` / `Console` |
| Open console | `打开前台控制台` / `Open console` |
| Stop microphone | `关闭麦克风` / `Stop microphone` |
| Restart app | `重启 App` / `Restart app` |
| Logs | `日志` / `Logs` |
| Record logs | `记录日志` / `Record logs` |
| Debug recordings | `调试录音` / `Debug recordings` |
| Save WAV and raw data | `保存 WAV 与原始数据` / `Save WAV and raw data` |
| Version & Updates | `版本与更新…` / `Version & Updates…` |
| Quit | `退出` / `Quit` (also ⌘Q) |

4. Inside the console, prefer accessibility labels over coordinates. Console sections carry explicit labels; the remote status row reads `"\(title), connected"` or `"\(title), offline"`.
5. Prefer `mcp_cua-driver_click` with an `element_token`. Use pixel coordinates only for surfaces missing from the tree.

**Read the whole tree before clicking.** SwiftUI exposes fewer elements than are on screen. The mixer page reported 13 actionable elements while the mapping page reported 33 — content plainly visible in a screenshot may simply not be addressable.

**Two probes worth knowing:**

- Enumerate a native popup's options without changing it: call `set_value` with a value that cannot exist. The call fails and returns the complete option list. This is how the voice trigger key's real option set was captured as evidence.
- A new snapshot invalidates every prior one. Re-read the window after anything that changes the UI, or you will act on stale tokens.

Demo flags for driving specific screens without waiting on real conditions — useful when the UI itself changed:

```bash
.build/debug/vRemote --permission-demo
.build/debug/vRemote --mapping-window-demo      # opens the console on the mapping page
.build/debug/vRemote --updates-window-demo
.build/debug/vRemote --purchase-demo
.build/debug/vRemote --donation-prompt-demo
```

### Driving the voice trigger key (the setting this project is changing)

The voice key setting is a picker in the console. To record a shortcut: focus the picker, then press the combination. The existing global keyboard tap in the app observes physical keys and distinguishes its own synthetic events by a marker, so a recording is a real user action.

When verifying a recorded shortcut, verify **both** directions:
- the console echoes what was recorded, and
- pressing the remote voice key actually emits that combination.

The second half needs a paired remote. Without one, verify the first half and say the second is unverified — do not report it as passing.

---

## Evidence

Capture to `.verification/<UTC timestamp>/` in the repo root (already gitignored).

| What | Where it goes |
|---|---|
| Self-test transcript | `self-test.txt` (stdout+stderr) and `self-test.exit` |
| Accessibility tree | `<feature>-tree.md` |
| Screenshot | `<feature>-<step>.png` |
| App log | copied from `~/Library/Logs/vRemote/vRemote.log` → `app.log` (needs `记录日志` on) |
| Recorded audio | copied from `~/Library/Application Support/vRemote/Recordings/` → `recordings/` (needs `保存 WAV 与原始数据` on) |
| Audio meter | `MIA_DIAGNOSTICS=1` prints `[AUDIO-METER] mix=… macBuffers=… peak=…` once per second on stderr → `audio-meter.txt` |

### Proof standards

- Exercise the **real user path**. A proof that calls an internal setter, or that flips a `UserDefaults` key and declares victory, is not a proof.
- Capture the **action and the resulting state**, not just a final screenshot. A screenshot showing a state you cannot connect to an action proves nothing.
- Verify **side effects** alongside what is visible: after recording audio, a WAV must actually exist and be non-empty; after enabling logs, the log file must actually grow.
- A dry-run or demo flag is a way to reach a screen, **never** a way to prove a behavior. `--permission-demo` shows what the walkthrough looks like; it does not prove a grant succeeded. When a safe path exists, verify what it actually skips by observing (files, network, git refs) rather than trusting its name.
- If the environment lacks a precondition, **report the failure and the reason**. Never weaken the journey to make it pass.

---

## Cleanup

Tear down only what this run created.

- **Kill by the exact pid you started**, never by process name — `pkill vRemote` would kill the user's own app.
  ```bash
  kill <pid>          # the pid captured at launch
  ```
  The app installs a `SIGTERM` handler that converts the signal into a normal AppKit termination, so the Option event tap and the CoreAudio IOProc are released cleanly. Prefer `kill` over `kill -9`.
- Leave `~/Library/Logs/vRemote/` and `~/Library/Application Support/vRemote/` in place; they are the user's data. Copy, never delete.
- Turn off `记录日志` / `保存 WAV 与原始数据` if you enabled them, so the app does not keep writing.
- **Never delete `.verification/`.** Evidence must survive teardown; a cleanup that eats the proof fails the run.

---

## Helpers

None shipped yet. If you add one, put it in `.pi/skills/verify-vremoter/scripts/`, make it executable, and show its exact invocation in this file. A helper the reader has to reverse-engineer is not a helper.

---

## Feature map

See `features/README.md`. Each feature file covers what it is, how to reach it, how to drive it, and its gotchas.

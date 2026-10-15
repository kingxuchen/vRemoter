# Studio Mixer

## Sub-features

- **Input selection.** Independent checkboxes for the MacBook microphone and the remote microphone.
- **Level meters.** Two meters driven by the mix, the remote one from the remote's audio level.
- **Session state text.** A status line describing what the session is doing.
- **Driver availability.** Whether `vRemoteDr 2ch` is present.
- **Stop microphone.** A single action that closes the session.
- **Permission status.** Microphone / Accessibility / Input Monitoring / Bluetooth grants.

## How to get to it (user POV)

Click the `vRemoter` menu-bar item → `控制台` / `Console` → `打开前台控制台` / `Open console`. The window opens on the mixer page.

## Driving it with cua-driver

1. `mcp_cua-driver_list_windows` → find the console window (`title` contains `vRemoter`).
2. `mcp_cua-driver_get_window_state(pid, window_id)` → read the tree, get element tokens.
3. Toggling an input checkbox: `mcp_cua-driver_click` with that checkbox's token. Confirm the change with `mcp_cua-driver_get_window_state` and the tree's `value` / `selected`, not by eyeballing the screenshot.
4. Screenshot each state to `$EVIDENCE/mixer-<step>.png`.

**Do not drive this feature while another vRemoter instance is running.** Two instances attach two IOProcs to the same `vRemoteDr 2ch` and break the user's audio. See the singleton rule in the skill.

## Gotchas

- **The app has no Dock icon** (`LSUIElement`). If you are hunting for a window and find none, the app did not launch — check `pgrep -fl vRemote`.
- **The console window title is localized**: `vRemoter 控制台` / `vRemoter Console`. Match on `vRemoter`, not the full string.
- **Meters do not move without audio.** With no driver installed or no paired remote, the level values sit at their floor. That is the environment, not a defect — report it as such.
- **Toggling an input is a real setting**, persisted to `UserDefaults`, and it affects every later session. Restore it when the run finishes unless the run's purpose was to change it.
- **The permission section is not proof of a grant.** Verify a grant by observing the real system state, not by reading the console's own checkbox.

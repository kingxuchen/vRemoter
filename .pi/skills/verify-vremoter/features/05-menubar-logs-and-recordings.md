# Menu bar, logs, recordings

## Sub-features

- **Menu-bar status item.** Image-only, no text label; its tooltip reads `vRemoter · <status>`.
- **Control submenu.** Open console, stop microphone, restart app.
- **Logs submenu.** Toggle recording, refresh on-disk size. Log file rotates at 5 MB.
- **Debug recordings submenu.** Toggle saving WAV plus raw data, refresh on-disk size.
- **Utility items.** Launch at login, language, version & updates, donation, quit.
- **Diagnostics meter.** `MIA_DIAGNOSTICS=1` prints a per-second audio meter to stderr.

## How to get to it (user POV)

Click the `vRemoter` menu-bar item. There is no Dock icon — `LSUIElement` is set.

## Driving it with cua-driver

The menu bar is a separate surface from the console window. Open it by targeting the status item:

1. `mcp_cua-driver_get_window_state` on the system menu-bar region, or `mcp_cua-driver_click` at the status item found via `mcp_cua-driver_get_cursor_position` after locating it in a desktop capture.
2. Menu items are matched by **title**, in either language — see the table in the skill's Drive section. Titles are the stable handle; do not use menu positions.
3. Submenus open on hover; use `mcp_cua-driver_click` on the parent, then on the child.

### Verifying side effects, not just menu state

Toggling a switch proves nothing on its own. Confirm the effect on disk:

```bash
# logs
ls -l ~/Library/Logs/vRemote/vRemote.log
tail -f ~/Library/Logs/vRemote/vRemote.log     # while an action runs

# debug recordings
ls -l ~/Library/Application\ Support/vRemote/Recordings/
```

Enable `记录日志` / `Save WAV and raw data`, perform an action, then assert a **new** file appeared or the existing one grew. Copy the artifact into `$EVIDENCE/` before cleaning up.

### Audio meter

```bash
MIA_DIAGNOSTICS=1 .build/debug/vRemote 2> "$EVIDENCE/audio-meter.txt"
```

Emits one `[AUDIO-METER] mix=… macBuffers=… remoteBuffers=… peak=… renders=…` line per second. `mix=on` with `remoteBuffers=0` while the remote mic should be open is a real finding worth reporting.

## Gotchas

- **The status item has no text.** Any approach that matches on a visible label for it will fail. Match on process + tooltip, or capture the menu-bar region.
- **Menu titles are localized.** The app runs in `zh_CN` by default (`CFBundleDevelopmentRegion`), and the language submenu can switch it. Match on the table's zh title, en title, or both.
- **`日志` size entries are display-only.** A menu item whose title starts with `占用 ·` is a label, not an action — clicking it does nothing.
- **Log recording defaults to off** and the app registers that default; reading it back is not proof the file is being written. Check the file's mtime and size.
- **Log and recording paths are the user's data.** Copy them; never delete them during cleanup.

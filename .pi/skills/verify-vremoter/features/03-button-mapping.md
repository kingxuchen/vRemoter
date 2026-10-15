# Button mapping

## Sub-features

- **Per-model mapping.** X6-Remote and Chromecast Voice Remote each carry their own saved mapping, so replacing a remote with another unit of the same model keeps working.
- **Enable / disable interception.** Off restores the system's original button behavior; on intercepts the device's reports and sends the chosen macOS action instead.
- **Action assignment.** Keyboard keys, media keys, and custom shortcuts per remappable button.
- **Reset.** Return a button to its default.
- **Disabled action.** Every remappable button can be turned off individually.

## How to get to it (user POV)

Console → the button-mapping page.

To land directly on that page without clicking through:

```bash
.build/debug/vRemote --mapping-window-demo
```

This is a DEBUG flag that opens the console already on the mapping page. It is a way to **reach** the screen, never a proof that mapping works.

## Driving it with cua-driver

1. Launch with `--mapping-window-demo` (DEBUG only).
2. `mcp_cua-driver_get_window_state` → read the tree before clicking.
3. Change one button's action, then assert the change two ways: the control's new value in the tree, **and** the persisted `UserDefaults` value for that model.
4. Enable interception, then press the physical remote button and observe the resulting macOS action.
5. Screenshot before and after to `$EVIDENCE/mapping-<step>.png`.

## Gotchas

- **The voice button is not freely remappable.** It is reserved for voice control. Attempts to map it will not do what a user expects.
- **The X6 mouse-mode switch key is handled inside the device firmware** and cannot be remapped from macOS. If a journey expects it to be remappable, that is a product limitation — report it, do not treat it as a regression.
- **Mapping is per-model, not per-device.** Verification must switch the model selector between X6 and Chromecast and confirm each has its own saved mapping.
- **Enabling interception suppresses the device's original action.** Verify with interception both off (system behavior returns) and on (the chosen action fires).
- **Requires a paired remote.** Without hardware, mapping changes can be saved and read back, but pressing a button is not provable. Say so.
- **DEBUG flag only** — see feature 01's gotcha about release builds.

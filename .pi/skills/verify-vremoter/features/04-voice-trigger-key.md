# Voice trigger key

**This is the feature the current work changes.** Read this file before touching the trigger-key setting.

## Sub-features

- **Choosing the shortcut the voice key emits.** Historically a fixed list of modifier keys. Being changed to a recorded arbitrary combination — a user clicks a picker, presses the combination they want, and it is stored as a key code plus modifier flags.
- **Echo.** The setting shows what was recorded in a readable form.
- **Clear / re-record / cancel.** Re-record overwrites, clear returns to unconfigured, cancel leaves the saved value untouched.
- **Unconfigured state.** With no shortcut configured, the voice key must do nothing at all — no emitted event and no microphone opening — and the console must say to configure one first.
- **Legacy migration.** Existing 1.1.1 users must keep their current behavior after upgrading.

## How to get to it (user POV)

Console → the **按键映射** (button mapping) page. It is **not** on the mixer page — verified against a running build, where the mixer page exposed no trigger-key control at all.

It sits at the top of the mapping page as a native popup button whose accessibility label is `触发键` / `Trigger`.

## What it looks like today (captured 2026-10-15)

The running app's popup offered exactly these five options:

```
Option (⌥)   Command (⌘)   Control (⌃)   Shift (⇧)   Fn / Globe
```

Five fixed entries, **no left/right distinction**, no combination with a main key. Right Control — Type4Me's default voice trigger — cannot be selected. This is the defect the current work removes.

Re-capture the option list any time with `set_value` on the popup using a value that cannot exist; it fails and returns the full list.

**When this setting changes, the accessibility role changes with it.** It is an `AXPopUpButton` today. A recording picker is a different control, so the selector in this file must be updated in the same change that changes the UI — otherwise verification silently stops finding the field.

## Driving it with cua-driver

Recording is a **real user action**: focus the picker, then press the combination with the keyboard. The app's global keyboard tap observes physical keys and tags its own synthetic events with a marker, so a recording is indistinguishable from a genuine keypress to the rest of the system.

1. `mcp_cua-driver_get_window_state` → find the picker.
2. `mcp_cua-driver_click` on the picker (or `mcp_cua-driver_press_key` with a `tab` token) to enter recording state.
3. `mcp_cua-driver_type_text` / `mcp_cua-driver_hotkey` to press the combination to record.
4. Confirm the echo in the tree.
5. Screenshot to `$EVIDENCE/trigger-key-<step>.png`.

### Verifying the two directions separately

Recording the shortcut and emitting it are **different proofs**. Do not report the second as passing when you only checked the first.

| Direction | Needs | Verify by |
|---|---|---|
| Record → stored → echoed | nothing | console echo + the persisted default value |
| Emit → the target app receives it | a **paired remote** | press the remote voice key, observe the target app react |

The second is the one that matters to a user and the one most likely to be unverifiable in a bare environment.

### Known sharp edge: `register(defaults:)` hides whether a user ever set this

The app registers a default for the trigger key at startup. That means reading the key through `UserDefaults.standard` returns a value **whether or not the user ever chose one** — a fresh install and a legacy user are indistinguishable through that path.

Migration logic that must distinguish them has to read the **persisted** domain rather than the registered defaults, e.g. by inspecting the app's persistent domain for the bundle id `local.simaqingfeng.vRemote`. A migration check that reads `UserDefaults.standard` will silently classify every legacy user as unconfigured.

Verify this explicitly: check that the migration decision differs between a domain containing the key and an empty one.

## Gotchas

- **A bare debug executable is not a bundle**, so it writes defaults under a different domain than the packaged app. Verify persistence with the packaged app, or the result will not reflect a real install.
- **The console window is fixed at 775x686 and cannot be made taller.** The trigger-key row is at the top of the mapping page, so switch to the mapping page before looking for it — do not hunt for it on the mixer page.
- **Recording is global-keyboard-driven.** Any stray keypress while recording is captured. Re-record deliberately; do not sweep the keyboard.
- **Modifiers must be set on the main key event**, not delivered as separate press/release pairs, for combinations to be recognized as a chord by the target app. Verify a multi-modifier combination explicitly — it is the case most likely to be wrong.
- **Do not kill another vRemoter instance to test this.** See the singleton rule.

# vRemoter feature map

Every user-facing feature, how to reach it, and how to prove it works. Maintained source of verification truth for this repo.

**Proof that drives one convenient entry point is incomplete when this map lists others.**

| # | Feature | Reach it by | Harness | Isolated? | Status |
|---|---|---|---|---|---|
| 01 | [Session state-machine self-test](01-session-state-machine-self-test.md) | CLI flag | terminal | ✅ fully isolated | ✅ proven |
| 02 | [Studio Mixer](02-studio-mixer.md) | Menu bar → Console | cua-driver | ⚠️ needs singleton | ✅ reachable |
| 03 | [Button mapping](03-button-mapping.md) | Console → 按键映射 | cua-driver | ⚠️ needs singleton | ✅ reachable |
| 04 | [Voice trigger key](04-voice-trigger-key.md) | Console → 按键映射 page | cua-driver | ⚠️ needs singleton | ✅ reachable |
| 05 | [Menu bar, logs, recordings](05-menubar-logs-and-recordings.md) | Menu bar item | cua-driver + filesystem | ⚠️ needs singleton | ⚠️ partial |

"Reachable" means the surface was opened and read on a running build. It does **not** mean the feature's behavior was proved — read the Gotchas in each file for what remains unverified.

## Coverage status

Driven once on 2026-10-15 against `.build/debug/vRemote` on a machine with the audio driver installed and a paired Chromecast Voice Remote.

**Proved:** feature 01 end to end — exit 0, 35 assertions, zero failures.

**Reached, not proved:** features 02, 03, 04 were opened and their accessibility trees captured. Feature 04's option set was captured as hard evidence. Not proved:

- Audio capture and the level meters — a bare debug executable has no microphone grant.
- Any remote-key press → recording path — needs the target app actually consuming `vRemoteDr 2ch`, which was not arranged.
- Feature 05's log and recording side effects — the toggles were not exercised.

Evidence for that run is in `.verification/20261015T142416Z/`.

## Known environment facts

- Audio driver installed; `vRemoteDr 2ch` reports available.
- Chromecast Voice Remote connected; X6 Remote offline.
- Type4Me runs on this machine — the natural target application for the generic voice-input work.

## Adding a feature

Add a file here with the four `H2`s: `Sub-features`, `How to get to it (user POV)`, `Driving it with cua-driver`, `Gotchas`. Link it from the table above. If a journey's precondition is not met in the current environment, the journey **reports a failure with the reason** — never weaken it to pass.

Keep the skill honest about what has actually been run. A map that claims coverage nobody exercised is worse than one that admits the gap.

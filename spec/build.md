# Build

> Coordinator-maintained narrative board. Reconcile it with the planned and active feature folders before selecting, starting, resuming, reviewing, merging, proving, or dropping work. Update it in the same coherent change that changes feature state. Drift is an advisory, never a runtime gate.

## Owner choices

- Workers and reviewers: engine `omp`, provider `anthropic`, model `claude-opus-5-5`; workers thinking `high`, reviewers `xhigh`. Never Cursor cloud agents. No model fallback: on quota or model failure, preserve work and ask.
- Spawn `--detached` always: Herdr tab switching and GUI activity must not disturb Adam, who is using the Mac.
- Hard rule for every job: never take Adam's focus or bring any window to the front; GUI checks use the repo fixture app or the Alice lab on the virtual display only.
- Hard rule (Adam, 15:00/15:03): never capture Adam's main screen. Enforced in the tool: shot/record need a target (window on the virtual display preferred, or `--display virtual`) and refuse everything else; the unlock needs both `--allow-main` and `VSCREEN_ALLOW_MAIN=1` and is Adam's alone. Jobs never use it.
- Alice repo is read only: no commits there; needed hooks go to Adam as a note.
- Review: an independent reviewer for the AX/input and permission-identity slices (focus and TCC mistakes are hard to see).
- Proof that earns PROVEN for the whole tool: a full Alice native scenario passes on the virtual display while another app stays in front. Met 2026-10-05 (F004); main now takes landings directly.
- Shared machine state across parallel jobs: one display daemon (`~/Library/Application Support/vscreen/display.json`). Use a running display or start one if absent; never stop or restart it during parallel work (windows on it would land on Adam's screen); the coordinator stops it. Quit your own fixture processes before you finish. Install your build to your own bundle (`VSCREEN_APP=/tmp/vscreen-FNNN/vscreen.app VSCREEN_LINK=/tmp/vscreen-FNNN/bin/vscreen scripts/install.sh`); same bundle id and signature keep Adam's grants. Only the coordinator installs `~/Applications/vscreen.app`.
- Never create a virtual display at a new size or identity without the F001 descriptor rules (fixed physical size, per-mode serial): a bad identity mirrored Adam's XDR once.

## TRACK

- vscreen: hidden virtual display plus focus-free window control for agents on macOS 26.5; private API risk reported plainly.

## NOW

- `F001-vscreen-core-display` (ACTIVE): on main; repair of review-1 findings (start/stop lock, origin and main/mirror guard, daemon identity, smoke and fixture bounds) next.
- `F002-window-ax-control` (ACTIVE): on main; independent review 1 next.

## NEXT

- `F005-vscreen-run` (PLANNED): `vscreen run -- CMD` moves any test's windows onto the virtual display; after the proof.

## PROVEN

- `F004-alice-native-proof` (PROVEN): Alice native chat-panels scenario passed on the virtual display, Slack frontmost in all 701 samples, lab window never on Adam's screen; spec/features/done/2026-10/F004-alice-native-proof/.
- `F003-capture` (PROVEN): shot/record of one window on the virtual display or of the virtual display; a target is required and the main screen is refused (manual double unlock only). Any capture can raise macOS's "bypass the private window picker" alert until Adam clicks Allow once (then about monthly).

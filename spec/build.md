# Build

> Coordinator-maintained narrative board. Reconcile it with the planned and active feature folders before selecting, starting, resuming, reviewing, merging, proving, or dropping work. Update it in the same coherent change that changes feature state. Drift is an advisory, never a runtime gate.

## Owner choices

- Workers and reviewers: engine `omp`, provider `anthropic`, model `claude-opus-5-5`; workers thinking `high`, reviewers `xhigh`. Never Cursor cloud agents. No model fallback: on quota or model failure, preserve work and ask.
- F006 group (Adam, 15:10): lead is this coordinator (Opus 5.5 xhigh); team members on `openai-codex/gpt-6.1-sol` (coordinator and worker thinking high) for tight fixes; the lead buys one Opus 5.5 (thinking high) review of the chosen candidate. Goal: refine without bloating logic.
- Spawn `--detached` always: Herdr tab switching and GUI activity must not disturb Adam, who is using the Mac.
- Hard rule for every job: never take Adam's focus or bring any window to the front; GUI checks use the repo fixture app or the Alice lab on the virtual display only.
- Hard rule (Adam, 15:00/15:03): never capture Adam's main screen. Enforced in the tool: shot/record need a target (window on the virtual display preferred, or `--display virtual`) and refuse everything else; the unlock needs both `--allow-main` and `VSCREEN_ALLOW_MAIN=1` and is Adam's alone. Jobs never use it.
- Alice repo is read only: no commits there; needed hooks go to Adam as a note.
- Review: an independent reviewer for the AX/input and permission-identity slices (focus and TCC mistakes are hard to see).
- Proof that earns PROVEN for the whole tool: a full Alice native scenario passes on the virtual display while another app stays in front. Met 2026-10-05 (F004); main now takes landings directly.
- Shared machine state across parallel jobs: one display daemon (`~/Library/Application Support/vscreen/display.json`). Use a running display or start one if absent; never stop or restart it during parallel work (windows on it would land on Adam's screen); the coordinator stops it. Quit your own fixture processes before you finish. Install your build to your own bundle (`VSCREEN_APP=/tmp/vscreen-FNNN/vscreen.app VSCREEN_LINK=/tmp/vscreen-FNNN/bin/vscreen scripts/install.sh`); same bundle id and signature keep Adam's grants. Only the coordinator installs `~/Applications/vscreen.app`.
- Never create a virtual display at a new size or identity without the F001 descriptor rules (fixed physical size, per-mode serial): a bad identity mirrored Adam's XDR once.

## TRACK

- vscreen: hidden virtual display plus focus-free window control for agents on macOS 26.5; private API risk reported plainly. Public at https://github.com/iceener/vscreen.

## NOW

- `F006-display-cleanup` (ACTIVE): group of two Sol teams (tight fix in the daemon vs observe-then-delete); no orphan virtual display after stop, crash, SIGHUP or logout; doctor reports and clears orphans.

## NEXT

- `F005-vscreen-run` (PLANNED): `vscreen run -- CMD` moves any test's windows onto the virtual display; after the proof.

## PROVEN

- `F007-limen-extension-optional` (PROVEN): pi and omp start in this repo without limen; the committed limen stubs load nothing when limen is absent and all hooks when it is present.
- `F002-window-ax-control` (PROVEN): window list/move, AX tree, allow-listed click, value typing without activating the app; review 1 repaired and live-checked on the fixture.
- `F001-vscreen-core-display` (PROVEN): signed bundle with its own TCC identity, daemon-held virtual display at the bottom-right corner; review 1 repaired (locks, main/mirror guard and watchdog, daemon identity).
- `F004-alice-native-proof` (PROVEN): Alice native chat-panels scenario passed on the virtual display, Slack frontmost in all 701 samples, lab window never on Adam's screen; spec/features/done/2026-10/F004-alice-native-proof/.
- `F003-capture` (PROVEN): shot/record of one window on the virtual display or of the virtual display; a target is required and the main screen is refused (manual double unlock only). Any capture can raise macOS's "bypass the private window picker" alert until Adam clicks Allow once (then about monthly).

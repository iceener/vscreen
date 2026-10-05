# Build

> Coordinator-maintained narrative board. Reconcile it with the planned and active feature folders before selecting, starting, resuming, reviewing, merging, proving, or dropping work. Update it in the same coherent change that changes feature state. Drift is an advisory, never a runtime gate.

## Owner choices

- Workers and reviewers: engine `omp`, provider `anthropic`, model `claude-opus-5-5`; workers thinking `high`, reviewers `xhigh`. Never Cursor cloud agents. No model fallback: on quota or model failure, preserve work and ask.
- Spawn `--detached` always: Herdr tab switching and GUI activity must not disturb Adam, who is using the Mac.
- Hard rule for every job: never take Adam's focus or bring any window to the front; GUI checks use the repo fixture app or the Alice lab on the virtual display only.
- Alice repo is read only: no commits there; needed hooks go to Adam as a note.
- Review: an independent reviewer for the AX/input and permission-identity slices (focus and TCC mistakes are hard to see).
- Proof that earns PROVEN for the whole tool: a full Alice native scenario passes on the virtual display while another app stays in front. Work lands on `vscreen-dev`; main receives it (fast-forward) only when the proof passes.
- Shared machine state across parallel jobs: one display daemon (`~/Library/Application Support/vscreen/display.json`). Use a running display or start one if absent; never stop or restart it during parallel work (windows on it would land on Adam's screen); the coordinator stops it. Quit your own fixture processes before you finish. Install your build to your own bundle (`VSCREEN_APP=/tmp/vscreen-FNNN/vscreen.app VSCREEN_LINK=/tmp/vscreen-FNNN/bin/vscreen scripts/install.sh`); same bundle id and signature keep Adam's grants. Only the coordinator installs `~/Applications/vscreen.app`.
- Never create a virtual display at a new size or identity without the F001 descriptor rules (fixed physical size, per-mode serial): a bad identity mirrored Adam's XDR once.

## TRACK

- vscreen: hidden virtual display plus focus-free window control for agents on macOS 26.5; private API risk reported plainly.

## NOW

- `F001-vscreen-core-display` (ACTIVE): landed on `vscreen-dev` at efc5522; Adam granted Accessibility and Screen Recording; independent review 1 running.
- `F002-window-ax-control` (ACTIVE): window list/move, AX tree, click/type against the fixture on the virtual display.
- `F003-capture` (ACTIVE): shot/record of the virtual display or one window; parallel with F002.

## NEXT

- `F004-run-on-virtual-display-alice-proof` (PLANNED): `vscreen run` plus the Alice native proof and hook note; after F002 and F003.

## PROVEN

- None yet.

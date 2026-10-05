# Build

> Coordinator-maintained narrative board. Reconcile it with the planned and active feature folders before selecting, starting, resuming, reviewing, merging, proving, or dropping work. Update it in the same coherent change that changes feature state. Drift is an advisory, never a runtime gate.

## Owner choices

- Workers and reviewers: engine `omp`, provider `anthropic`, model `claude-opus-5-5`; workers thinking `high`, reviewers `xhigh`. Never Cursor cloud agents. No model fallback: on quota or model failure, preserve work and ask.
- Spawn `--detached` always: Herdr tab switching and GUI activity must not disturb Adam, who is using the Mac.
- Hard rule for every job: never take Adam's focus or bring any window to the front; GUI checks use the repo fixture app or the Alice lab on the virtual display only.
- Alice repo is read only: no commits there; needed hooks go to Adam as a note.
- Review: an independent reviewer for the AX/input and permission-identity slices (focus and TCC mistakes are hard to see).
- Proof that earns PROVEN for the whole tool: a full Alice native scenario passes on the virtual display while another app stays in front. Commit to main when it passes.

## TRACK

- vscreen: hidden virtual display plus focus-free window control for agents on macOS 26.5; private API risk reported plainly.

## NOW

- `F001-vscreen-core-display` (ACTIVE): package, own permission identity, install, and the daemon-held virtual display; first slice is the skeleton plus signing so Adam can approve permissions once.

## NEXT

- `F002-window-ax-control` (PLANNED): window list/move, AX tree, click/type; after F001's identity lands.
- `F003-capture` (PLANNED): shot/record of the virtual display or a window; parallel with F002.
- `F004-run-on-virtual-display-alice-proof` (PLANNED): `vscreen run` plus the Alice native proof and hook note; after F002 and F003.

## PROVEN

- None yet.

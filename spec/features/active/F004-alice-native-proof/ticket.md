# F004 · A full Alice native scenario passes on the virtual display while Adam's app stays in front

## Outcome

Alice's native chat-panels scenario (`scripts/debug/native-chat-panels.sh` in the Alice plant, the one that used to take focus) runs with its lab window on the vscreen virtual display. Adam's frontmost app never becomes Alice; his main display never shows the lab window. Owner priority of 2026-10-05 12:37 (via Tony).

## Scope

- `scripts/proof-alice-chat-panels.sh`: starts or reuses the display, samples the frontmost app every 0.2 s before, during and after, watches the lab window's display and frame, takes paired shots of the virtual display and the main display at the same moment mid-scenario, and writes `proof/<stamp>/summary.json` with a verdict.
- Alice side: a throwaway worktree (`/Users/overment/playground/alice-app/.vscreen-proof-alice`, detached at alice-v6 `4f01e4b5e`) with a two-line hook that places the hidden lab window at `ALICE_LAB_WINDOW_ORIGIN` before reveal. Nothing is committed to Alice; the hook is a note for Adam (`alice-hook.md`).

## Out of scope

- A general `vscreen run -- CMD` that moves any test's windows: F005.

## Acceptance

- Scenario exit 0; the lab pid is never frontmost; the lab window is never on screen outside the virtual display.
- Shot (a) shows the Alice window working on the virtual display; shot (b), taken at the same moment, shows Adam's main display with no Alice window.
- No dialog or other window from vscreen itself takes the front during the run.

# F004 · Any GUI test runs on the virtual display; a full Alice native scenario proves it

## Outcome

`vscreen run -- <command>` runs a test command, moves every window its process tree opens onto the virtual display as soon as it appears, and reports in JSON whether any window showed on the main display and whether the frontmost app ever changed. A full Alice native lab scenario passes this way while another app stays in front.

## Scope

- `vscreen run [--display virtual] [--settle MS] -- CMD...`: requires a running virtual display; exports `VSCREEN_DISPLAY_ID` and `VSCREEN_DISPLAY_FRAME` (x,y,w,h in global points) to the child so apps that honour them can open there directly; watches descendants of the child (pid tree) for new windows (AX `kAXWindowCreatedNotification` per process plus a fast CGWindowList poll) and moves them with the F002 move path; samples `NSWorkspace.frontmostApplication` throughout; passes the child's exit code through. JSON: exit code, windows moved (pid, CGWindowID, first-seen display and frame, ms on main display), frontmost before/after and every change.
- Proof script `scripts/proof-alice.sh` (Alice plant `/Users/overment/playground/alice-app/alice`, read only): checks the lab GUI lock is free, runs one self-contained lab scenario under `vscreen run`, takes `vscreen shot --display virtual` mid-run, and writes evidence (vscreen JSON, Alice `result.json` path and status, shot) under `spec/features/active/F004-.../proof/`.
- Scenario order: `ALICE_LAB_SPEC=$PWD/scripts/app-lab/history-craft.e2e.mjs pnpm app:lab` (asserts WebKit visibility, so it proves the window really renders on the virtual display); also `initial-alice.e2e.mjs`. Not the default chat spec (overwrites the clipboard) and not specs that use osascript `frontmost` or System Events keys.
- Facts from the Alice survey: lab binary `target/debug/Alice` (unbundled), spawned by wdio; window 880x600, created hidden, revealed with `orderFrontRegardless` (no key, no activate); tao calls `activateIgnoringOtherApps(YES)` at launch; title is empty, match by pid, layer 0, width > 100. Lab focus findings may appear at `/Users/overment/playground/alice-app/alice/tmp/lab-focus-findings.md`; read them first if present.
- Alice hook note for Adam (no Alice edits): the smallest change that opens the lab window on the virtual display without a flash on main (survey points at `src-tauri/src/automation.rs:93-95`, `setFrameOrigin` before `orderFrontRegardless`, reading `VSCREEN_DISPLAY_FRAME` passed through `scripts/app-lab/wdio.conf.mjs`). Write it to `spec/features/active/F004-.../alice-hook.md`.

## Out of scope

- Editing, committing, or cleaning anything tracked in the Alice repo. Running the chat spec.

## Acceptance

- Proof run: Alice lab exits 0 with `result.json` `status:"passed"`; vscreen JSON shows the lab window on the virtual display, frontmost app unchanged before, during, and after; the mid-run shot shows the Alice window.
- Any time the window spent on the main display is reported in ms, not hidden.

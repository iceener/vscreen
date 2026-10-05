# F005 · Any GUI test runs on the virtual display without app changes

## Outcome

`vscreen run -- <command>` runs a test command, moves every window its process tree opens onto the virtual display as soon as it appears, and reports in JSON whether any window showed on the main display and whether the frontmost app ever changed. Apps that honour `VSCREEN_DISPLAY_FRAME` open there directly.

## Scope

- `vscreen run [--settle MS] -- CMD...`: requires a running display; exports `VSCREEN_DISPLAY_ID` and `VSCREEN_DISPLAY_FRAME` (x,y,w,h global points); watches descendants of the child for new windows (AX `kAXWindowCreatedNotification` plus a fast CGWindowList poll) and moves them with the F002 move path; samples the frontmost app; passes the child's exit code through.
- JSON: exit code, windows moved (pid, CGWindowID, first-seen display and frame, ms on the main display), frontmost before/after and every change.
- Check whether an ordered-out window can be positioned before it is revealed (fixture); if so, do it, so the main display never shows it.

## Out of scope

- App-side hooks; the Alice proof (F004).

## Acceptance

- With the fixture launched under `vscreen run`, its windows end on the virtual display, the JSON reports the time each spent on the main display, and the frontmost app is unchanged.

# F006 group brief

Shared outcome: the ticket (`../ticket.md`). Two teams take different routes to "no orphan virtual display"; the lead (the plant coordinator) compares candidates, buys one independent review, and lands one.

## Constraints for every member

- Read `spec/build.md` Owner choices first. Hard rules: never take Adam's focus or bring a window to the front; never capture the main screen (no `--allow-main`, no `VSCREEN_ALLOW_MAIN`); no keychain or TCC dialogs.
- The virtual display is shared machine state. Both teams run live display checks, so coordinate through `limen group publish` before any `display start`/`stop`/`kill`: announce "taking the display", release it with "display free". Never stop a display another team announced. Leave no display, daemon or fixture running when you finish.
- Test only with your own bundle: `VSCREEN_APP=/tmp/vscreen-F006-team-N/vscreen.app VSCREEN_LINK=/tmp/vscreen-F006-team-N/bin/vscreen scripts/install.sh`. Never touch `~/Applications/vscreen.app`.
- Small code: no new frameworks, no duplicate stop/start paths, delete what your change makes redundant. Report the net line count.
- Deliverable per team: a committed candidate branch, `spec/features/active/F006-display-cleanup/group/teams/team-N-evidence.md` with the exact commands and observed output for every acceptance line, and a final group publish naming the candidate SHA.

## Starting hypotheses

- team-1: the tight fix inside the existing daemon and commands.
- team-2: observe first, then delete: if WindowServer already releases the display on process death, orphans can only be live daemons, and the fix is mostly removal plus one process scan.

## Lead synthesis

The lead files selected findings under `group/findings/`, writes `group/synthesis.md`, picks a candidate (smaller and fully proven wins), runs an Opus review, lands it, and reruns the acceptance proof itself.

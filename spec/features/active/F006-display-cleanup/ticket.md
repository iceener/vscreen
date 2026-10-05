# F006 · No virtual display ever outlives its owner

## Outcome

A vscreen virtual display exists only while a known vscreen daemon holds it. `display stop` always removes it. A crash, `kill -9`, SIGHUP, or logout never leaves an orphan display behind; if one is ever found, `display start` refuses to add another and `vscreen doctor` reports it and names the one command that clears it. The code stays small.

## Scope

- Start in `Sources/vscreen/Display.swift` (daemon lifecycle, state, locks from F001 repair 1) and `doctor` in `Sources/vscreen/Permissions.swift`.
- First establish the fact: does WindowServer remove a `CGVirtualDisplay` when its owning process dies (`kill -9`)? Every design choice follows from that observation.
- Orphan = an online display carrying vscreen's descriptor identity (vendor `0x7673`) that is not the display of the daemon recorded in state, or a live `vscreen __display-daemon` process not recorded in state.
- `display start` refuses (stable error code) while an orphan exists; `doctor` lists orphans with a `fix` command; one stop path clears them (no second, parallel stop implementation).
- Keep: the capture lock (window or virtual display only; unlock needs `--allow-main` plus `VSCREEN_ALLOW_MAIN=1`) unchanged and still passing.

## Out of scope

- New frameworks, launchd agents, helper binaries, or a second state file. Window/AX and capture features.

## Acceptance

- `display start` / `display stop` twice in a row: each stop leaves no vscreen display online (`CGGetOnlineDisplayList`).
- `kill -9` on the daemon: either no vscreen display remains, or `doctor` reports it and the named fix clears it; then `display start` works again.
- SIGHUP to the daemon removes its display and state.
- `vscreen shot --display main` (and a main-display window) fails with `outside_virtual_display` without the double unlock.
- Frontmost app unchanged across every check; net source line count of the change stays small and is reported.

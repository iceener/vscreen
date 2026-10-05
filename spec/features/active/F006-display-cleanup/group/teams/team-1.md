# team-1 · Tight fix in the existing daemon

Approach: keep the daemon, locks and state as they are; close the remaining gaps directly.

- Make every daemon exit path (SIGTERM, SIGINT, SIGHUP, display terminated by the system, session end) release the display and remove its own state.
- Add orphan detection in one function used by `display start`, `display status`, and `doctor`: online displays with vendor `0x7673` other than the recorded display, plus live `vscreen __display-daemon` processes not recorded in state (process table via `proc_listpids`/`proc_name`/argv; no shelling out).
- `display start` refuses with a stable code while orphans exist; `display stop` clears the recorded daemon and any orphan daemons through the same stop function; `doctor` reports `orphans` and the exact `fix` command.
- Prove with `kill -9`, SIGHUP, and start/stop twice.

Workers: one implementation worker; the second slot is a continuation or a fix after your own check, not a review (the lead buys the review).

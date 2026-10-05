# team-2 · Observe first, then delete

Approach: measure what macOS already guarantees, then write the least code that covers the rest.

- First, before any code: create a display with the current daemon, `kill -9` it, and record whether the display leaves `CGGetOnlineDisplayList` and how fast. Same for SIGHUP, and for a daemon whose parent shell dies. Publish the result to the group at once; team-1 depends on it too.
- If WindowServer releases the display with the process, an orphan display can only exist while some vscreen daemon process lives. Then the fix is: one process scan for `vscreen __display-daemon` processes (and vendor `0x7673` displays as a cross-check), `start` refusing while an unrecorded one lives, `doctor` naming it with a `fix`, and `stop` killing it through the existing stop function. Remove code that the observation makes unnecessary.
- If it does not release it, publish that immediately and fall back to the smallest holder-side cleanup.

Workers: one implementation worker; the second slot is a continuation or fix after your own check, not a review (the lead buys the review).

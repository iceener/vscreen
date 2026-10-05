PASS 97fce4c59afd22d3239ac984d951562b90c5d822

Verdict: **accept with fixes.** No acceptance bullet is proven broken, and `swift build` is clean. I did not re-run the live acceptance checks (install, start/status/stop, doctor) because the job rules forbid it. For those, the worker's `notes.md` is the only evidence. Findings 1–3 can leave a second virtual display, or a changed main display, on Adam's Mac. Fix them before the window-control work (F002) relies on the shared daemon.

The candidate is HEAD `97fce4c…` and the worktree is clean. The task named no sha, so I could not check for a mismatch.

## Findings

1. **Two concurrent `display start` calls can orphan a daemon that holds a display.** Medium, plausible. `Sources/vscreen/Display.swift:138-153`, `:160`.
   - Nothing locks the status check, the state removal (`:150`) and the spawn as one step.
   - Scenario: two agent jobs run `vscreen display start` before the first daemon writes state, which happens only after its display is online. Both see no state and both spawn a daemon.
   - Both daemons build the same vendor/product/serial (`:223`). Two identical identities online at the same time is the same per-identity memory area that caused the mirroring incident [INFERENCE].
   - The second placement at (3008,1692) gets moved to another edge. The `CGConfigureDisplayOrigin` contract in the SDK header says displays are placed "without overlapping".
   - The second `writeState` overwrites the first. `display stop` then kills only one daemon. The other keeps its display until logout, and `status` and `stop` cannot see it. The same race exists between `start` and `stop`.
   - Fix: take an exclusive `flock` on a lock file in `Paths.support` around start and stop. Also have the daemon hold a lock for its whole life, and exit before `CGVirtualDisplay(descriptor:)` if the lock is already held.

2. **`--origin` can make the virtual display main, and nothing checks after placement.** Medium, plausible, not run. `Display.swift:31-37`, `:261-265`.
   - `--origin` accepts any integers.
   - The main display is the one at (0,0). The candidate's safety net relies on this rule at `:253`.
   - `display start --origin 0,0` asks CoreGraphics to put the virtual display at (0,0). The header says it then moves displays that were not set explicitly, so the XDR moves. The menu bar and Dock then go to the hidden display.
   - The mirror/main check runs only when the display first comes online (`:247`), not after the placement transaction.
   - Fix: reject an origin of (0,0). After `:263`, assert `CGMainDisplayID() == user && CGDisplayIsInMirrorSet(id) == 0`. If that fails, exit so the display is released.

3. **The daemon identity check may fail after `install.sh` replaces the bundle. `stop` then loses track of the daemon.** Medium, plausible. `Display.swift:101-107`, `:172-183`, `scripts/install.sh:44-47`.
   - `isDaemonProcess` needs `proc_pidpath` to return a path that ends in `/vscreen`.
   - `install.sh` renames the old bundle and then runs `rm -rf` on it while the daemon still runs from it. I did not verify what `proc_pidpath` returns for an unlinked executable.
   - If it returns 0:
     - `status` reports `daemonAlive:false, stale:true`.
     - `start` spawns a second daemon and leaves the first one running, which ends the same way as finding 1.
     - `stop` skips the kill and deletes the state file (`:178`). It then returns `display_still_online`, and the pid is no longer recorded anywhere.
   - Fix: identify the daemon by `proc_name` plus the process start time (`PROC_PIDTBSDINFO` `pbi_start_tvsec`), stored in the state file. Never delete state for a live pid that cannot be identified; report the pid instead.

4. **The safety net guesses which display is Adam's after the takeover has already happened.** Low, plausible. `Display.swift:50-54`, `:246`.
   - When the virtual display is already main, `user` is "the first other online display".
   - If the Mac has a second physical panel, that panel can get origin (0,0) and become main instead of the XDR.
   - Fix: record `CGMainDisplayID()` before `CGVirtualDisplay(descriptor:)` and restore that id.

5. **The daemon's worst-case startup is longer than the caller's deadline.** Low. The timing is proven by reading; the effect is inferred.
   - The daemon waits up to 5 + 5 + 2 s (`:240`, `:256`, `:263`). The caller waits 10 s (`:154`).
   - In the mirror-recovery path, the CLI can send SIGTERM in the middle of recovery and report `daemon_timeout`.
   - SIGTERM's default action kills the daemon and releases the display, so the screen recovers. Only the error is misleading.
   - Fix: make the caller's deadline longer than the daemon's worst case.

6. **No watchdog after startup.** Low, hardening note. `Display.swift:281-289`.
   - The mirror/main check runs only once.
   - A later reconfiguration (sleep/wake, a display reconnect) that mirrors or promotes the virtual display goes unnoticed.
   - Fix: register `CGDisplayRegisterReconfigurationCallback` in the daemon and re-check, or exit.

7. **The re-exec parent does not forward signals, and the environment guard leaks.** Low, plausible. `Sources/vscreen/Permissions.swift:74-90`, `:56-57`, `:75`.
   - Ctrl-C works because parent and child share a process group.
   - A harness that sends SIGTERM only to the parent pid leaves the child running. The caller sees exit 143 and no JSON object. This does not matter for the short commands in this feature. It will matter for long commands such as recording in the capture work (F003).
   - `VSCREEN_RESPONSIBLE=1` is inherited by everything vscreen spawns. Any later vscreen call from that environment skips the self-disclaim, and TCC then charges the request to the host app.
   - Fix: guard on `responsibility_get_pid_responsible_for_pid(getpid()) == getpid()`, and forward SIGTERM, SIGINT and SIGHUP to the child.

8. **The TCC grant is only as safe as a 0600 file.** Informational. `scripts/sign.sh:13`, `:66`, `:76`.
   - Any process running as Adam can do this: read `keychain-password`, unlock the signing keychain, and codesign its own bundle as `com.overment.vscreen` with the same leaf certificate. That bundle meets the designated requirement and gets the Accessibility and Screen Recording grants.
   - Signing does not use the hardened runtime, and the re-exec passes on the full environment. So `DYLD_INSERT_LIBRARIES` injection into vscreen also works.
   - The extra risk is small compared with what the vscreen CLI itself can do. Adding `--options runtime` at `:76` costs little.

9. **sign.sh failure paths.** Low. The bash 3.2.57 behavior is proven by probes; the triggers are unlikely.
   - **a. Key left on disk.** The RETURN trap (`:27`) does not run on errexit. If identity creation fails anywhere in `:44-59`, `$tmp` keeps the unencrypted `key.pem` and `id.p12` in `$TMPDIR` (0700, readable only by Adam). Use an EXIT trap.
   - **b. Empty search list.** If the user search list is empty, `"${saved[@]}"` under `set -u` makes bash 3.2 abort at `:53`. By then `create-keychain` has already added the signing keychain to the list, so the list stays changed. The same expansion at `:72`/`:74` is safe, because it fails before the list changes.
   - **c. Two runs at once.** Two `sign.sh` runs can interleave the save and restore of the search list (`:70-74`). The signing keychain can then stay in the user search list for good. There is no prompt, and the login keychain is not touched.
   - **d. Partial creation.** If the keychain exists but `cert.pem` is missing, every later run fails at `:65` (`:63` skips creation). Recovery creates a new certificate, so Adam must grant permissions again.
   - **e. Passwords on the command line.** The `-p`, `-P`, `-k` and `pass:` arguments at `:47`, `:52`, `:56`, `:57`, `:58` and `:66` are visible in `ps` while those commands run.
   - **Confirmed by reading:** every `security` call names `$KC` explicitly. Only `list-keychains -d user` touches the search list. The login keychain is never read or written. The key ACL plus the partition list mean codesign does not prompt.

10. **smoke.sh stops a display it did not start.** Low to medium when jobs run in parallel. Proven by reading. `scripts/smoke.sh:20`, `:47`.
    - If another job's display is running, `start` returns `alreadyRunning:true`, and the smoke script still stops that display under the other job.
    - Fix: run `stop` only when `start` reported `alreadyRunning:false`.

11. **The fixture window position is not kept inside its display.** Low, plausible. `Sources/vscreen-fixture/main.swift:84-86`.
    - The main-display refusal checks only the display id.
    - `--x -3000 --y -1700` puts the window on Adam's XDR. The window is ordered back and is not key, but it shows on any uncovered desktop area, and later AX clicks could hit it.
    - Fix: keep the frame inside `CGDisplayBounds(options.display)`, or fail.

12. **The daemon's error code does not reach the caller.** Low. `Display.swift:157-158`.
    - A daemon failure such as `virtual_display_failed` or `display_mirrored` reaches the caller only as `daemon_failed` with "see log".
    - A daemon killed by a signal is reported with exit code 0.
    - Fix: pass the daemon's error code back, for example as a failure record in the state directory.

**No problems found in:**
- JSON helpers, the error-code shape, and the match between `help` and `docs/usage.md`.
- The detached daemon: `POSIX_SPAWN_CLOEXEC_DEFAULT`, stdin from `/dev/null` (so it holds no pipe from the caller), `setsid`, and the self-disclaim on its spawn.
- `realpath` to the bundle executable for TCC attribution.
- Serial packing: no bits overlap within the allowed option ranges.
- State removal guarded by the pid.
- Fixture: accessory policy, `orderBack`, and no activate call.

## Checks run

- `git rev-parse HEAD` returned `97fce4c59afd22d3239ac984d951562b90c5d822`. `git status --short` showed a clean tree.
- `swift build` (debug) printed "Build complete!" with no warnings or errors.
- Probes in `/bin/bash` 3.2.57:
  - A RETURN trap set inside a function does not fire for later function returns, so `sign.sh:27` causes no later `set -u` error.
  - Expanding an empty array under `set -u` fails with "unbound variable" (exit 127).
  - A RETURN trap does not run on errexit inside a function; the temp directory was left behind.
- Read the `CGConfigureDisplayOrigin` contract in the SDK header `CGDisplayConfiguration.h`.

**Not run, per the job rules:** `install.sh`, `sign.sh`, `smoke.sh`, `vscreen display start|stop|status`, `vscreen doctor`, the fixture, and `codesign -d -r-` on the installed app. These acceptance bullets are unverified by this review:
- `install.sh` installs a signed binary whose designated requirement is the same across two builds.
- `display start`, `status` and `stop` work, and the frontmost app does not change.
- `vscreen doctor` prints valid JSON.

The mirroring safety net has never been exercised, as `notes.md` also says.

**Next:** the worker fixes findings 1–3 (a lock around start/stop; origin validation and a main/mirror check after placement; a reliable daemon identity check that keeps state for a live pid it cannot identify). Then findings 10 and 11. Then run `scripts/smoke.sh` live once the shared display is free.

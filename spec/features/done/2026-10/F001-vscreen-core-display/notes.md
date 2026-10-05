# F001 notes

## Permission approval Adam must do (one line)

Run `vscreen permissions request` once in any terminal, then in System Settings > Privacy & Security turn on **vscreen** under **Accessibility** and under **Screen & System Audio Recording**.

`vscreen doctor` then shows `"permissions":{"accessibility":true,"screenRecording":true}`. `permissions request` was not run by the worker, because it shows system dialogs.

## Probe (macOS 26.5.2, build 25F84, Apple M4 Max, Pro Display XDR main)

`CGVirtualDisplay` works on this macOS. A 30-line probe created a display with
`CGVirtualDisplayDescriptor` + `CGVirtualDisplaySettings(hiDPI=1, modes=[1920x1200@60])`:

```
applied=true displayID=8 online=true bounds=(-1920.0, 0.0, 1920.0, 1200.0) main=(0.0, 0.0, 3008.0, 1692.0)
mode points=1920x1200 pixels=3840x2400
frontmost before=md.obsidian after=md.obsidian
```

- Swift imports `-applySettings:` as `apply(_:)`.
- Modes are in points. `hiDPI=1` gives a 2x backing store (3840x2400 pixels for 1920x1200 points). `maxPixelsWide/High` must cover the 2x size.
- macOS places a new display left of the main display, top-aligned, at (-1920, 0). That is next to the top-left hot corner, so vscreen moves it.
- Display IDs are not reused within a login session.

## Placement accepted by macOS

Main display (XDR) bounds: (0, 0, 3008, 1692) points.
Default `vscreen display start` gives frame **(3008, 1692, 1920, 1200)**. The virtual display touches the main display only at the main display's bottom-right corner point. `CGConfigureDisplayOrigin` returns 0 and `CGDisplayBounds` reads back the same origin (`placement.accepted: true`).

- A requested origin of (3008, 1691) snaps to (3008, 1692).
- (3008, 1592), a 100-point overlap on the right edge, is accepted as given.
- A 1280x800 non-HiDPI display is also accepted at (3008, 1692).
- Configuration uses `.forSession`. macOS also remembers the origin per display identity for later creations.

## Display identity and the mirroring incident

macOS remembers settings per virtual display identity (vendor, product, serial).

During development, one identity was created at 1280x800 non-HiDPI with `sizeInMillimeters` derived from pixels (149 mm wide). macOS 26.5 then mirrored Adam's XDR onto it and made it main. The XDR bounds became (0, 0, 1280, 800). This was observed in the daemon log at 09:06:12–09:06:16 and 09:06:57–09:07:00 (local 11:06–11:07), for about 2–4 s each time. After that, the identity was remembered as mirrored.

Earlier failures at 09:02–09:05 (UTC), reported as "did not come online within 5s", were probably the same mirroring [INFERENCE]. The frontmost app did not change.

Fixes in `Sources/vscreen/Display.swift`:

- **Physical size:** fixed at 600 mm wide, with height from the aspect ratio. A fresh 1280x800 non-HiDPI identity then came online extended, not mirrored. It was re-created twice without problems.
- **Fresh identities:** `productID = 2`. The productID 1 identities are remembered as mirrored and are abandoned.
- **Serial per configuration:** serial = `width<<13 | height<<1 | hiDPI`, so one identity never changes mode.
- **Safety net:** if the display arrives in a mirror set or as main, the daemon unmirrors both displays and sets Adam's display origin to (0,0) before placement. It reports `placement.mirroredOnArrival`. This path was **not exercised live**, because a test would deliberately mirror Adam's screen.

Every new identity adds an entry to `/Library/Preferences/com.apple.windowserver.displays.plist` (root-owned). The development probes added about 10 of them. They are harmless and were not removed.

## Permission identity

- **Bundle, not a bare binary:** TCC keys plain CLI binaries by path but bundles by bundle id. `scripts/install.sh` installs a minimal `~/Applications/vscreen.app`: Info.plist with `CFBundleIdentifier=com.overment.vscreen` and `LSUIElement=true`. `~/.local/bin/vscreen` is a symlink to `vscreen.app/Contents/MacOS/vscreen`. A bundle replacement is a rename, so a running daemon keeps its old executable.
- **Self-disclaim:** every command except `help` re-executes itself with `posix_spawn` + `responsibility_spawnattrs_setdisclaim(attr, 1)` (env guard `VSCREEN_RESPONSIBLE=1`). The display daemon is spawned the same way, with `POSIX_SPAWN_SETSID`.
  - Verified with `responsibility_get_pid_responsible_for_pid`: `vscreen doctor` reports `responsiblePid == pid` (`selfResponsible: true`).
  - With `VSCREEN_RESPONSIBLE=1` set by hand (no re-exec), the responsible process was the terminal host `herdr`.
- **Signing:** `scripts/sign.sh` creates a self-signed code-signing certificate (CN "vscreen local code signing", 10 years) in a dedicated keychain at `~/Library/Application Support/vscreen/signing/vscreen-signing.keychain-db`. The random keychain password is in `keychain-password` (0600) next to it. The key ACL allows `/usr/bin/codesign`, and the partition list is set, so signing shows no dialog. The certificate is not trusted (no `add-trusted-cert`, which would prompt); codesign accepts it anyway.
  - codesign finds the identity only through the user keychain search list. `sign.sh` appends the signing keychain for the one codesign call and restores the exact previous list on exit (also after `create-keychain`, which adds itself). The login keychain is never read or changed.

Designated requirement (installed `~/Applications/vscreen.app`):

```
identifier "com.overment.vscreen" and certificate leaf = H"b2abfb1277db767445d1ec63f8d9a518278adb64"
```

It was identical across two release builds while the CDHash changed (`fdcace99…` -> `325d554c…`). Deleting the signing directory creates a new certificate, and then Adam must grant the permissions again.

## Fixture

`Sources/vscreen-fixture` (`swift build --product vscreen-fixture`) is an accessory-policy AppKit app. It opens one window with `fixture.text`, `fixture.button`, and `fixture.label` accessibility identifiers. It uses `orderBack`, never becomes key, refuses the main display, prints JSON-line events (ready/click/text), and exits after 600 s by default.

`scripts/smoke.sh` output, from the installed binary:

```
fixture: {"appActive":false,"displayID":53,"event":"ready","frame":{"height":182,"width":420,"x":3048,"y":1732},"isKey":false,...,"screenDisplayID":53}
frontmost before=net.imput.helium during=net.imput.helium after=net.imput.helium
smoke ok
```

`CGWindowListCopyWindowInfo` independently showed the fixture window at (3048, 1732, 420x182), on screen, inside the virtual display.

## Seams for F002/F003

- Output contract: `Sources/vscreen/Output.swift` (`CLIError`, `emitSuccess`, `emitFailure`).
- Router and option parsing: `Sources/vscreen/main.swift`.
- Display state: `readState()` / `displayStatus()` in `Display.swift`. The state file is `~/Library/Application Support/vscreen/display.json`.
- Non-prompting permission checks: `permissionState()` in `Permissions.swift`.
- `frontmostAppJSON()` is in doctor output for focus checks.

## Repair 1

Fixes for `review-1.md` (the review that accepted F001 with fixes). Code commit `35d9860`, record SIGHUP and notes in the next commit.

| # | Finding | Fix |
| --- | --- | --- |
| 1 | Concurrent start orphans a daemon | `display start` and `display stop` hold an exclusive flock on `display-control.lock` for their whole run (40 s wait, then `display_busy`). The daemon takes `display-daemon.lock` (2 s retry) before `CGVirtualDisplay(descriptor:)`, holds it for life, and exits with `daemon_already_running` if it is held. |
| 2 | `--origin` can make the display main | `--origin 0,0` is refused (`bad_arguments`). After placement the daemon checks main and mirror state and exits with `display_became_main`, which releases the display. |
| 3 | Identity lost after reinstall | State stores `pidStart` (`pbi_start_tvsec/usec` from `PROC_PIDTBSDINFO`). The daemon is `ours` when name is `vscreen` and the start time matches; `gone` when the pid is dead or another process has it; `unidentified` when the process is alive but its info cannot be read. For `unidentified`, `status` reports `daemonUnidentified:true` and `start`/`stop` fail with `daemon_unidentified` and keep the state file. State without `pidStart` (older daemons) falls back to the name check. |
| 4 | Safety net guesses Adam's display | The daemon records `CGMainDisplayID()` before it creates the display and restores that id (stored as `userDisplayID`). `userDisplay(excluding:)` is gone. |
| 5 | Caller deadline shorter than daemon worst case | Caller waits 30 s; daemon worst case is 2 + 5 + 5 + 2 = 14 s. |
| 6 | No watchdog | `CGDisplayRegisterReconfigurationCallback` in the daemon; a burst of callbacks is coalesced into one check 0.5 s later. If the display is mirrored or main, the daemon runs the same unmirror + restore as at startup; if that fails in 5 s, it records `display_mirrored`, removes state, and exits (the display goes away). |
| 7 | Re-exec env guard leaks; no SIGHUP | Guard is `responsibility_get_pid_responsible_for_pid(getpid()) == getpid()`. `VSCREEN_RESPONSIBLE` is removed; the child gets the parent's environment unchanged. A hidden argv marker (`__responsible`) stops a re-exec loop if the disclaim ever fails (`spawn_failed`); argv does not leak to grandchildren. The wrapper forwards SIGINT, SIGTERM, SIGHUP. `record` now also stops cleanly on SIGHUP. |
| 8 | Hardened runtime | Done before this repair (`f74e68f`). |
| 9a | Key left on disk | `create_identity` uses an EXIT trap with the path expanded at set time, removes `$tmp` itself on success, then clears the trap. |
| 9b | Empty search list | All three `list-keychains -s` calls use `${a[@]+"${a[@]}"}`. |
| 9c | Two sign.sh runs interleave | Not fixed (not in this repair's scope). |
| 9d | Partial creation | If the keychain exists but `cert.pem` is missing, `sign.sh` reads it back with `security find-certificate -c "$CN" -p`; if that fails it stops with a message to move the signing dir away. |
| 9e | Passwords in argv | Not fixed (not in this repair's scope). |
| 10 | smoke.sh stops another job's display | `smoke.sh` stops the display only when its `start` returned `alreadyRunning:false`. |
| 11 | Fixture window can land off its display | The fixture fails with `window_outside_display` before ordering any window when the main window (plus the web window under it, with `--web 1`) is not inside `CGDisplayBounds(--display)`. |
| 12 | Daemon error code lost | The daemon writes `display-failure.json` (`pid`, `code`, `message`, `at`) on every failure exit. `start` returns that code; without a record it reports exit code or "killed by signal N". `status` of a stale daemon shows `failure`. |

### Live checks (installed `/tmp/vscreen-F001r/bin/vscreen`, macOS 26.5)

Frontmost app (lsappinfo) was Slack before and after every check except the record check (see below).

- `doctor`: `selfResponsible:true`, certificate-based requirement, both permissions true. `VSCREEN_RESPONSIBLE=1 vscreen doctor` still re-execs (`selfResponsible:true`). `vscreen __responsible doctor` run from a terminal fails with `spawn_failed` instead of looping.
- Concurrent start: four `display start` in parallel from a stopped state. Result: one daemon (pid 81159), one virtual display (id 57, frame 3008,1692 1920x1200); one call returned `alreadyRunning:false`, three `true`, all with the same pid and display id.
- Reinstall under a running daemon: `install.sh` replaced the bundle; `lsof` showed the daemon running from the deleted `.vscreen.app.old.*` executable. `status` still `running:true`, `start` returned `alreadyRunning:true`, no second daemon.
- Daemon lock: a Python `flock(LOCK_EX|LOCK_NB)` probe saw the lock held. With `display.json` moved aside, `display start` spawned a daemon that exited with `daemon_already_running`, and the caller returned that code; display count stayed 2, one daemon.
- Start/stop race: three rounds of `stop` and `start` in parallel. Every round ended consistent (no daemon and 1 display with `running:false`, or one daemon and 2 displays with `running:true`).
- `smoke.sh` with the display already running: `stop: skipped`, display still running after. `smoke.sh` from a stopped state: started display 60, fixture ready on it with `appActive:false`, stopped it; `smoke ok` both times, frontmost Slack before/during/after.
- Fixture: `--x -3000 --y -1700`, `--x 1600 --y 40`, `--x 40 --y 1100`, and `--y 900 --web 1` all failed with `window_outside_display`; no fixture process left.
- `--origin 0,0` and `--origin ' 0, 0'`: `bad_arguments`, no daemon spawned.
- Identity: state with a live `sleep` pid and no `pidStart` → `stale:true`, `stop` cleared it and did not kill `sleep`. State with pid 1 (launchd, info not readable) → `daemonUnidentified:true`; `stop` failed with `daemon_unidentified` and kept the state file (removed by hand afterwards).
- SIGHUP: `record --duration 20` on the virtual display, `kill -HUP` to the wrapper pid only. Wrapper exit 0, JSON `stoppedBy:"SIGHUP"`, child gone, movie written.

**Focus incident in the record check.** At stream start, replayd showed ScreenCaptureKit's periodic re-approval alert for vscreen (`SCAlertStatsManager requireAlert` → `SCAlert userAcknowledgementAlert`, via UserNotificationCenter). Frontmost became UserNotificationCenter. A click 3 s later dismissed it (`user acknowledgement refused` in the replayd log); Slack was frontmost again and `doctor` still reports `screenRecording:true`. This is macOS behaviour of any `shot`/`record` once the re-approval interval passes, not code from this repair. It can break the focus rule for capture work and needs an owner decision.

**Not exercised live:** the mirror/main recovery at startup, the post-placement `display_became_main` exit, and the watchdog. Triggering them needs a mirrored or main virtual display, which the job rules forbid.

End state: display stopped, no daemon, no fixture process.

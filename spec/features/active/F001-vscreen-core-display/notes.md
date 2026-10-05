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

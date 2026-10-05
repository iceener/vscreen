# vscreen usage

`vscreen` is a macOS CLI for agents. It holds a hidden virtual display and (in later
versions) drives app windows on it without taking focus from the person at the Mac.

Every command prints one JSON object on stdout: `{"ok":true,...}` on success, or
`{"ok":false,"error":{"code":"...","message":"..."}}` with exit code 1.

## Install

```sh
scripts/install.sh
```

Builds a release binary, wraps it in `~/Applications/vscreen.app` (bundle id
`com.overment.vscreen`), signs it with a local self-signed identity, and links
`~/.local/bin/vscreen` to the bundle's executable. The signing identity lives in its own
keychain under `~/Library/Application Support/vscreen/signing/`; the login keychain is not used.

## Permissions

Accessibility and Screen Recording are granted to vscreen itself, not to the terminal or
agent host that runs it: every command re-executes itself as its own TCC-responsible process.
A grant survives rebuilds because the designated requirement is tied to the stable signing
certificate.

Grant once, yourself:

```sh
vscreen permissions request
```

Then allow vscreen in System Settings > Privacy & Security > Accessibility, and in
Screen & System Audio Recording. Other commands never prompt.

## Commands

| Command | Does |
| --- | --- |
| `vscreen help` | Print this command list. |
| `vscreen doctor` | Report permissions, signature, and display state without prompting. |
| `vscreen permissions request` | Ask macOS for Accessibility and Screen Recording for vscreen. May show system dialogs; run it yourself. |
| `vscreen display start [--width N] [--height N] [--no-hidpi] [--origin X,Y]` | Create the virtual display in a background daemon. Default 1920x1200 points, HiDPI, touching the main display only at its bottom-right corner. |
| `vscreen display status` | Show whether the daemon runs and the display is online, with its frame. |
| `vscreen display stop` | Stop the daemon and remove the virtual display. |
| `vscreen shot [--display virtual\|ID \| --window ID] -o FILE.png [--scale 1\|2] [--allow-main]` | Save a PNG of the virtual display (default) or one window. A target outside the virtual display needs --allow-main. |
| `vscreen record [--display virtual\|ID \| --window ID] -o FILE.mov --duration SECONDS [--fps N] [--allow-main]` | Record a movie (H.264, no audio). Returns when the file is finalized; SIGINT/SIGTERM stop it early and cleanly. |

`display start` returns the running display when one exists (`"alreadyRunning":true`).
`--origin X,Y` is a global position in points (top-left origin, main display at 0,0).

### Capture

`shot` and `record` use ScreenCaptureKit and need Screen Recording; without it they fail with
`permission_missing` and never prompt. The default target is the virtual display. When it is
not running they fail with `display_not_running`; they never fall back to the main display.

- `--display ID` other than the virtual display, and `--window ID` whose frame is not fully
  inside the virtual display, fail with `outside_virtual_display` unless `--allow-main` is passed.
  Window IDs are CGWindowIDs.
- `--scale` defaults to the target's backing scale: a HiDPI 1920x1200 display gives a
  3840x2400 PNG, `--scale 1` gives 1920x1200. A window gives its frame size times the scale.
  The cursor is not captured.
- `record` writes H.264 `.mov` at the backing scale, `--fps` 1–60 (default 30), `--duration` up
  to 3600 s. It replaces an existing file. The result reports `duration` (of the written movie),
  `elapsed`, and `stoppedBy` (`duration`, `SIGINT`, or `SIGTERM`).
- While a window is recorded, macOS draws a "shared" badge in place of its title-bar buttons;
  the badge is in the movie.

```sh
vscreen shot -o display.png
# {"ok":true,"path":".../display.png","pixels":{"width":3840,"height":2400},"scale":2,
#  "target":{"kind":"display","displayID":55,"virtual":true,"frame":{...}}}
vscreen record --window 174621 -o window.mov --duration 3
```

## Files

- State: `~/Library/Application Support/vscreen/display.json` (daemon pid, display id, placement).
- Daemon log: `~/Library/Logs/vscreen/daemon.log`.

## Test fixture and smoke check

`swift build --product vscreen-fixture` builds a small AppKit app for tests. It opens one
window (text field `fixture.text`, button `fixture.button`, label `fixture.label`) on the
given display without activating itself, and prints events as JSON lines:

```sh
vscreen-fixture --display <displayID> [--x N] [--y N] [--title T] [--exit-after SECONDS]
```

It refuses the main display and exits after 600 s by default.
`scripts/smoke.sh` runs doctor, display start/status, the fixture on the virtual display, and
display stop, and fails if the frontmost app changed.

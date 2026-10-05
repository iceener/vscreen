# vscreen usage

`vscreen` is a macOS CLI for agents. It holds a hidden virtual display and drives app windows
on it without taking focus from the person at the Mac.

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
| `vscreen window list [--pid P] [--app NAME] [--bundle ID] [--display virtual\|main\|ID] [--all-layers]` | List windows front to back: id (CGWindowID), pid, app, bundle id, title, frame, display, layer, on-screen, order. Layer 0 only unless --all-layers. |
| `vscreen window move --window ID [--to virtual\|main\|DISPLAYID] [--x X --y Y] [--fit]` | Move a window by AXPosition to X,Y points from the target display's top-left (default virtual, 40,40). --fit shrinks it to stay inside the display. Never raises or activates. |
| `vscreen tree --pid P [--window ID] [--depth N] [--max-nodes N]` | Accessibility tree of the app's windows as JSON: path, role, title, value, description (aria-label), identifier, domIdentifier, frame, actions, children. |
| `vscreen click --pid P (--path PATH \| --match TERMS) [--window ID] [--action AXPress \| --post]` | Perform an AX action on the element (default AXPress). --post sends mouse down/up at its centre to that pid only; the cursor does not move. |
| `vscreen type --pid P (--path PATH \| --match TERMS) [--window ID] --text T [--mode value\|keys]` | value: set AXValue (replaces the text). keys: focus the element inside its app, then post Unicode key events to that pid only; fails with keys_not_routable when the app's focused element is another element. |
| `vscreen key --pid P --key NAME [--mods cmd,shift,alt,ctrl] [--path PATH \| --match TERMS]` | Post one key (return, tab, escape, delete, arrows, a-z, 0-9, ...) to that pid only, to its focused element; with an element, focus it first and fail with keys_not_routable if focus stays elsewhere. |
| `vscreen shot [--display virtual\|ID \| --window ID] -o FILE.png [--scale 1\|2] [--allow-main]` | Save a PNG of the virtual display (default) or one window. A target outside the virtual display needs --allow-main. |
| `vscreen record [--display virtual\|ID \| --window ID] -o FILE.mov --duration SECONDS [--fps N] [--allow-main]` | Record a movie (H.264, no audio). Returns when the file is finalized; SIGINT/SIGTERM stop it early and cleanly. |

`display start` returns the running display when one exists (`"alreadyRunning":true`).
`--origin X,Y` is a global position in points (top-left origin, main display at 0,0); `0,0` is
refused because it would make the virtual display the main display.
`display start` and `display stop` run one at a time (a lock in `~/Library/Application Support/vscreen/`);
one waiting longer than 40 s fails with `display_busy`. Only one daemon can hold a display: a second one
exits before it creates a display (`daemon_already_running`). A daemon failure reaches the caller with the
daemon's own code (`virtual_display_failed`, `display_mirrored`, `display_became_main`, ...); `status` of
a stale daemon shows it under `failure`. The daemon is identified by pid, process name and process
start time. When its pid is alive but cannot be identified, `status` reports `daemonUnidentified:true`
and `start`/`stop` fail with `daemon_unidentified` and keep the state file.
The daemon watches display reconfiguration (sleep/wake, reconnects): if the virtual display becomes
mirrored or main, it puts Adam's display back as main, or exits and removes the virtual display.

## Windows and elements

All window and element commands need Accessibility (except `window list`) and fail with
`permission_missing` without it. They never activate an app, raise a window, set
`AXMain`/`AXFrontmost`, move the cursor, or post to a global event tap.

- **Window ids** are CGWindowIDs from `window list`. `window move` finds the AX window by
  `_AXUIElementGetWindow`, else by an identical frame (`axWindowMatch`). A window on another
  Space may be missing from the app's AX windows; the move then fails with `ax_window_not_found`.
- **Paths** come from `tree`: `w<CGWindowID>` for a window, then child indices in AXChildren
  order, e.g. `w174779/0`. A window without an id is `n<index in AXWindows>`. A path is stable
  while the window's element structure does not change.
- **Match terms** are comma-separated `key=value` (exact) or `key~value` (case-insensitive
  contains); all terms must hold, and values cannot contain commas. Keys: `role`, `subrole`,
  `title`, `id` (AXIdentifier or HTML id via AXDOMIdentifier), `label` (AXDescription, which is
  the aria-label in web content, or AXTitle), `value`, `placeholder`, `class` (one HTML class).
  The search is depth-first; the first match is used and `matchCount` reports how many matched.
  When nothing matches, the search runs once more after 1 s.
- **Web content** (WKWebView, e.g. Tauri apps): `tree` reports `domIdentifier`,
  `domClassList`, `description` (aria-label), `title`, `placeholder`, `url`. WebKit builds the
  web tree only after the first AX request, so the first `tree` of a fresh web view can show an
  empty `AXGroup`; repeat it.
- **Focus evidence:** every acting command returns `focus` with the frontmost app before,
  during, and after, `frontmostUnchanged`, and `targetBecameFrontmost`.

### What reaches an app that is not frontmost

Observed on the fixture (macOS 26.5, AppKit window and WKWebView window), with another app
frontmost:

- `click` (AXPress) works for AppKit and web buttons.
- `type --mode value` works for AppKit and web text fields; it replaces the text. A web field
  takes the value only after `AXFocused` (DOM focus), which vscreen sets when the first write
  does not stick.
- `type --mode keys` and `key` post events to the pid. AppKit gives them to the focused element
  of the window it treats as the app's focused window, whatever window the target is in. vscreen
  sets `AXFocused` on the target, then compares it with the app's `AXFocusedUIElement`; when they
  differ it fails with `keys_not_routable` and posts nothing, so keys never land in another
  element. On the fixture, keys worked in the AppKit field when its window was the app's focused
  window, and were refused for the web field and for an AppKit field in a second window.
- `click --post` is not tested: a mouse down in a window of an inactive app may activate it.

## Capture

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
given display without activating itself, and prints events as JSON lines (ready, click, text,
value, input, and any key-window or activation change):

```sh
vscreen-fixture --display <displayID> [--x N] [--y N] [--title T] [--exit-after SECONDS] [--main-window 1] [--web 1]
```

It refuses the main display and exits after 600 s by default. `--main-window 1` adds a small
second window near the main display's bottom-right corner, ordered behind all other windows,
as a target for `window move`; it stays transparent unless another app's window covers it.
`--web 1` adds a WKWebView window under the first one with `web-text` (input), `web-button`, and
`web-label` elements that carry HTML ids, classes, and aria-labels; it prints `web.input` and
`web.click` events.
`scripts/smoke.sh` runs doctor, display start/status, the fixture on the virtual display, and
display stop, and fails if the frontmost app changed.

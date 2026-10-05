# F002 notes

## Result on the fixture (macOS 26.5, shared virtual display 55 at 3008,1692 1920x1200)

| Check | Result |
| --- | --- |
| `tree` finds field and button | AppKit: `w<id>/0` AXTextField `fixture.text`, `w<id>/1` AXButton `fixture.button`. Web: `web-text`, `web-button`, `web-label` with domIdentifier, domClassList, description (aria-label) |
| `type --mode value` | changes the AppKit field (`text` event) and the web input (`web.input` event) |
| `type --mode keys` | changes the AppKit field when its window is the app's focused window (`text` event "K"); otherwise refused with `keys_not_routable`, nothing posted |
| `key --key return` | same routing guard; refused in the two-window runs |
| `click` (AXPress) | AppKit label `clicks: 1 text: hello`; web `web.click` count 1 and 2 (match by `label=Web press` and by `class=primary,role=AXButton`) |
| `click --post` | **not run**: a mouse down in a window of an inactive app may activate it [INFERENCE] |
| `window move` main -> virtual | arrived at 4008,1992 (`axWindowMatch: windowID`); no key or activation event; last in z-order before and after (run 2) |
| frontmost app | identical before, during, after in every final run (Helium in run 2, Slack in run 3 and the web probe); fixture never active, `targetBecameFrontmost:false` everywhere |

Alice itself was running on the main display and was not touched. The web part is verified on the fixture's WKWebView window only.

## Key events into an app that is not frontmost

`CGEventPostToPid` key events always reach the app (fixture `input` events from an NSEvent local monitor). Where AppKit delivers them:

1. AppKit gives keyDown to the first responder of the window it treats as the app's focused window, even though no window is key (`windowIsKey:false`). The app's `AXFocusedUIElement` names that element.
2. Single-window fixture: `fixture.text` is that element from launch (`focused:true`); `type --mode keys --text K` changed it (`{"event":"text","text":"K"}`), frontmost unchanged.
3. `--main-window 1` fixture: the app's focused element is the second window (`AXWindow "F002 fixture (main)"`). `AXFocused=true` on `fixture.text` returns success but reads back false. Before the guard existed, keys were dropped.
4. `--web 1` fixture: `AXFocused` on the DOM input works (`focusedAfter:true`), but the app's focused element stays the AppKit `fixture.text`. Before the guard existed, keys meant for the web input **landed in the AppKit field** (`{"event":"text","text":" +k"}`).
5. The undocumented CGEvent field 51 (window number) changes `NSEvent.window` but not delivery; it was tried and removed. Fields 91/92 change nothing. A temporary logging field editor showed keyDown never reaches a first responder outside the focused window (removed after the probe).
6. Not tried, on purpose: making a window key (`AXMain`, `AXFocused` on a window, SkyLight make-key records). A key window takes keyboard focus from Adam.

So `type --mode keys` and `key --path/--match` set `AXFocused`, then require the app's `AXFocusedUIElement` to equal the target (`requireKeyRoute`); otherwise they fail with `keys_not_routable` and post nothing. For Alice (one WKWebView window) keys may route to the focused DOM element [INFERENCE, untested]. `--mode value` is the reliable path.

## Exact commands and observed JSON (excerpts)

Bundle: `VSCREEN_APP=/tmp/vscreen-F002/vscreen.app VSCREEN_LINK=/tmp/vscreen-F002/bin/vscreen scripts/install.sh`. Scripts and full logs (outside the repo): `/tmp/vscreen-F002/acceptance.sh`, `keys-probe.sh`, `web-probe.sh`; logs in `/tmp/vscreen-F002/run/` (`acceptance2.log`, `acceptance3.log`, `keys-probe.log`, `web-probe.log`). The display id came from `display.json`; the display was never started or stopped.

Run 2 (`acceptance2.log`, before the keys guard; frontmost `net.imput.helium` at every sample):

```
$ vscreen-fixture --display 55 --x 520 --y 300 --title "F002 fixture" --main-window 1 --exit-after 300
{"appActive":false,"event":"ready","isKey":false,"mainWindowNumber":174799,"mainWindowVisible":false,"pid":82692,"screenDisplayID":55,"windowNumber":174797,...}

$ vscreen tree --pid 82692 --window 174797
{"nodeCount":9,"windows":[{"actions":["AXRaise"],"children":[
  {"identifier":"fixture.text","path":"w174797/0","role":"AXTextField","placeholder":"type here","value":"","actions":["AXShowMenu","AXConfirm"],...},
  {"identifier":"fixture.button","path":"w174797/1","role":"AXButton","title":"Press","actions":["AXPress"],...},
  {"identifier":"fixture.label","path":"w174797/2","role":"AXStaticText","value":"clicks: 0",...}, ...

$ vscreen type --pid 82692 --match id=fixture.text --text hello --mode value
{"axError":0,"changed":true,"mode":"value","settable":true,"valueBefore":"","valueAfter":"hello",
 "focus":{"frontmostBefore":{"bundleId":"net.imput.helium",...},"frontmostDuring":{...},"frontmostAfter":{...},"frontmostUnchanged":true,"targetBecameFrontmost":false},...}

$ vscreen click --pid 82692 --match role=AXButton,title=Press
{"method":"action","action":"AXPress","element":{"path":"w174797/1","matchCount":1,...},"focus":{...,"frontmostUnchanged":true,"targetBecameFrontmost":false}}
fixture: {"count":1,"event":"click","text":"hello"}
$ vscreen tree --pid 82692 --window 174797 --depth 1   ->   fixture.label "value":"clicks: 1 text: hello"

$ vscreen window move --window 174799 --to virtual --x 1000 --y 300
{"arrived":true,"axWindowMatch":"windowID","requested":{"x":4008,"y":1992},
 "before":{"display":2,"order":24,...},"window":{"display":55,"frame":{"x":4008,"y":1992,"width":300,"height":112},"order":23,"onVirtualDisplay":true,...},
 "focus":{...,"frontmostUnchanged":true,"targetBecameFrontmost":false}}
virtual-display windows front to back: [(23, F002 fixture), (24, F002 fixture (main))]
```

`order` is global: 24 was the last on-screen window before the move, and after it the window is behind the other fixture window.

Run 3 (`acceptance3.log`, final binary, frontmost `com.tinyspeck.slackmacgap` at every sample): value, click, and move as above (label `clicks: 1 text: hello`, move `arrived:true`). Keys and key were refused:

```
{"ok":false,"error":{"code":"keys_not_routable","message":"key events for pid 15854 would reach the app's focused element, not w174990/0; focused element: {\"role\":\"AXWindow\",\"title\":\"F002 fixture (main)\",\"focused\":true,...}. Use --mode value or an AX action."}}
```

In run 3 the main display showed only a Slack window (probably a full-screen Space), and the transparent move-target window was listed in front of it (order 4 vs 6). It stayed invisible (`mainWindowVisible:false`).

Keys probe (`keys-probe.log`, single-window fixture, final binary):

```
fixture.text focused True value ''
$ vscreen type --pid <pid> --match id=fixture.text --text K --mode keys
keys changed True 'K' {'needed': False} True False      (changed, valueAfter, focusInsideApp, frontmostUnchanged, targetBecameFrontmost)
fixture: {"characters":"K","event":"input","firstResponder":"NSTextView","windowIsKey":false,...}
fixture: {"event":"text","text":"K"}
```

Web probe (`web-probe.log`, `--web 1`, final binary; the first match on a fresh web view succeeded through the 1 s retry):

```
$ vscreen type --pid 7798 --match id=web-text --text "hi web" --mode value
{"changed":true,"valueAfter":"hi web","element":{"path":"w174985/0/0/0/0/0","role":"AXTextField","domIdentifier":"web-text","domClassList":["field"],"description":"Web text","title":"Web text","placeholder":"web input",...},"focus":{...,"frontmostUnchanged":true,"targetBecameFrontmost":false}}
$ vscreen click --pid 7798 --match "label=Web press"          -> {"action":"AXPress","element":{"domIdentifier":"web-button",...}}
$ vscreen click --pid 7798 --match class=primary,role=AXButton -> {"action":"AXPress",...}
$ vscreen type --pid 7798 --match id=web-text --text " +k" --mode keys -> keys_not_routable (focused element: fixture.text)
fixture: {"event":"web.input","text":"hi web"} {"count":1,"event":"web.click"} {"count":2,"event":"web.click"}
```

The first web `value` write did not stick. vscreen then set `AXFocused` (DOM focus, `focusedAfter:true`) and wrote again.

`window move --window <main> --to virtual --x 1800 --y 1150 --fit` (earlier binary) gave `"resized":{"width":120,"height":50,"ok":true}`, frame 4808,2842 120x50, `arrived:true`.

## Incidents and limits

- **Visible fixture window:** in one diagnostic launch during a full-screen iTerm Space, the `--main-window` window sat at z-order 0 on the main display for about 3 s. Fix: it starts with alpha 0 and becomes opaque only when another app's window fully covers it (`mainWindowVisible`).
- **Other Space:** `window move` failed with `ax_window_not_found` for a window on the desktop Space while a full-screen Space was current; `AXWindows` did not list it. The error message now says so.
- **Frontmost change not caused by vscreen:** in run 1 the frontmost app changed Finder -> iTerm2 while Adam worked; the fixture was never active and `targetBecameFrontmost` stayed false.
- **Fresh web view:** the first `tree` returned the WKWebView as an empty `AXGroup`; 2 s later the full web tree was there. `--match` searches once more after 1 s.
- `NSWorkspace.frontmostApplication` is cached per process; `focusSnapshot` turns the run loop for 20 ms before reading. External samples (`vscreen doctor` in a new process, `lsappinfo front`) agreed every time.
- `display status` from this branch reports `running:false, stale:true` for the F003-owned daemon (pid 29027) because its bundle was reinstalled; fixed on another branch. F002 code needs only `display.json` `displayID` and `CGGetOnlineDisplayList`.

## Seams

- `Sources/vscreen/Windows.swift`: `windowInfos()`, `resolveDisplay`, `axWindow(for:)`, `placement` (pure), `windowMove`, `focusSnapshot`/`focusReport`.
- `Sources/vscreen/AX.swift`: `readFields` (one `AXUIElementCopyMultipleAttributeValues` per node), paths (`w<id>/i/j`), `parseMatch`/`matches`, `search` (DFS, 64 deep, 20000 nodes), `click`/`postClick`, `typeText`, `requireKeyRoute`, `postKey`, `key`.
- `Sources/CPrivate/include/CPrivate.h`: `_AXUIElementGetWindow`.
- Fixture: `--main-window 1`, `--web 1`, `value` events (AXValue poll), `input` events (local monitor), key and activation notifications.

## Open for the next slice

- `click --post` needs a safe live check before anyone relies on it.
- Keys into a single-window WKWebView app (Alice's shape) are untested.

## Repair 1

Fixes for `review-1.md` (independent review 1, PASS with findings). Code commit `87624ad`. Checks run by the worker: `swift build` (clean, no warnings); a throwaway Swift Testing package in `/tmp` with `@testable import vscreen` over the real sources (3 tests passed: action allow-list and `--post` gate, control-character scan, error details serialize); a script compared `commandList` with the docs table (14 rows, no differences). Nothing below was run live: vscreen and the fixture were off limits for this job. `F` is the fixture pid, `W` its window id from `window list`, `V` the virtual display size.

| # | Fix | Live check for the coordinator |
| --- | --- | --- |
| 1 | `click --post` fails with `activation_risk` unless `--allow-activation-risk` is passed; `--allow-activation-risk` without `--post` is `bad_arguments`. Help, the docs table, and the "Windows and elements" section now say `--post` may activate the app. | `click --pid F --match id=fixture.button --post` gives `activation_risk` and the label does not change. Then, with another app frontmost, `--post --allow-activation-risk`: record `focus.targetBecameFrontmost` and the fixture's key/activation events. That is the open `--post` live check. |
| 2 | `click --action` takes only `AXPress`, `AXConfirm`, `AXIncrement`, `AXDecrement`, `AXPick`, `AXCancel` (`allowedActions`); anything else fails with `action_not_allowed` before any AX call. | `click --pid F --path wW --action AXRaise` and `--match id=fixture.text --action AXShowMenu` both give `action_not_allowed`. Plain `click --match id=fixture.button` still increments the label. |
| 3 | `search` starts at the root window's children, so `--match` never resolves to the window. `requireNotWindow` refuses a window root or an `AXWindow`/`AXSheet` role with `element_is_window`; `type`, `key`, and `focusInsideApp` call it before any write. | `type --pid F --path wW --text hi` and `key --pid F --path wW --key a` give `element_is_window`; `type --pid F --match "label~F002 fixture" --text hi` gives `element_not_found` (the title belongs to the window only). The fixture prints no key-window event. |
| 4 | `axWindow(for:)` matches by frame only among AX windows whose `_AXUIElementGetWindow` id is unknown. | The trigger (two same-app windows with identical frames, target missing from `AXWindows`) is hard to stage. Re-run the main -> virtual move of the `--main-window 1` window: still `axWindowMatch:"windowID"`, arrives. |
| 5 | `type --mode keys` refuses any Unicode control character (`firstControlCharacter`) with `bad_arguments`, before Accessibility is touched, and points to `vscreen key`. Per-character route re-checks were not added. | `type --pid F --match id=fixture.text --mode keys --text $'a\tb'` gives `bad_arguments`; the fixture prints no `input` event. |
| 6 | `key` without an element checks the pid (`app_not_found`) and fails with `target_frontmost` when the app is frontmost. `--window` without `--match`/`--path` is `bad_arguments` (it was silently ignored). | `key --pid 999999 --key a` gives `app_not_found`. `key --pid F --key escape` with another app front still posts (`ok:true`). Do not test `target_frontmost` against Adam's frontmost app: if the guard were wrong, the key would reach his app. Leave it proven by reading unless the fixture can be frontmost in the lab. |
| 7 | `type --mode value` fails with `ax_failed` (write error and value differs from `--text`) or `value_not_set` (write reported success, value unchanged). `type --mode keys` with an unchanged value fails with `keys_no_effect`. `window move` fails with `ax_failed` when AXSize failed and `not_arrived` when the window is not on the target display. Each carries the full success report in `error.details`. | `type --pid F --match id=fixture.label --text x` gives `ok:false` (`ax_failed` or `value_not_set`) with `error.details.focus`. The existing value and keys runs on `fixture.text` still return `ok:true`. |
| 8 | `CLIError` has optional `details`; `emitFailure` prints `error.details`. `keys_not_routable` reports `element`, `focusInsideApp` (the AXFocused write already made), and `focusedElement`, and its message says nothing was posted. | `--web 1` fixture: `type --pid F --match id=web-text --mode keys --text k` gives `keys_not_routable` with `error.details.focusInsideApp.needed:true`. |
| 9 | `window move` reads `AXMinimized` and fails with `window_minimized` without unminimizing. `--x`/`--y` must be smaller than the target display's width/height (`bad_arguments`), so `--fit` never computes a negative size. | `window move --window W --x 5000` gives `bad_arguments`. `--x 1900 --y 1150 --fit` on a 1920x1200 display gives a positive `resized`. The minimized case needs a minimized fixture window; the fixture cannot make one now. |
| 10 | Help and `docs/usage.md` list `[--window ID]` for `key`. | `vscreen help` matches the docs table (14 rows). |
| 11 | Left as a note; another job edits the fixture. | None. |
| 12 | Left as a note: `targetBecameFrontmost` still takes three samples. | None. |

Seams: `allowedActions`, `requireNotWindow`, `windowRoles`, `firstControlCharacter`, and `search` in `Sources/vscreen/AX.swift`; `axWindow(for:)` and the checks in `windowMove` in `Sources/vscreen/Windows.swift`; `CLIError.details` in `Sources/vscreen/Output.swift`. On success, `arrived` in the `window move` output is always true now; it stays for compatibility.

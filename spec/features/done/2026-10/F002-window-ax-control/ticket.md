# F002 · Agents see and drive any app window on the virtual display without taking focus

## Outcome

An agent can list windows, move any app's window onto the virtual display, read its accessibility tree as JSON, and click or type into its elements, while Adam's frontmost app and keyboard focus never change.

## Scope

- `vscreen window list [--pid P|--app NAME|--bundle ID] [--display virtual|main|ID]`: CGWindowID, pid, app, bundle id, title, frame, display, layer, on-screen.
- `vscreen window move --window ID [--to virtual|main|DISPLAYID] [--x X --y Y] [--fit]`: resolve the AX window for a CGWindowID (`_AXUIElementGetWindow` or frame match), set `AXPosition` (and `AXSize` when fitting). Never `AXRaise`, never set `AXMain`/`AXFrontmost`, never activate.
- `vscreen tree --pid P [--window ID] [--depth N]`: JSON nodes with path, role, subrole, title, value (truncated), description, identifier (incl. `AXDOMIdentifier`), enabled, focused, frame, actions, children. Must work for WKWebView content (Tauri apps) as well as AppKit.
- `vscreen click --pid P (--path PATH | --match role=..,title=..,id=..,label=..) [--action AXPress]`: AX action first; `--post` sends mouse down/up to that pid only (`CGEventPostToPid`) at the element centre without moving the cursor.
- `vscreen type --pid P (--path|--match) --text T [--mode value|keys]` and `vscreen key --pid P --key return|tab|escape|... [--mods cmd,shift]`: `value` sets `AXValue` (and focuses the element inside its app via `AXFocused` only if needed); `keys` posts Unicode key events to that pid only.
- Report in JSON what actually happened (action used, element resolved), and whether the target app ever became frontmost.
- Extend `docs/usage.md` and `vscreen help`.

## Out of scope

- Capture (F003). Any global event tap, cursor warp, AppleScript keystroke.

## Acceptance

- With the F001 fixture on the virtual display while another app is front: `tree` finds the field and button; `type --mode value` and `--mode keys` both change the field; `click` increments the label; the fixture label proves each effect; frontmost app identical before, during, after.
- `window move` moves a fixture window from main (ordered behind other windows) to the virtual display without it coming to the front.
- Checks run only against the fixture, never against Adam's own windows.

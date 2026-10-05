---
name: vscreen
description: >
  Drive macOS app windows on a hidden virtual display without stealing the user's
  focus or capturing their main screen. Use when an agent must control a native
  macOS app, move a window off the user's monitor, read an accessibility tree,
  click/type into UI, or screenshot/record only the virtual display. Triggers:
  "vscreen", "virtual display", "hidden display", "control mac app without focus",
  "move window off screen", drive AppKit/Tauri/Electron off the main monitor,
  focus-free UI automation on macOS. Prefer vscreen over osascript, cliclick,
  CGEvent global posts, or main-screen screenshots for this class of work.
---

# vscreen

macOS CLI: hidden virtual display + focus-free window/AX control + capture locked
to that display.

Binary: `vscreen` if on `PATH`, else `~/.local/bin/vscreen`
(symlink → `~/Applications/vscreen.app/Contents/MacOS/vscreen`).

Full reference (optional deep dive): repo `docs/usage.md`, or
https://github.com/iceener/vscreen/blob/main/docs/usage.md

## Contract

- Every command → **one JSON object on stdout**.
  - OK: `{"ok":true,...}`
  - Fail: `{"ok":false,"error":{"code":"...","message":"..."}}` and exit 1
- Branch on `error.code`. Human logs → stderr; ignore for control flow.
- Acting commands return `focus` (`frontmostUnchanged`, `targetBecameFrontmost`).
  If focus broke → **stop and report**. Do not keep clicking.

## Hard rules

1. **Never steal focus.** No activate, raise, `open` without `-g`, AppleScript activate.
2. **Never capture the main screen.** No `--allow-main`, no `VSCREEN_ALLOW_MAIN`.
3. Prefer **AX** click/type. Avoid `click --post` (needs `--allow-activation-risk`; may activate).
4. **Do not** run `vscreen permissions request` (GUI dialogs). If `permission_missing`, ask the user.
5. Do not stop a display another job started unless you own the session and nothing else needs it.
6. Prefer `--mode value` for text. Use `key` for return/tab/escape — not `type --mode keys` with control chars.

## Setup check (once per session)

```sh
vscreen doctor
```

Need:
- `permissions.accessibility: true` for window move / tree / click / type / key
- `permissions.screenRecording: true` only for `shot` / `record`
- `identity.valid: true`, prefer `selfResponsible: true`

If binary missing: tell user to install from the vscreen repo with `scripts/install.sh`
and grant Accessibility + Screen Recording to **vscreen** in System Settings
(Privacy & Security). Agents never drive those toggles.

## Standard loop

```sh
# 1. Display (reuse if already running)
vscreen display start          # alreadyRunning:true is fine
vscreen display status

# 2. Find window
vscreen window list --pid PID
# or: --app NAME | --bundle ID | --display virtual|main

# 3. Move onto virtual display (no raise/activate)
vscreen window move --window ID --to virtual --fit

# 4. Inspect UI
vscreen tree --pid PID --window ID
# Fresh WKWebView may return empty AXGroup once — repeat tree.

# 5. Act
vscreen click --pid PID --match role=AXButton,title=Send
vscreen type --pid PID --match id=message --text "Hello" --mode value
vscreen key  --pid PID --key return

# 6. Verify (needs Screen Recording; target required)
vscreen shot --window ID -o /tmp/vs-window.png
# or whole virtual display:
vscreen shot --display virtual -o /tmp/vs-display.png

# 7. Tear down only if this session started it and work is done
vscreen display stop
```

## Addressing UI

| Target | How |
| --- | --- |
| Window | CGWindowID from `window list` (`id`) |
| Element path | From `tree`: `w<CGWindowID>/0/2/...` |
| Element match | `--match` comma-separated terms; **all** must hold |

Match keys: `role`, `subrole`, `title`, `id` (AXIdentifier or DOM id),
`label` (description/aria-label/title), `value`, `placeholder`, `class` (one HTML class).

```text
key=value     exact
key~value     case-insensitive contains
```

Examples:

```sh
--match role=AXButton,title=Send
--match id=fixture.text
--match role=AXTextField,label~email
```

First depth-first hit wins; `matchCount` reports total. Empty match → one automatic 1s retry.

Windows/sheets never match as elements — address windows via `window` commands / path `w<id>`.

## Commands (cheat sheet)

| Command | Purpose |
| --- | --- |
| `help` | Command list |
| `doctor` | Permissions, signature, display — no prompts |
| `display start\|status\|stop` | Virtual display lifecycle |
| `window list` | Windows front→back |
| `window move --window ID [--to virtual] [--fit]` | Place on display |
| `tree --pid P` | AX tree JSON |
| `click --pid P (--path PATH \| --match T)` | AXPress by default; allow-listed actions only |
| `type --pid P ... --text T [--mode value\|keys]` | Prefer `value` |
| `key --pid P --key NAME [--mods cmd,shift,alt,ctrl]` | One key to that pid |
| `shot ... -o FILE.png` | PNG of virtual window/display |
| `record ... -o FILE.mov --duration S` | H.264, no audio |

`click` allow-listed actions: `AXPress` (default), `AXConfirm`, `AXIncrement`,
`AXDecrement`, `AXPick`, `AXCancel`. **`AXRaise` / `AXShowMenu` → `action_not_allowed`.**

## Capture rules

- Target **required**: `--window ID` \| `--pid P` \| `--title TEXT` \| `--display virtual`
- Missing target → `target_required`
- Anything on main / outside virtual → `outside_virtual_display` (no file written)
- No display running → `display_not_running` (never falls back to main)
- Prefer `--window` when known; `--pid`/`--title` pick largest on-virtual match

## Common errors

| code | meaning / agent action |
| --- | --- |
| `permission_missing` | Ask user to grant AX and/or Screen Recording to vscreen.app |
| `display_not_running` | `display start` |
| `target_required` | Pass `--window` / `--pid` / `--title` / `--display virtual` |
| `outside_virtual_display` | `window move --to virtual` first; never unlock main |
| `ax_window_not_found` | Window likely other Space / minimized; don't guess another frame |
| `window_minimized` | Do not unminimize; report |
| `not_arrived` | Read `error.details.window`; retry move or fail |
| `value_not_set` / `ax_failed` | Re-tree; try focusable field; avoid assuming success |
| `keys_not_routable` | App focus elsewhere; use `--mode value` or click first |
| `keys_no_effect` | Value unchanged; don't loop blindly |
| `target_frontmost` | `key` without element refused while target app is frontmost |
| `action_not_allowed` | Drop AXRaise/AXShowMenu |
| `display_busy` | Wait and retry start/stop |

## What not to do

- `osascript` keystroke / activate to "help" vscreen
- Global mouse warp or HID event taps
- `shot` without a virtual target
- `click --post` without explicit user need + `--allow-activation-risk`
- Killing the display daemon mid-flight another agent owns
- Prompting TCC (`permissions request`) from agent sessions

## Minimal smoke (optional)

If the vscreen repo is available and the user wants a self-check:

```sh
scripts/smoke.sh
```

Expect `smoke ok` and unchanged frontmost app. Does not require Screen Recording.

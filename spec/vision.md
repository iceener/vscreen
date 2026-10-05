# Vision

> Human-owned durable intent. Source: README.md (Adam's goal) and the owner's launch instruction of 2026-10-05.

## Product principles

- `vscreen` is a general macOS CLI for agents: a hidden software virtual display where agents drive app windows while Adam keeps working on his own screen.
- Never take Adam's focus: no app activation, no window raised or brought to the front, no global key presses, no cursor moves. This holds for the tool and for every test of it.
- Act through Accessibility actions or events posted to one process (`CGEventPostToPid`), never through the global HID event stream.
- Capture only the virtual display or one window, never Adam's screen.
- Output is JSON for agents; errors are JSON with a stable `code` and a non-zero exit.
- Permissions belong to `vscreen` itself (Accessibility, Screen Recording), not to whichever terminal runs it; the tool never triggers a system permission prompt unless Adam asks it to.
- The virtual display uses the private `CGVirtualDisplay` API (as BetterDisplay does) held open by a daemon. If that API fails on this macOS, say so plainly; the fallback is a dummy HDMI plug.

## Current direction

- macOS 26.5 on Adam's Mac (one Pro Display XDR, Apple Silicon). Install to `~/.local/bin/vscreen` with a short usage doc.
- Place the virtual display so the cursor rarely wanders onto it.
- Proof: a full Alice native scenario (plant `/Users/overment/playground/alice-app/alice`, read only) passes on the virtual display while another app stays in front. Alice hooks are written as notes for Adam, never committed there.

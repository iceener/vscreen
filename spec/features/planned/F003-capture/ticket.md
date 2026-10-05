# F003 · Agents capture only the virtual display or one window

## Outcome

An agent can take a PNG screenshot or a short video of the virtual display or of one window, and never of Adam's own screen by accident.

## Scope

- `vscreen shot (--display virtual|ID | --window ID) -o FILE.png [--scale 1|2]` via ScreenCaptureKit (`SCScreenshotManager`); JSON reports path, pixel size, display/window.
- `vscreen record (--display virtual|ID | --window ID) -o FILE.mov --duration SECONDS [--fps N]` via `SCStream` with `SCRecordingOutput`; returns when the file is finalized; also stops cleanly on SIGINT/SIGTERM.
- Default target is the virtual display; capturing the main display requires an explicit display ID (no silent fallback to Adam's screen when the virtual display is down: fail with `display_not_running`).
- Preflight Screen Recording with `CGPreflightScreenCaptureAccess`; fail with `permission_missing` before any ScreenCaptureKit call that could prompt.
- Extend `docs/usage.md` and `vscreen help`.

## Out of scope

- Window list/move and AX (F002). Audio capture.

## Acceptance

- With the F001 fixture on the virtual display: `shot --display virtual` and `shot --window ID` produce PNGs whose pixel size matches the display/window and show the fixture (inspect the image).
- `record --duration 3` produces a playable movie of about three seconds (`ffprobe` or AVFoundation duration).
- Frontmost app unchanged across every check; nothing is captured from the main display.

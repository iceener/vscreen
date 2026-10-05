# Styleguide

> Project-owned coding practice for every coordinator, worker, and reviewer turn.

## Shape

- One Swift package at the repo root (`Package.swift`, Swift 6 toolchain, macOS 26 target). Executable target `vscreen`; private API declarations live in a small Objective-C/C target with one header, nothing else in it.
- One file per command family under `Sources/vscreen/` (display, windows, ax, capture, permissions); a small router and a JSON output helper shared by all.
- The daemon is the same `vscreen` binary in a hidden mode, not a second product.
- Scripts in `scripts/` (build, sign, install, smoke). `docs/usage.md` is the short usage doc and `vscreen help` prints the same command list.

## Prefer

- Every command prints exactly one JSON object on stdout: `{"ok":true,...}` or `{"ok":false,"error":{"code":"...","message":"..."}}` with a non-zero exit. Human logs go to stderr or the daemon log.
- Preflight permissions with non-prompting calls (`AXIsProcessTrusted`, `CGPreflightScreenCaptureAccess`) and fail with code `permission_missing` before touching an API that would prompt.
- Address windows by CGWindowID and pid; address elements by a stable path from `vscreen tree` or by attribute match (role, title, identifier, description).
- Small pure functions for parsing, matching and geometry, with plain `swift test` unit tests only where an edge is genuinely uncertain.

## Avoid

- Anything that activates an app or raises a window: `NSApp.activate`, `NSRunningApplication.activate`, `AXRaise`, setting `AXMain`/`AXFrontmost`, `open` without `-g`, `osascript ... activate`, `makeKeyAndOrderFront` in fixtures.
- Global input: `CGEventPost(.cghidEventTap/...)`, `CGWarpMouseCursorPosition`, AppleScript `keystroke`.
- Touching Adam's own windows in tests; tests use the repo fixture app or the Alice lab only.
- Keychain or TCC calls that may show a dialog during automated work.

# F001 · vscreen exists, holds a hidden virtual display, and owns its permissions

## Outcome

`vscreen` is installed at `~/.local/bin/vscreen`. `vscreen display start|stop|status` creates and removes a software virtual display through the private `CGVirtualDisplay` API, held open by a background daemon, placed so Adam's cursor rarely reaches it. `vscreen doctor` reports permission and display state as JSON. Accessibility and Screen Recording are granted to `vscreen` itself, so a grant survives rebuilds and works from any terminal or agent host. A fixture app gives later slices a safe window to drive.

## Scope

- Swift package skeleton per `.agents/limen/styleguide.md`: router, JSON output contract, `help`, `docs/usage.md`.
- Private API header for `CGVirtualDisplay`, `CGVirtualDisplayDescriptor`, `CGVirtualDisplayMode`, `CGVirtualDisplaySettings` (DeskPad and BetterDisplay-era declarations are the reference).
- Daemon: `display start` spawns the hidden `vscreen` mode detached (own session), writes state (pid, displayID, frame) under `~/Library/Application Support/vscreen/`, logs under `~/Library/Logs/vscreen/`; `stop` ends it; `status` reads state and verifies the display is online. Options for size and HiDPI; sensible default near 1920x1200 logical, HiDPI on.
- Placement: away from Adam's path. Main display is a 6K XDR, Dock autohides at the bottom, hot corner top-left locks the screen. Prefer touching the main display only at the bottom-right corner; verify with `CGDisplayBounds` what macOS actually accepts and report it.
- Own permission identity: every privileged invocation runs as its own TCC-responsible process (self re-exec with `responsibility_spawnattrs_setdisclaim`, or launchd), and the binary is signed with a stable self-signed code-signing identity kept in a dedicated keychain under `~/Library/Application Support/vscreen/` so the designated requirement does not change between builds. Never touch Adam's login keychain.
- `vscreen doctor`: AX trusted, screen capture preflight, signature/designated requirement, daemon/display state, using only non-prompting calls. `vscreen permissions request` is the one explicit, Adam-run command that may prompt or open System Settings.
- `scripts/install.sh`: release build, sign, copy to `~/.local/bin/vscreen`.
- Fixture: a tiny AppKit app (separate executable target) that opens one window with a text field, a button, and a label echoing clicks and text, on a display and origin given by flags, without activating itself (accessory policy, ordered without becoming key or front on Adam's display).

## Out of scope

- Window list/move, AX tree, click/type, capture: later tickets.

## Acceptance

- `swift build` clean; `scripts/install.sh` installs a signed binary; `codesign -d -r-` shows a certificate-based requirement, stable across two builds.
- `vscreen display start` then `status` shows an online display with its frame; `stop` removes it; no app activates and the frontmost app is unchanged throughout (record `NSWorkspace.frontmostApplication` before and after).
- `vscreen doctor` prints valid JSON from the installed binary.
- If `CGVirtualDisplay` creation fails on macOS 26.5, the outcome says so plainly with the error.

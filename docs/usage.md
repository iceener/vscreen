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

`display start` returns the running display when one exists (`"alreadyRunning":true`).
`--origin X,Y` is a global position in points (top-left origin, main display at 0,0).

## Files

- State: `~/Library/Application Support/vscreen/display.json` (daemon pid, display id, placement).
- Daemon log: `~/Library/Logs/vscreen/daemon.log`.

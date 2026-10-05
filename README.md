# vscreen

vscreen is a command-line tool for macOS. It creates a hidden virtual display. An agent can move app windows to this display and control them there. The user keeps the keyboard focus. No window comes to the front on the user's display.

## What it does

- It creates a software virtual display. A background process keeps the display open.
- It lists app windows. It moves a window to the virtual display. The app does not become active.
- It writes the accessibility tree of an app as JSON.
- It clicks and types into elements. It uses Accessibility actions or events that go to one process only. It does not send global key presses and does not move the pointer.
- It takes a screenshot or a video of one window on the virtual display, or of the virtual display. It never captures the main screen.

## Install

Requirements: macOS 26 and the Swift 6 toolchain (Xcode or the Command Line Tools). The tool was tested on macOS 26.5 on Apple silicon.

```sh
git clone https://github.com/iceener/vscreen.git
cd vscreen
scripts/install.sh
```

The script builds a release binary and puts it in `~/Applications/vscreen.app`. It signs the app with a local self-signed certificate. It links `~/.local/bin/vscreen` to the app. Add `~/.local/bin` to your `PATH`.

The certificate is in `~/Library/Application Support/vscreen/signing/`. Keep this folder. With a new certificate, you must grant the permissions again.

## Use

```sh
vscreen help                    # list all commands
vscreen doctor                  # show permissions and display state
vscreen display start           # create the virtual display
vscreen display status
vscreen display stop
vscreen window list --pid PID
vscreen window move --window ID --to virtual
vscreen tree --pid PID
vscreen click --pid PID --match role=AXButton,title=Send
vscreen type --pid PID --match id=message --text "Hello" --mode value
vscreen key --pid PID --key return
vscreen shot --pid PID -o window.png
vscreen record --window ID -o window.mov --duration 10
```

The default display is 1920x1200 points with HiDPI. It touches the main display only at the main display's bottom-right corner, so the pointer seldom moves onto it.

Full reference: [docs/usage.md](docs/usage.md).

## Capture rule

vscreen never captures the main screen. The tool enforces this rule. An agent cannot turn it off.

- `shot` and `record` need a target: `--window ID`, `--pid PID`, `--title TEXT`, or `--display virtual`. Without a target, the command fails with `target_required`.
- The target window must be fully on the virtual display. Use a window target when you know the window.
- Any other display or window fails with `outside_virtual_display`. vscreen writes no file.
- Only a person can unlock main-screen capture. This needs both the `--allow-main` flag and the environment variable `VSCREEN_ALLOW_MAIN=1`.

## Output

Each command writes one JSON object to standard output.

- Success: `{"ok":true,...}`
- Failure: `{"ok":false,"error":{"code":"...","message":"..."}}` and exit code 1.

Agents must read `error.code`. Logs go to standard error.

## Permissions

vscreen needs Accessibility and Screen Recording. macOS gives these permissions to `vscreen.app`, not to the terminal that runs it.

1. Run `vscreen permissions request`. This command can show system dialogs.
2. Open System Settings > Privacy & Security.
3. Turn on vscreen in Accessibility.
4. Turn on vscreen in Screen & System Audio Recording.

A screenshot or a recording can also show a macOS alert: "vscreen is requesting to bypass the system private window picker". The alert comes to the front. Click Allow. macOS shows the alert again after some time (approximately one month). If you refuse it, it comes back on a later capture. To get the alert at a time that is good for you, run a capture yourself:

```sh
vscreen display start && vscreen shot --display virtual -o /tmp/vscreen-check.png
```

The other commands do not show permission dialogs. `vscreen doctor` shows the permission status.

## Limits

- The virtual display uses `CGVirtualDisplay`. This is a private macOS API. A macOS update can stop it. If this occurs, use a dummy HDMI plug to get a second display.
- `type --mode keys` works only when the target element already has the focus in its app. In other cases, use `type --mode value` or `click`.
- `click --post` sends mouse events to the app. This can make the app active. vscreen refuses it unless you also give `--allow-activation-risk`.
- Windows on other Spaces can be missing from the Accessibility data. `window move` then fails.

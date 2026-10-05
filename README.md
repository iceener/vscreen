# virtual-screen (`vscreen`)

General macOS CLI for agents. It creates a hidden virtual display and lets any agent
drive app windows there without taking Adam's focus or covering his screen.

## Goal
- `vscreen display start|stop|status`: create or remove a software virtual display (CGVirtualDisplay). Place it so it does not get in Adam's way.
- `vscreen window list|move`: list windows; move any app window onto the virtual display without activating the app.
- `vscreen tree`: dump the accessibility tree (windows, elements) of an app as JSON.
- `vscreen click|type`: act on an element without activating the app or stealing keyboard focus (AX actions, or events posted to the process, never global key presses).
- `vscreen shot|record`: capture only the virtual display or one window.
- JSON output for agents. Short usage doc. Installed on PATH (~/.local/bin).

## Proof
First user: Alice native tests (plant /Users/overment/playground/alice-app/alice, app-lab window).
A full Alice native scenario must pass while another app is in front and Adam keeps typing elsewhere.
No focus steal, no window pops to the front.

## Constraints
- macOS 26.5. Private API may break on updates; report clearly if it fails (backup: dummy HDMI plug).
- Name every permission Adam must approve (Accessibility, Screen Recording) in one line.

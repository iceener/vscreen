# Alice hook for vscreen (note for Adam; not committed to Alice)

Why: the lab window is created hidden and revealed with `orderFrontRegardless` on the main display, so it covers your screen, and a covered window stops painting. With this hook the window is placed on the vscreen virtual display before it is ever revealed, so it never shows on your screen and keeps painting.

Used for the F004 proof in a throwaway worktree (`/Users/overment/playground/alice-app/.vscreen-proof-alice`, detached at alice-v6 `4f01e4b5e`).

## Change (two places, 17 lines)

`src-tauri/src/automation.rs`, above `show_without_activation`:

```rust
/// Place the hidden lab window at `ALICE_LAB_WINDOW_ORIGIN=x,y`
/// (global top-left points, e.g. inside a virtual display) before it is ever revealed.
pub(crate) fn place_lab_window(app: &tauri::AppHandle) {
    use tauri::Manager;
    let Some((x, y)) = std::env::var("ALICE_LAB_WINDOW_ORIGIN").ok().and_then(|value| {
        let (x, y) = value.split_once(',')?;
        Some((x.trim().parse::<f64>().ok()?, y.trim().parse::<f64>().ok()?))
    }) else {
        return;
    };
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.set_position(tauri::LogicalPosition::new(x, y));
    }
}
```

`src-tauri/src/lib.rs`, in `.setup(...)` right after `configure_main_window_chrome(app.handle())?;`:

```rust
#[cfg(feature = "automation")]
automation::place_lab_window(app.handle());
```

No change to `wdio.conf.mjs` or the debug kit was needed: the app inherits the variable from the runner's environment.

## Use

```sh
vscreen display start
# centre an 880x600 lab window on the virtual display
eval "$(vscreen display status | python3 -c 'import json,sys; f=json.load(sys.stdin)["frame"]; print(f"export ALICE_LAB_WINDOW_ORIGIN={int(f["x"]+(f["width"]-880)/2)},{int(f["y"]+(f["height"]-600)/2)}")')"
sh scripts/debug/native-chat-panels.sh
```

## Still open in Alice (from the F921 lead's findings, unchanged by this hook)

- tao's launch-time `activateIgnoringOtherApps(YES)`: in both proof runs it did not take the front on macOS 26.5.
- Scenarios that call `toggle_window`, osascript `set frontmost`, or System Events keys still take focus by design.

PASS 6bbe362e948765f520f6f90f6db9d69be3c69349

No acceptance bullet is proven broken. The F002 code builds cleanly. The worker's fixture runs in `notes.md` are the evidence for the three acceptance bullets. I did not re-run them, because the task forbids running vscreen and the fixture. Four notes should be fixed before agents drive shared apps such as Alice or browsers: findings 1 to 4.

**Candidate identity:** HEAD is `6482cee`, a later main commit with the F004 proof. It is not the F002 merge `6bbe362`. `git diff --stat 6bbe362 HEAD -- Sources docs Package.swift` is empty, so the reviewed F002 code is byte-identical to the candidate. The tree is clean.

## Findings

1. **`click --post` has no gate, and the docs contradict themselves.** High. The code path is proven. Activation is plausible but not run.
   - Where: `Sources/vscreen/AX.swift:354-367` and `:385-399`, `Sources/vscreen/main.swift:20-21`, `docs/usage.md:49`, `:60-62` and `:98`.
   - Scenario: an agent reads `vscreen help`, which says the flag sends mouse down/up "to that pid only; the cursor does not move". It runs `click --pid <Alice> --match id=send --post`. A posted left-mouse-down in a non-key window of an inactive app can make that window key and activate the app. The worker inferred the same risk in `notes.md:12`. Adam's frontmost app then changes.
   - Nothing refuses or warns. Help and the docs table do not mention the risk. `docs/usage.md:61` says these commands "never activate an app", but `:98` says `--post` may.
   - Fix: put `--post` behind an explicit opt-in, or remove it until the live check listed under "Open for the next slice" is done. Make help match `docs/usage.md:98`.

2. **`click --action` accepts any action the element offers, including `AXRaise` and `AXShowMenu`.** Medium. The code path is proven. The visible effect is plausible.
   - Where: `AX.swift:370-375`. The only check is `target.fields.actions.contains(action)`.
   - Window roots offer `AXRaise` (`notes.md:42`). Text fields offer `AXShowMenu` (`notes.md:43`).
   - Scenario: `click --pid P --path w<id> --action AXRaise` raises a window. `--action AXShowMenu` opens a context menu in an inactive app. Menu tracking may take keyboard input until the menu closes.
   - This contradicts `docs/usage.md:61` ("never … raise a window"), the ticket's "Never AXRaise", and the styleguide's Avoid list.
   - Fix: deny `AXRaise` and decide on `AXShowMenu`. A stricter option is an allow-list: `AXPress`, `AXConfirm`, `AXIncrement`, `AXDecrement`, `AXPick`, `AXCancel`.

3. **`AXFocused` can be written to an AXWindow element.** Medium. The code path is proven. The focus effect is plausible.
   - `AX.swift:222-226`: `search` tests the root window itself. It is first in DFS order, and the `label`/`title` keys match the window title.
   - `AX.swift:446-448`: `type --mode value` calls `focusInsideApp` whenever the AXValue write does not stick.
   - `AX.swift:455` and `:542`: the keys path and `key` always call `focusInsideApp`.
   - `focusInsideApp` (`:405-411`) does not check the role.
   - Scenario: `type --pid <Alice> --match label~Alice --text hi` is meant for an input whose aria-label contains "Alice". It resolves to the window titled "Alice". The AXValue write fails, and then `AXFocused=true` is set on the window. `--path w<id>` does the same.
   - `notes.md:27` names "AXFocused on a window" as deliberately not tried, because a key window takes keyboard focus from Adam.
   - Fix: start `search` at the root's children, or refuse AXWindow and AXSheet targets for `type` and `key`. Also refuse AXFocused on window roles inside `focusInsideApp`.

4. **The frame fallback in `window move` can move a different window of the same app.** Medium. The logic error is proven. The trigger is plausible.
   - Where: `Windows.swift:182-187`. When no AXWindow matches the target id, the frame filter runs over every candidate. That includes windows whose `_AXUIElementGetWindow` id is known and different.
   - Scenario: the agent's target W1 is on another Space, so it is missing from `AXWindows` (`notes.md:101`). Adam's window W2 of the same app, for example a browser or Alice, is on the current Space with an identical frame. Then `byFrame == [W2]`, and W2 moves to the virtual display with `axWindowMatch:"frame"`.
   - The result describes W1 with `arrived:false` (`:247-252`, `:264`) and no error. The agent never learns that Adam's window moved.
   - Fix: keep only candidates where `axWindowID($0) == nil` before matching by frame.

5. **The keys guard runs only once, before a multi-character sequence.** Low to medium. Plausible.
   - Where: `AX.swift:455-457` and `:489-494`. `postText` sends each character with keycode 0 and a Unicode string override.
   - AppKit key bindings map by characters. So `"\t"` triggers `insertTab:`, which moves to the next key view. `"\r"` or `"\n"` triggers `insertNewline:`, which fires the field action or submits a form.
   - Scenario: `type --mode keys --text "a\tb"` puts `b` into the next field of the target app.
   - The keys stay inside the target pid. Only the element is wrong, but `docs/usage.md:95-96` says keys "never land in another element".
   - Fix: refuse control characters in keys mode and point to `vscreen key`, or re-run `requireKeyRoute` before each character.

6. **`key` without `--path` or `--match` has no guard and does not check the pid.** Low. Proven by reading.
   - Where: `AX.swift:537-545`. This path never calls `rootWindows`, so a dead or wrong pid still returns `ok:true` instead of `app_not_found`.
   - No command refuses a target pid that is already frontmost (`targetActiveBefore:true`, `Windows.swift:298`).
   - Scenario: `key --pid <Alice> --key return` while Adam uses Alice on the main display. The Return goes to Alice's focused element, which can be Adam's composer.
   - This behaviour is documented ("to its focused element"), so treat it as hardening: refuse when the target is frontmost, or require an element or an explicit flag.

7. **`type --mode value` reports `ok:true` when the write failed.** Low. Proven.
   - Where: `AX.swift:441-469`. If both writes return a non-zero `axError`, the command still returns `{"ok":true,"changed":false,...}`.
   - The styleguide requires `ok:false` on failure. An agent that checks only `ok` will believe the text was typed.
   - The same shape occurs in three other places: keys mode with `note` (`:465-467`), and `window move` with `arrived:false` or `resized.ok:false`.
   - Fix: throw `ax_failed` when `error != .success` and the value did not change.

8. **The `keys_not_routable` error hides a focus change that already happened.** Low. Proven.
   - Where: `AX.swift:455-456` and `:542-543`. `focusInsideApp` writes `AXFocused` before `requireKeyRoute` throws.
   - The error JSON carries only a message. So the moved DOM or AppKit focus is not reported, although the ticket asks to "report in JSON what actually happened".

9. **`window move` ignores minimized windows and does not bound the offset.** Low. Plausible.
   - Where: `Windows.swift:219-271` never reads `AXMinimized`. A window can report `arrived:true` from its CG bounds while it is still minimized in the Dock. The only hint is `window.onScreen:false`.
   - `--x` and `--y` (`:224-225`) are not bounded by the display. With `--fit`, an offset past the display edge gives `placement` (`:203`) a negative size, which is then written as AXSize.

10. **Help omits `--window` for `key`.** Low. Proven.
    - `main.swift:24` and `docs/usage.md:51` leave it out, but `AX.swift:530` accepts `--window`.
    - Otherwise help and the docs table are identical: a script compared all 14 rows.

11. **The fixture decides the move target's visibility only once.** Low. Plausible.
    - Where: `Sources/vscreen-fixture/main.swift:202` and `:212`. Alpha becomes 1 only if another window covers the target at launch, and the check never runs again.
    - If the covering window later moves away, an opaque fixture window shows on Adam's main display.
    - If the target is not covered at launch, it stays at alpha 0 on the main display. `notes.md:71` shows it listed in front of a full-screen Slack Space. I did not verify that alpha-0 windows let clicks pass through.

12. **`targetBecameFrontmost` takes three samples, not "ever".** Low. Note.
    - Where: `Windows.swift:284-300`. The samples are taken before the action, just after it (one 20 ms run-loop turn), and after a 250 ms settle. All use the in-process `NSWorkspace` value.
    - A short activation between samples is missed. The external samples in `notes.md` agreed with these readings, so the acceptance evidence stands.

## Read with no finding

- F002 sources contain no `activate` call, no `AXRaise` call, no `AXMain` or `AXFrontmost` write, no `CGWarpMouseCursorPosition`, no tap-level `CGEventPost`, no `makeKeyAndOrderFront`, and no AppleScript (grep over `Sources/`).
- All event posting uses `postToPid` with a `.privateState` source.
- `requireAccessibility` uses the non-prompting `AXIsProcessTrusted` and runs before every AX call.
- Errors go through `CLIError` and print `{"ok":false,"error":{code,message}}` with exit 1.
- `window list` and `tree` output every field the ticket lists.
- The fixture uses the `.accessory` activation policy and `orderBack`. It refuses to open its primary window on the main display.
- The board line for F002 in `spec/build.md:23` is consistent with this review.

## Checks run

- `git rev-parse HEAD` returned `6482ceee453a…`. `git status --short` showed a clean tree. `git diff --stat 6bbe362 HEAD -- Sources docs Package.swift` was empty.
- `swift build` (debug, both products): "Build complete! (8.99s)", with no warnings in the output.
- A Python script compared `commandList` in `main.swift` with the command rows of `docs/usage.md`: 14 rows each, no differences.
- grep for focus and activation APIs across `Sources/`.

## Not run

- vscreen, the fixture, `install.sh`, `sign.sh` and `smoke.sh`. The task forbids them.
- The three acceptance bullets. Their evidence is the worker's runs in `notes.md` (runs 2 and 3, the keys probe and the web probe), and this review did not reproduce it.
- `swift test`. `Package.swift` has no test target.

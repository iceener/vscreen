# F003 notes

## What landed

- `Sources/vscreen/Capture.swift`: `shot` and `record`. Router and help lines are in `main.swift`. The docs are in `docs/usage.md` under "Capture".
- Target rule: the default is the virtual display. If `display status` is not `running`, the command fails with `display_not_running`. A `--display ID` other than the virtual display fails with `outside_virtual_display` unless `--allow-main` is passed. The same is true for a `--window ID` whose `SCWindow.frame` is not fully inside `CGDisplayBounds(virtual)`. The ticket asks only for an explicit ID for the main display. `--allow-main` on displays is stricter, for consistency with windows.
- `CGPreflightScreenCaptureAccess` runs before any ScreenCaptureKit call (`permission_missing`). Argument errors come first, then the preflight, then target resolution.
- Shot: `SCScreenshotManager.captureImage`. Size = `filter.contentRect` × scale. The default scale is `filter.pointPixelScale`. `showsCursor = false`. The PNG is written with ImageIO.
- Record: `SCStream` + `SCRecordingOutput` (H.264 `.mov`), with no stream output attached. It waits for `recordingOutputDidFinishRecording`, then reads the duration with `AVURLAsset.load(.duration)`. SIGINT/SIGTERM handlers (DispatchSource, `SIG_IGN`) are installed before capture starts.

## Edits outside Capture.swift (review these)

1. **`Permissions.swift` `runAsOwnResponsibleProcess`:** the wrapper now forwards SIGINT/SIGTERM to the re-executed child. Before this change, `kill -TERM <pid the agent started>` killed only the wrapper. The child kept recording, and the agent lost the JSON. This affects every command, but the child's default action on these signals is still to terminate.
2. **`Display.swift` `isDaemonProcess`** (separate commit `9fddf72`): `scripts/install.sh` replaces the bundle and then deletes the old one. After that, `proc_pidpath` fails for a daemon that was started from that bundle. `display status` then reported `running:false, stale:true` while display 55 was still online. A later `display start` would remove the state file and create a **second** display with the same identity. The orphaned daemon could then not be stopped with `display stop`. Fix: if `proc_pidpath` fails, check `proc_name == "vscreen"`.
   - **Hazard now:** the display daemon (pid 29027, display 55) runs from an executable that `/tmp/vscreen-F003/vscreen.app` used to hold. Any binary without this fix (for example, the F002 job's bundle) sees it as stale. The coordinator must stop it with a binary that has the fix (or `kill -TERM 29027`). Do not run `display start` from an old binary while it runs.

## Checks run (installed `/tmp/vscreen-F003/bin/vscreen`, signed `com.overment.vscreen`)

Doctor: `"permissions":{"accessibility":true,"screenRecording":true}`, `selfResponsible:true`.

Frontmost app, recorded with `vscreen doctor` before and after each check. It was equal within every check. It changed between checks (Slack → Helium → com.anysphere.sand → Helium), because Adam was working. vscreen did not activate anything.

**Before the display was started** (frontmost before/after = `com.tinyspeck.slackmacgap`):

```
vscreen shot -o a.png                    -> {"error":{"code":"display_not_running",...},"ok":false} exit=1
vscreen shot --display virtual -o a.png  -> display_not_running
vscreen record -o a.mov --duration 1     -> display_not_running
vscreen shot --display 1 -o a.png        -> {"error":{"code":"outside_virtual_display","message":"display 1 is not the virtual display; pass --allow-main to capture it"},"ok":false}
vscreen shot -o /nonexistent/a.png       -> output_failed
vscreen shot --display virtual --window 3 -o a.png -> bad_arguments (either --display or --window)
vscreen shot --scale 3 -o a.png          -> bad_arguments
```

No files were written.

**Display and fixture:** no display was running, so `vscreen display start` started one (default config): display 55 at (3008,1692,1920,1200), pixels 3840x2400. It was not stopped; the coordinator owns it. The fixture was started with `.build/debug/vscreen-fixture --display 55 --exit-after 900 --title "F003 fixture"` and reported `"frame":{"height":182,"width":420,"x":3048,"y":1732},"appActive":false,"windowNumber":174621`.

**Shots** (frontmost before/after = `com.tinyspeck.slackmacgap`):

```
shot --display virtual -o display.png  -> "pixels":{"height":2400,"width":3840},"scale":2,"target":{"displayID":55,"kind":"display","virtual":true,...}
shot --window 174621 -o window.png     -> "pixels":{"height":364,"width":840},"scale":2,"target":{"kind":"window","onVirtualDisplay":true,"pid":29068,"title":"F003 fixture","windowID":174621,...}
shot --window 174621 --scale 1 -o window1x.png -> 420x182
shot -o display-default.png --scale 1  -> 1920x1200
```

`sips` confirmed the same pixel sizes. All PNGs were opened as images. The fixture window (title "F003 fixture", "type here", "Press", "clicks: 0") is visible at 40,40 points in the display shots. The window shots show only the fixture window.

**Refusal of a main-display window** (Slack window 113879 at 375,317, found with `CGWindowListCopyWindowInfo`; frontmost before/after = Helium):

```
shot --window 113879 -o refused.png   -> {"error":{"code":"outside_virtual_display","message":"window 113879 at 375,317 1700x1031 is not inside the virtual display; pass --allow-main to capture it"},"ok":false}
record --window 113879 ...            -> outside_virtual_display
shot --window 999999 ...              -> window_not_found
```

No refused.* files exist. `--allow-main` was never exercised, so nothing was captured from the main display.

**Record** (frontmost before/after = Helium, then com.anysphere.sand):

```
record --display virtual -o display.mov --duration 3
  -> "duration":3.058,"elapsed":3.084,"fps":30,"pixels":{"height":2400,"width":3840},"stoppedBy":"duration"  (wall 3.7 s)
  ffprobe: h264 3840x2400, nb_frames=33, format duration=3.033333
record --window 174621 -o window.mov --duration 3 --fps 10
  -> "duration":3.03,"pixels":{"height":364,"width":840},"stoppedBy":"duration"
  ffprobe: 840x364, nb_frames=31, duration=3.030000
record -o term.mov --duration 30 & sleep 1.5; kill -TERM <wrapper pid>
  -> "stoppedBy":"SIGTERM","duration":1.158, exit=0; ffprobe duration=0.883333, 27 frames
record -o int.mov --duration 30 & sleep 1.5; kill -INT <wrapper pid>
  -> "stoppedBy":"SIGINT","duration":0.692, exit=0; ffprobe duration=0.691667, 19 frames
```

After that, `pgrep -fl "vscreen record"` found no processes. Frames were extracted with ffmpeg at 2.5 s (display.mov) and 2 s (window.mov) and opened. Both show the fixture.

## Observations

- The movie of a static fixture still has frames across the whole duration (33 frames over 3 s at 30 fps). SCK sends few frames for static content, but SCRecordingOutput keeps the full time span.
- While a window is recorded, macOS 26 replaces the window's title-bar buttons with a "shared" badge, and the badge is in the movie. This does not happen for display recording or for shots.
- For signal stops, the AVFoundation duration and the ffprobe duration differ by about 0.3 s (term.mov). The reported `duration` comes from AVFoundation.
- `--scale` is on `shot` only. `record` always uses the backing scale (as in the ticket).

## Cleanup

- The fixture (pid 29068) was killed. `pgrep vscreen-fixture` finds nothing.
- The virtual display was left running (the shared-state rule).
- Test files are in `/tmp/vscreen-F003/out/` (PNGs, movies, extracted frames).

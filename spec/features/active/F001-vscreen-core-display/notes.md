# F001 notes

## Probe (macOS 26.5.2, build 25F84, Apple M4 Max, Pro Display XDR main)

`CGVirtualDisplay` works on this macOS. A 30-line probe created a display with
`CGVirtualDisplayDescriptor` + `CGVirtualDisplaySettings(hiDPI=1, modes=[1920x1200@60])`:

```
applied=true displayID=8 online=true bounds=(-1920.0, 0.0, 1920.0, 1200.0) main=(0.0, 0.0, 3008.0, 1692.0)
mode points=1920x1200 pixels=3840x2400
frontmost before=md.obsidian after=md.obsidian
```

- Swift imports `-applySettings:` as `apply(_:)`.
- Modes are given in points; `hiDPI=1` gives a 2x backing store (3840x2400 pixels for 1920x1200 points). `maxPixelsWide/High` must cover the 2x size.
- Default placement by macOS: left of the main display, top-aligned, at (-1920, 0). That is next to the top-left hot corner, so vscreen must move it.
- Display IDs are not reused within a login session (8, 10, 11 across three runs).

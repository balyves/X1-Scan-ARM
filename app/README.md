# app

The macOS application **X1 Scan** (macOS 26, Swift 6). Decisions:
[`docs/decisions.md`](../docs/decisions.md), "Application, step 2".

- `X1Scan.xcodeproj`, `X1Scan/`: the application. AppKit shell (window,
  toolbar, menus, image canvas), SwiftUI palettes, String Catalog (English,
  French). Not sandboxed, hardened runtime.
- `X1ScanCore/`: models and view models (preview session, virtual X1,
  read-only inspector of the real X1, viewport, histogram, palette layout,
  export). No interface.

## Build and run

    open app/X1Scan.xcodeproj        # scheme X1Scan, then Run

or, from the command line:

    cd app
    xcodebuild -project X1Scan.xcodeproj -scheme X1Scan build

## Tests

    cd app/X1ScanCore
    swift test

The tests run against the virtual X1 (`tests/fixtures`) and never open a
real scanner.

## Scanner

- **Virtual X1** (default): replay of the captured preview. Preview, Stop and
  Export work.
- **Real X1**: only Scanner > Read Identity (INQUIRY, page 0x26, log page
  0x30, 0xDF), shown in Scanner Information (⌘I). Before reading: **X1 on,
  FlexColor closed** (only one program can open the scanner). Preview is
  disabled. The real X1 is never read at launch.

## Shortcuts

| Keys | Action |
|---|---|
| ⌘R | Preview |
| ⌘. or Esc | Stop |
| ⇧⌘E | Export |
| ⌘0 / ⌥⌘0 / ⌘1 | Zoom to fit / fill window / actual size |
| ⌘+ / ⌘− | Zoom in / out (next step) |
| ⌘I | Scanner Information |
| ⌘, | Settings |
| Tab | Show/hide all palettes |
| H, Z, C | Hand, zoom, crop tools |
| Space (held) | Hand, temporarily |
| Option-click (zoom tool) | Zoom out |
| ⌥⌘P | Palettes in full or as icons |
| ⌃⌘F | Full screen |

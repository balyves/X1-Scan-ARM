# Project decisions

Recorded on 2026-11-12. Change this file when a decision changes, and say
why.

## Platform

- **macOS 26 Tahoe only.**
- **Swift 6** (language mode 6, strict concurrency), **Xcode 26 or later**.

## Application

- **SwiftUI inside an AppKit shell.** Liquid Glass through the standard
  components, light and dark modes, full screen. Step 2 is described below
  ("Application, step 2").
- **Bilingual interface, English and French**, following the system
  language (String Catalog).

## Distribution

- **Not sandboxed.** The application opens the scanner through IOKit
  (SCSITaskUserClient).
- Distributed directly, **outside the Mac App Store**. Signed and notarised
  later.

## Other Flextight software

Recorded on 2026-11-14.

- **20More** (commercial, closed source) is a source of **feature ideas
  only**. We do not reuse, disassemble or otherwise analyse its software.

## Candidate building blocks (not chosen yet)

Recorded on 2026-11-14, for the future ideas of the README (DNG export, ICC
profiles, metadata). Nothing here is a dependency yet. **Check each licence
again before any use**: the project is MIT (CLAUDE.md, rule 3).

- **ImageIO** (Apple, system framework): TIFF writing, IPTC/XMP metadata,
  ICC profile embedding.
- **Little CMS** (lcms2, MIT): colour management, applying and building ICC
  profiles.
- **Adobe DNG SDK**, or **our own DNG encoder**: linear DNG export. The SDK's
  licence must be checked against MIT before linking it.
- **colour-science** (Python, BSD-3-Clause, to verify): prototyping only (profiles, densities), in
  tools outside the app.
- **ArgyllCMS** (AGPL): **only as an external tool** the user runs (for
  example to build a profile from an IT8 target), **never linked** into the
  app, bundled with it, or copied into the repository.

## Scope of version 1

- Scan and **export a raw 16-bit TIFF**: linear RGB, with only the
  corrections needed to form the image (flat field from the white and dark
  references, R/B line-gap realignment). No colour profile, no curves.
- The architecture is ready for **non-destructive processing modules**
  working on linear data, added in this order: basic adjustments, then full
  FlexColor-style corrections.

## X1Kit (step 1, no user interface)

Swift package in `X1Kit/`:

| Module | Role |
|---|---|
| `X1Transport` | `SCSITransport` protocol; `IOKitTransport` (real scanner, through a small C layer `CX1IOKit` adapted from tools/x1probe); `SimulatedX1` (replays tests/fixtures). |
| `X1Protocol` | CDB construction and response parsing: INQUIRY, pages 0x20 and 0x26, 0xDF state, log page 0x30. |
| `X1Preview` | FlexColor 4.8.13's preview sequence and the runner that executes it. |
| `X1Image` | Flat field, line gap, 16-bit TIFF writer. |

## Application, step 2 (shell on the virtual X1)

Recorded on 2026-11-12.

### Structure

- `app/X1Scan.xcodeproj` and `app/X1Scan/`: the application target, a thin
  layer (AppKit window, toolbar, menus, canvas; SwiftUI palettes). It holds
  the only String Catalog (`Localization/Localizable.xcstrings`).
- `app/X1ScanCore/`: Swift package with every model and view model, no
  interface and no user-facing text (typed states, translated by the app).
  Tested with `swift test`, in the CI too.
- The Xcode project uses synchronised folders and is written by hand; it is
  checked with `xcodebuild` in the CI. No sandbox; hardened runtime on.
  The fixtures in `tests/fixtures` are copied into the bundle for the
  virtual X1.

### Scanner access from the app

- **The preview runs only on the virtual X1.** `PreviewSession.start(on:)`
  takes a `VirtualScanner`, which can only be built from capture fixtures.
  Preview is disabled with the real X1, with the reason shown.
- **Real X1: reads only.** `ScannerInspector` opens an
  `IOKitTransport(policy: .readOnly)`, checks each command against
  `CommandPolicy.readOnly` itself as well, sends INQUIRY, MODE SENSE 0x26,
  LOG SENSE 0x30 and 0xDF, then closes the device at once so that FlexColor
  can open it. It stops after INQUIRY if the device is not a Flextight X1.
  Reading only happens when the user chooses Scanner > Read Identity (or
  the button in Scanner Information); never at launch (step 2b).
  The CI (`app` job) fails if a tracked file of `app/` contains
  `unrestricted`, `allowsStateChangingCommands`, `CommandPolicy(`,
  `CX1IOKit` or `cx1_`. This is a text check, not a proof; like every
  workflow step, a pull request that edits the workflow can remove it.
- **Stop**: the toolbar's Stop, ⌘. and Esc cancel the run; `PreviewRunner`
  then applies the rules of "Scanner safety" below. The session stays
  "stopping" until the stop sequence is over, and quitting waits for it.
- `SimulatedX1` accepts a `DB` stop received after SCAN but before its
  captured place, and then replays the 0xDF states recorded after
  FlexColor's own end-of-scan stop, so that stopping can be tried on the
  virtual X1. **[hypothesis]** No capture shows how a real X1 answers a `DB`
  sent while lines are still being read: a clean stop on the virtual X1
  proves nothing for the real scanner.

### Display

- The image builds up as lines arrive: `PreviewRunner.run(progress:)` reports
  each step and each READ, and `IncrementalPreviewDecoder` gives exactly the
  result of `PreviewDecoding` block by block.
- **Pacing of the virtual X1** (`Pacing.display`, about 4 s): a delay added
  only to see the image build up. **Not a measurement** of the real X1.
- **Colour [hypothesis]**: the corrected 16-bit values (the exported ones)
  are tagged **linear sRGB** and colour-matched to the display by
  ColorSync / Core Animation. The X1's primaries are unknown; this is a
  provisional choice, to be replaced by a scanner profile.
- **Pixel aspect [hypothesis]**: preview pixels are drawn 3 times taller than
  wide. The factor is one documented parameter,
  `X1Image.PreviewGeometry.pixelAspectRatio`, to be adjusted with captures of
  real scans. It is display only: decoded and exported images keep the
  scanner's pixels.
- The Info palette shows the corrected values (as exported) in large and the
  raw CCD samples behind the same pixel in small.

### Layout, ready for later steps

- `PaletteRegistry` lists the palettes; `PaletteLayout` (Codable, versioned)
  keeps order, folded palettes, column mode (expanded or icon bar), column
  width, each palette's placement (`docked` or `floating(frame)`) and the
  tool bar placement (`floating` capsule or `dockedColumn`). Saved in
  UserDefaults and reconciled with the registry on load.
- `Workspace` (a named layout) and the store exist as models.
- **Not done yet**: floating palette windows, docked tool column, workspace
  menu, drag-and-drop reordering (the header menu moves palettes up and down).

### Debug builds

Launch arguments, Debug only, for checking the window without screen
recording: `-X1ScanSnapshot <file.png>` (renders the window and the palettes,
then quits), `-X1ScanAutoPreview YES` (preview on the virtual X1 at launch),
`-X1ScanIconBar YES`.

## Application, step 2b (menus, zoom, settings)

Recorded on 2026-11-14. Nothing here changes what is sent to a scanner.

### Scanner menu instead of the Scanner palette

- The Scanner palette is gone (`PaletteID.scanner` removed; saved layouts
  drop it when reconciled). Scanner menu: Preview ⌘R, Stop ⌘., Virtual X1 /
  Real X1, Read Identity, Scanner Information… ⌘I.
- **Read Identity** opens Scanner Information and, with the real X1, runs
  the same read-only `ScannerInspector` read as before. With the virtual X1
  the identity comes from the fixtures. **Scanner Information** shows the
  last reading (identity, state, LOG 0x30 counters) and never reads by
  itself.
- The bottom bar names the source and its state (`ScannerStatusLine`):
  "Virtual X1 · Ready", "Real X1 · Not read", "… · Reading…",
  "… · Identity read", "… · Reading failed".

### Zoom

- `Viewport.mode`: `fit`, `fill` or `fixed`. Steps 6.25, 8.33, 12.5, 16.7,
  25, 33.3, 50, 66.7, 100, 200, 300, 400, 800, 1600 %.
- Fit (16-point margin) and Fill (no margin) are recomputed whenever the
  image area changes size: window, full screen, palettes hidden or shown.
  A chosen magnification (step, pinch, typed value) is kept.
- ⌘+ / ⌘− go to the step strictly above or below the current
  magnification, as Photoshop and Preview, also after a pinch.
- View menu: Zoom to Fit ⌘0, Fill Window ⌥⌘0, Actual Size ⌘1, Zoom In,
  Zoom Out, and a Zoom submenu with the steps. The bottom bar's percentage
  is a combo box with the same choices, where a value can be typed ("150",
  "12,5 %"); an invalid value puts the current one back.

### Window menu and palettes

- One item per palette, checked when shown, with the same title as the
  palette header. Show/Hide All Palettes (Tab, as in Photoshop, only when
  the image area has the focus: elsewhere Tab moves to the next control, as
  usual; a disabled menu item would still swallow the key, so `WindowMenu`
  passes it on), Reset Palette Layout.
- `PaletteLayout` version 2 adds `hidden`; version 1 layouts decode with
  nothing hidden. When every palette is hidden the column collapses.

### Settings (⌘,)

`AppSettings`, saved in UserDefaults:

- General: language (System / Français / English), written to the app's
  `AppleLanguages`, effective at the next launch; hide the serial number
  (on by default; replaces the unsaved "reveal" toggle of step 2).
- Display: appearance (System / Light / Dark); background around the
  image: neutral grey 18 % (middle grey, L* 50, sRGB 119/119/119, default),
  black or white; zoom when opening (Fit or 100 %).
- Export: folder and file name template, shared with the Export palette
  (`ExportSettings.nameTemplate`, default `X1-preview-{date}-{n}`; tokens
  `{date}`, `{heure}` or `{time}`, `{n}`). Step 2 settings keep their base
  name (`<base>-{date}-{n}`). The palette shows the name of the next file;
  the name actually written is computed again at export time (date, time
  and first free number then), tested.
- Scanner: source at launch (Virtual X1, Real X1, last used). The real X1
  is never read at launch.

### Fixes

- Stop is red (prominent) only while a preview runs.
- Histogram: square-root scale by default, logarithmic as an option.

### Debug builds

New launch arguments: `-X1ScanHideAllPalettes YES`, `-X1ScanZoomFill YES`.
The snapshot also renders the Settings window and Scanner Information.
They change the saved layout like a user would.

## Scanner safety

### Read-only guard

`IOKitTransport` checks every command before any IOKit call. By default
(`CommandPolicy.readOnly`) only these reads are allowed, each with its
direction, and each CDB must match the captured one **byte for byte**
(2026-11-14). Only the bytes marked below vary, and only within the values
seen:

| Opcode | Command | Direction | Allowed CDB | Bytes |
|---|---|---|---|---|
| 0x00 | TEST UNIT READY | none | `00 00 00 00 00 00` | 0 |
| 0x03 | REQUEST SENSE | in | `03 00 00 00 12 00` | 18 |
| 0x12 | INQUIRY | in | `12 00 00 00 60 00` | 96 |
| 0x4D | LOG SENSE | in | `4d 00 30 00 00 00 00 00 34 00` | 52 |
| 0x5A | MODE SENSE(10) | in | `5a 00 PP 01 00 00 00 LL LL 00` | per page, below |
| 0xD3 | status / sensors | in | `d3 00 00 00 02 00` | 2 |
| 0xDF | scanner state | in | `df 00 00 00 02 00` | 2 |
| 0xEE | read register | in | `ee 00 00 00 01 AA 00 00 01 00`, AA = 0x04-0x19 | 1 |

MODE SENSE pages and lengths seen in the captures: 0x20 (34), 0x21 (12,
100), 0x23 (12, 60), 0x25 (24), 0x26 (56), 0x27 (20), 0x29 (14). The CDBs of
INQUIRY, LOG SENSE, MODE SENSE, 0xD3, 0xDF and 0xEE come from the FlexColor
capture; those of TEST UNIT READY and REQUEST SENSE from `tools/x1probe`, to
which a real X1 answered. A test checks that every read of the read-only
list in `tests/fixtures/preview-sequence.json` passes.

Everything else is refused unless `CommandPolicy.unrestricted` is chosen
explicitly. It is only for runs the user has approved (CLAUDE.md, rule 4).

### Preview sequence

- **Captured values, no invented rules.** Windows, modes, exposure data,
  read sizes and FlexColor's redundant page re-reads are sent byte for byte
  as captured.
- **Measured position (page 0x20, bytes 27-28).** FlexColor's rule for
  feeding the measurement back into the next window is not understood: it
  sometimes sends the measured value (8 971), sometimes another one (6 443
  measured, 6 250 sent). We send the captured values. On a real scanner, the
  preview stops if a measurement differs from the captured one by more than
  **100**. Two captures differed by 64 on the first measurement (25 803 /
  25 867); the others were identical. **Threshold to revise.**
- **Waits on 0xDF.** We poll 0xDF after exactly the commands where FlexColor
  polled it, until the state FlexColor last saw there: `00 00`, or `00 01`
  after SCAN. Only `08 01` and `08 40` are accepted meanwhile.
- **Stop at the first unexpected response**:
  - a status other than GOOD;
  - a wrong number of bytes;
  - an INQUIRY other than `Imacon` / `Flextight X1`;
  - a SCAN response other than `00 00`;
  - a measured position out of tolerance;
  - a line counter going back after SCAN;
  - an unknown 0xDF state, or a timeout.
- **Anomaly after SCAN (0x1B)**: send only `DB 00 00 00 00 00`, wait for
  0xDF to return `00 00`, and send nothing else. **Anomaly before SCAN**:
  send nothing more.

### Tests

- `SimulatedX1` replays tests/fixtures/preview-sequence.json:
  - commands must arrive in the captured order; the only exception is an
    early `DB` after SCAN (see "Scanner access from the app");
  - polled values are replayed in order;
  - image data is synthesised from preview-calibration-profile.json.
- **Conformance**: against the simulator, our preview sends the same CDB,
  direction, transfer length and data_out as FlexColor, in the same order,
  apart from polling commands, and waits on 0xDF at the same points.
- **Nothing in the test suite talks to a real scanner.** `IOKitTransport` is
  only tested unopened.

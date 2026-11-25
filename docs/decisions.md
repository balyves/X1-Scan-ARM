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

- **A commercial Flextight application** (closed source, not named here) is
  a source of **feature ideas only**. We do not reuse, disassemble or
  otherwise analyse its software.

## Candidate building blocks (not chosen yet)

Recorded on 2026-11-14, for the future ideas of the README (DNG export, ICC
profiles, metadata). Nothing here is a dependency yet. **Check each licence
again before any use**: the project is MIT (CLAUDE.md, rule 3).

- **ImageIO** (Apple, system framework): TIFF writing, IPTC/XMP metadata,
  ICC profile embedding.
- **Little CMS**: colour management, applying and building ICC profiles.
  **lcms2 core only** (MIT); not the fast-float plugin, which is GPLv3 or
  commercial.
- **Adobe DNG SDK**, or **our own DNG encoder**: linear DNG export. To check
  before use: the SDK's licence, the licences of the libraries it bundles,
  and Adobe's DNG patent licence, which also applies to our own encoder.
- **colour-science** (Python, BSD-3-Clause, to verify): prototyping only
  (profiles, densities), in tools outside the app.
- **ArgyllCMS** (AGPL): **only as an external tool** the user runs (for
  example to build a profile from an IT8 target), **never linked** into the
  app, bundled with it, or copied into the repository.
- **Output profiles** (Adobe RGB, ProPhoto, sRGB, Display P3): generated
  with lcms2 or taken from ColorSync at run time; **never committed** as
  `.icc` files.

## Existing 3F files (future idea)

Recorded on 2026-11-14.

- 3F files are read from **our own format notes** (`docs/format-3f.md`),
  with no Hasselblad code and no code from other 3F readers. **No film
  profile is shipped.**
- The app may read the profiles of the user's own FlexColor installation,
  in place, at run time, on their machine, if there is one. They are never
  copied into the repository, the app bundle or the app's own data, and
  never used as test fixtures. Without them, a setting that needs a
  Hasselblad profile is **reported, never emulated**.
- Precautions (the first two follow CLAUDE.md, rules 1 and 2):
  - the serial number stored in a 3F is masked at export (tag 46279 and any
    metadata copied from it);
  - a real 3F file is **never** used as a test fixture;
  - batch edits (metadata) are written to **copies, or with a backup**, never
    in place without one.

## Scope of version 1

- Scan and **export a raw 16-bit TIFF**: linear RGB, with only the
  corrections needed to form the image (flat field from the white and dark
  references, R/B line-gap realignment). No colour profile, no curves.
  8-bit exports, added in step 3, are the one exception: sRGB curve and
  profile, provisional (see "Application, step 3").
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
  *Step 4 adds FlexColor's captured preview on the real X1, behind a hidden
  setting and a guard (see "Application, step 4").*
- **Real X1: reads only.** `ScannerInspector` opens an
  `IOKitTransport(policy: .readOnly)`, checks each command against
  `CommandPolicy.readOnly` itself as well, sends INQUIRY, MODE SENSE 0x26,
  LOG SENSE 0x30 and 0xDF, then closes the device at once so that FlexColor
  can open it. It stops after INQUIRY if the device is not a Flextight X1.
  Reading only happens when the user clicks Read Identity in Scanner
  Information (⌘I); never at launch (step 2b; the Scanner menu item was
  removed after step 4).
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
  real scans. It is used for the display and, since 2026-11-25 (user's
  request), for exported files: Export resamples a preview to square
  pixels (`RecipeRenderer`, "Rendering" below), so the factor, still a
  [hypothesis], now sets the geometry written in every exported preview;
  decoded images and the scan's master keep the scanner's pixels. Scans are shown with square pixels
  (`X1Image.ScanDecoding.pixelAspectRatio` = 1): the decoder resamples their
  lines by 3/5, and FlexColor's TIFF is 2 000 ppi both ways (protocol.md
  §10; journal, 2026-11-18, first real scan).
- The Info palette shows the corrected values (as exported) in large and the
  raw CCD samples behind the same pixel in small.

### Layout, ready for later steps

*Replaced in step 3 by the settings panel (palettes removed).*

- `PaletteRegistry` lists the palettes; `PaletteLayout` (Codable, versioned)
  keeps order, folded palettes, column mode (expanded or icon bar), column
  width, each palette's placement (`docked` or `floating(frame)`) and the
  tool bar placement (`floating` capsule or `dockedColumn`). Saved in
  UserDefaults and reconciled with the registry on load.
- `Workspace` (a named layout) and the store exist as models.
- **Not done yet**: docked tool column, workspace menu. Floating palettes
  and drag-and-drop reordering came with step 2c.

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

*Replaced in step 3 (palettes removed).*

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
  `{date}`, `{time}`, `{n}`; `{heure}` was accepted in step 2b only and is
  converted to `{time}` since step 2c). Step 2 settings keep their base
  name (`<base>-{date}-{n}`). The palette shows the name of the next file;
  the name actually written is computed again at export time (date, time
  and first free number then), tested.
- Scanner: source at launch (Virtual X1, Real X1, last chosen). The real X1
  is never read at launch. "Last chosen" is the last source chosen in the
  interface; a source imposed at launch (the startup setting, or the
  `-StartupSource` argument of tools/run-virtual.sh) is never saved
  (2026-11-16; the setting read "Last used" before). Only a change of source
  saves: choosing the source already shown saves nothing.

### Fixes

- Stop is red (prominent) only while a preview runs.
- Histogram: linear scale by default, logarithmic as an option (square root
  by default until 2026-11-16).

### Debug builds

New launch arguments: `-X1ScanHideAllPalettes YES`, `-X1ScanZoomFill YES`.
The snapshot also renders the Settings window and Scanner Information.
They change the saved layout like a user would.

## Application, step 2c (palettes, background, file names, Settings)

*The toolbar and the palettes of this step were replaced in step 3.*

Recorded on 2026-11-14. Nothing here changes what is sent to a scanner.

### Toolbar

- The Palettes button sits in the toolbar's button group, next to Export,
  before the inspector tracking separator: no button above the column.

### Palettes

- `PaletteLayout` version 3 adds `openInIconBar`; version 2 layouts decode
  with nothing open.
- **Icon bar**: each icon opens or closes its palette in a stack beside the
  bar, over the image area (top right); several can be open, in palette
  order. Saved.
- **Drag and drop**: a palette header (or icon) dropped on another palette
  moves it before that one; dropped below the last, to the end.
- **Floating panels**: Detach (header menu) or a palette dropped on the
  image area opens it in an `NSPanel` (utility, floating, hidden when the
  app is in the background), at the drop point. Its frame is saved
  (`PalettePlacement.floating`). Attach (button in the panel), Window >
  Attach All Palettes, or the panel's drag handle dropped on the column
  puts it back at its place. Closing the panel hides the palette; the Window menu shows it
  again at the same place.
- The column collapses when no palette is shown in it (hidden or floating).

### Background around the image

- `CanvasBackground.custom(SRGBColor)`, chosen with the system colour panel
  (Settings > Display > Custom…, or the colour swatch), applied live; saved
  as `custom:r,g,b`. A button puts back the neutral grey 18 %.

### File names

- Tokens stored in English only (`ExportToken`): `{roll}`, `{frame}`,
  `{date}`, `{time}`, `{n}`; the buttons that insert them at the cursor are
  translated. Step 2b templates with `{heure}` are converted to `{time}`.
- `{frame}`: two digits at least; +1 after each successful export (on by
  default). Passing to another roll puts it back to 1: only when the roll
  name is validated (Return, leaving the field, or an export) and differs
  from the last validated one; typing alone changes nothing. Setting the
  frame by hand validates a roll name typed before it, so the frame chosen
  for the new roll is kept. The "Next file" preview uses the validated
  settings, as the export does.
- `{n}`: first number free in the folder from a start value, with 1 to 6
  digits.
- `{roll}` with an empty roll name (or spaces only) is removed with its
  separators, so that "X1-{roll}-{frame}" gives "X1-07", not "X1--07": the
  run of separators before it, or after it at the start of the name; glued
  to other text on either side, only the token goes (2026-11-16).
- The builder (Export palette and Settings > Export) shows the sanitised
  name of the next file; the name actually written is computed at export
  time. Scan setting tokens (resolution, film, holder) come with real scans.

### Settings

- An icon toolbar at the top (`NSTabViewController`, toolbar style), as in
  Mail or Safari: General, Display, Export, Scanner.

### Fit (⌘0)

- A reported Fit at 6.25 % (the minimum) with a tiny image: Fit and Fill
  were computed from a size of the image area that was not known yet or
  degenerate. They are now computed only for an area of 64 points or more
  per side, and the area's size is also followed through the scroll view's
  frame notifications. The exact sequence was not reproduced.

## Application, step 3 (settings panel, after Epson Scan 2)

Recorded on 2026-11-14. Nothing here changes what is sent to a scanner.

### Window

- No window toolbar. From left to right: the image area; a narrow tool
  column (hand, zoom, crop; rotate, add frame, auto adjust disabled with a
  tooltip until they exist); the **settings panel**. Tool column and panel
  are one split view item: they resize together (280-480 pt for the panel,
  300 at first launch, then remembered; 260-640 until 2026-11-16, narrowed
  for the compact panel)
  and hid together with one command, View > Hide Settings Panel (⌥⌘P),
  until 2026-11-21. Since then (user's request), hiding keeps the tool
  column: the item narrows to it (minimum = maximum = the column's width,
  never collapsed), and the panel is hidden by ⌥⌘P or by dragging the
  divider past half the panel's smallest width (less 20 pt) towards the
  right edge; it comes back with ⌥⌘P, ⌥⌘1 to ⌥⌘3, or the divider (which
  stays on the left of the tool column) dragged back past half the
  smallest width plus 20 pt, so that a hesitating drag does not flicker. A drag that hides the panel keeps the width it had when the drag
  began (a `NSSplitView` subclass tells when its tracking begins and
  ends). The state is saved (`InspectorLayout.isHidden`), and full screen
  behaves the same (checked with synthetic drags, `-X1ScanDragProbe`).
  `NSSplitViewController` declares `splitView(_:constrainSplitPosition:
  ofSubviewAt:)` for Swift but does not implement it: the override never
  calls super (it crashed). With the panel hidden, Preview and Scan stay
  in the Scanner menu (Scanner > Scan added). The divider has a tooltip
  (`ShortcutTooltip.panelDivider`, ending with ⌥⌘P). User's answers the
  same day: ⌥⌘P hiding the panel alone is confirmed; Scan takes ⇧⌘R
  (`AppShortcut.scan`, in the Scan button's tooltip and on the Keyboard
  Shortcuts page); the Scanner menu items read "Preview…" and "Scan…",
  since a confirmation opens first on the real X1 (the panel's buttons
  keep "Preview" and "Scan").
  The item has a holding priority of 260, just above the image area's 250:
  at 750 it was above the divider drag and froze the panel at its minimum
  width. On macOS 26 the split view's `subviews` also hold the divider view,
  so the width code uses `arrangedSubviews` (it expected two subviews and
  never applied or saved the width). The saved width is
  applied after the first layout pass and only then saved again. The window
  resizes freely from 760 × 520.
  Small controls everywhere (`controlSize(.small)`).
- Panel, top to bottom (all sections open at first launch, then
  remembered): **Original** (film type, holder chosen among those ticked in Settings >
  Holders: saved in `ScanSettings`,
  not sent to the scanner yet); **Main / Advanced** tabs (Main: resolution,
  input and output size in preview pixels, scale, foldable histogram;
  Advanced: empty, with a sentence: only settings that work go there);
  **Output** (format, compression, name template menu and Edit… to
  Settings > Export, folder, Export Preview); **Preview** (Stop, in red,
  while a preview runs) and **Scan** (disabled) buttons. When Preview is
  disabled because the real X1 is chosen, a sentence under the buttons
  (and their tooltip) says to choose the virtual X1 in Settings.
- The source (virtual / real X1) is chosen in Settings > Scanner; the
  state is in the bottom bar; Scanner Information (⌘I) is in the Scanner
  menu, with its Read Identity button (the menu's Read Identity and source
  items were removed after step 4). First launch: virtual X1.
- Input size: the crop rectangle, or the whole preview, in pixels.
  Millimetres wait for the preview resolution to be confirmed by a
  capture. Resolution, scale and crop are saved and apply to the scan
  later: Export Preview writes the whole preview, and the size estimate of
  the bottom bar is for that file.
- `InspectorLayout` (width, hidden, folded sections, tab) replaces
  `PaletteLayout`; the keys of the palettes (`PaletteLayout`, `Workspaces`)
  are removed from the preferences at launch.
- Without an image the zoom menu shows "—" and the R G B values are
  hidden; every new preview gets the zoom of Settings > Display (Fit by
  default) when its first rows arrive; the crop rectangle is kept when the
  new preview has the same size.
- Bottom bar: scanner state, estimated size of the exported file
  (uncompressed), R G B under the pointer in the unit of Settings > Display
  (0-255 by default, percent, 16-bit; raw sensor values in the tooltip),
  zoom menu. In 0-255 the values are sRGB-encoded, as in an 8-bit export
  and in Photoshop (18 % linear grey ≈ 118; the neutral grey background is
  119, L* 50 being 18.4 %); in percent and 16-bit they are the
  linear corrected values (as exported in 16 bits). The tooltip says which.
- The panel can be hidden only through the model (⌥⌘P): dragging the
  divider cannot collapse it.

### Zoom menu (the 6.25 % report)

- The zoom combo box applied every selection change of its list, so
  browsing the list (arrow keys, and perhaps the pointer) could apply
  6.25 %, the first step under Fit and Fill. A choice is now applied only
  when confirmed (click on an entry, Return) or typed; leaving the field
  (a click elsewhere after browsing) applies nothing. The exact sequence
  of the report was not reproduced; this is the likely cause
  **[hypothesis]**.

### File name tokens

- Token buttons (Settings > Export) insert at the last caret position of
  the template field, recorded while the field has the focus, with "-"
  added where the neighbour is not already a separator
  (`ExportToken.insert`, tested). They used to land at the start, glued.

### Export formats

| Format | Encoding | Profile |
|---|---|---|
| RGB 16-bit (default) | linear, raw | none |
| RGB 8-bit | sRGB curve | sRGB (ColorSync), **provisional** |
| Grey 16-bit | linear luminance | none |
| Grey 8-bit | sRGB curve on the luminance | grey, sRGB curve (generated), **provisional** |

- Grey = 0.2126 R + 0.7152 G + 0.0722 B on the linear values (Rec. 709 /
  sRGB coefficients) **[hypothesis]**: the X1's primaries are unknown.
- 8 bits is never linear; the sRGB curve and profiles are provisional
  until the IT8 input profile. A warning is shown with 8-bit formats.
- Compression: none, LZW, or ZIP (Deflate in a zlib stream), both with the
  horizontal predictor (TIFF predictor 2). ZIP by default in 16 bits, LZW in
  8 bits; choosing a format selects its default compression. ImageIO writes
  LZW and Deflate but without the predictor (checked on 2026-11-14 with a
  throwaway program on macOS 26: no tag 317 in its files), so
  `X1Image.TIFFWriter` writes them itself (Apple's Compression framework
  for Deflate). Every combination is read back by ImageIO with identical
  values (tests).
- Sizes on the virtual X1's preview (2004 × 817), measured once with a
  throwaway probe (not a test), synthetic and smooth, so far more
  compressible than a real scan:

  | Format | None | LZW | ZIP |
  |---|---|---|---|
  | RGB 16-bit | 9.8 MB | 1.7 MB | 1.6 MB |
  | RGB 8-bit | 4.9 MB | 109 KB | 85 KB |
  | Grey 16-bit | 3.3 MB | 353 KB | 387 KB |
  | Grey 8-bit | 1.6 MB | 25 KB | 26 KB |

## Application, step 4 (captured preview on the real X1)

Recorded on 2026-11-16. The first commands that change the scanner's state
sent by our code: only FlexColor's captured preview, byte for byte.

### Guard

- `CapturedSequenceGuard` (X1Transport) is built from the capture itself,
  not from `PreviewScript`; a test checks that both give exactly the same
  commands. Since 2026-11-16 the app builds it from
  `tests/fixtures/preview-sequence-cold.json` (see the last section).
- Every command other than a poll must be, **in order**, the next captured
  exchange: CDB, direction, length and data out, byte for byte. Polls
  (0xEE, 0xD3, 0xDF reads of `CommandPolicy.readOnly`) are allowed between
  steps and do not move the sequence on. After SCAN the captured page 0x20
  read may be repeated, and `DB 00 00 00 00 00` is accepted out of order;
  after that stop only 0xDF passes. After the last captured command only
  polls pass. Anything else is refused before IOKit.
- `IOKitTransport(capturedSequence:)` checks every command with the guard
  instead of the read-only policy. It is not `.unrestricted`, and the CI
  check of `app/` (no other policy, no `CX1IOKit`) also checks that this
  mode is created in `AppModel.swift` only. `IOKitTransport.isReadOnly`
  tells the two modes apart. Timeouts: 30 s for a READ, 10 s for any other
  command (approved by the user on 2026-11-16).
- A command's SCSI status is used only with the service response
  TASK_COMPLETE. With SERVICE_DELIVERY_OR_TARGET_FAILURE the task status
  gives the cause, reported as `TransportError.deliveryFailure`: 0x01 task
  timeout, 0x02 protocol timeout (not CHECK CONDITION), 0x03 device not
  responding, 0x04 device not present; any other service response, or none,
  is a delivery failure too. The run then stops like any anomaly.
- The runner is unchanged: same checks and stop rules as on the virtual X1
  (status, length, identity, 0xDF states, position within 100 of the
  capture, line counter; before SCAN nothing more, after SCAN only DB then
  0xDF until `00 00`). Later changed: tolerance 256, line counter checked
  in the image phase only (see below).

### Reading the lines after SCAN

- In the capture FlexColor sends each 20-line READ without waiting for the
  page 0x20 line counter to announce the lines (e.g. 37 lines acquired, 23
  read, 20 more requested) **[confirmed]**; the scanner presumably holds the
  READ until the lines exist **[hypothesis]**. Waiting on the counter would
  change the timing of the sequence; and the last counter value observed,
  808, is read before the last READ, so how far it goes after it is not
  known (protocol.md §5).
- So the runner reads exactly as FlexColor did; the user's limit of 30 s
  without new lines is the READ timeout, after which the run stops with
  DB (tested with a simulated transport error after SCAN). A healthy scan
  slower than 20 lines in 30 s would be stopped. What the scanner and
  ASFireWire do after an IOKit timeout is not known. The guard still allows
  page 0x20 to be read again after SCAN (the runner does not use it).

### Enabling and confirming

- Hidden setting, off by default, no interface:
  `defaults write org.x1scanarm.X1Scan EnableRealPreview -bool YES`.
  Off: Preview stays disabled on the real X1, as before.
- On: Preview (⌘R or the panel) asks, every time, for ticked checks: the
  X1 is on, a holder is in place, FlexColor is closed, and (since
  2026-11-16) the X1 was switched off and on since the last real preview.
  Start is disabled until all are ticked, and Return does not start it.
- No identity read while a preview runs; changing the source stops a
  preview with the usual stop rules; quitting waits for the stop sequence.
- Any preview on the real X1 that does not complete (anomaly, Stop, change
  of source, quit) ends with an alert: before SCAN, switch the X1 off and
  on again (the session and modes FlexColor set may still be active);
  after SCAN, the same before another preview (the end of session is not
  sent on the stop path). The alert gives the log.
- The hidden setting can also be passed as a launch argument
  (`-EnableRealPreview YES`, argument domain); the confirmation is still
  asked.

### Log

- `LoggingTransport` writes every command and response, polls included,
  in the format of `tools/capture/cap3.py` (`CDB`, `ENV`, `FIN statut`,
  `RAW offset`, `REP`, plus `SENSE` and `ERREUR` for refusals and errors),
  READ data in a `.raw` file beside it: comparable with a FlexColor capture
  and readable by `tools/decode/decode_preview.py`.
- Each CDB line is written before the command is sent, the result after it:
  a command that never returns is in the log.
- Files: `~/X1-captures/<yyyy-MM-dd>/x1scan-apercu-<HHmmss>.txt` and `.raw`,
  created exclusively (never replacing a file). A failed write does not
  stop the run; the alert then says the log is incomplete. They hold the
  serial number: outside the repository.

## Film holders (step 3)

Recorded on 2026-11-14.

- **Holder code lines in the repository** (user's decisions, 2026-11-18):
  an exception to "no raw image files" (CLAUDE.md rule 2), limited to
  **8 holder code lines**, one-line reads that show a holder's code on its
  leading edge (`tests/fixtures/holders/holder-code-lines.json`, raw
  pixels, no serial number): the seven of the morning capture, and the 6×7
  line of the afternoon (`essai-K`, full CCD width), added by the user's
  second decision of the same day. No other image data; the calibration
  line of the first session of the morning run, which shows no code, is
  not kept.
- **Holder labels** (user's decision, 2026-11-18): `holders.json` uses the
  titles of Hasselblad's holder sheet ("Flextight Holders", v4 2019; facts
  only, the sheet is not in the repository), with openings in mm and in
  inches as the sheet gives them, the patent printed on Hasselblad holders
  and the code read. Where the sheet contradicts itself (50200407,
  50200410), the title is kept and the other variant is in `note`.

- The default list is a versioned data file,
  `app/X1ScanCore/Sources/X1ScanCore/Resources/holders.json`: reference,
  format, opening in mm, number of frames, series, from Hasselblad's holder
  compatibility table. **Factual data only**: no Hasselblad image or
  document in the repository.
- Default formats are shown with the decimal separator of the user's
  number format (locale: "6×4,5" with French formats); the data file keeps
  a dot.
- Deleting a custom holder asks for confirmation.
- Settings > Holders: tick the holders owned; only those appear in the
  panel's menu, after "Not specified" (always first). The three holders
  supplied with the X1/X5 are ticked at first. Custom holders (name,
  optional reference, opening, frames) can be added, edited and deleted;
  default holders can only be unticked (hidden), never deleted or changed.
- The panel saves the chosen holder (`ScanSettings.holderID`); a holder no
  longer ticked shows as "Not specified". Nothing is sent to the scanner.
  The free-text holder of the first step 3 build is converted once into a
  custom holder.

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
100), 0x23 (12, 60), 0x24 (32, scans only, since 2026-11-17), 0x25 (24),
0x26 (56), 0x27 (20), 0x29 (14). The CDBs of
INQUIRY, LOG SENSE, MODE SENSE, 0xD3, 0xDF and 0xEE come from the FlexColor
capture; those of TEST UNIT READY and REQUEST SENSE from `tools/x1probe`, to
which a real X1 answered. A test checks that every read of the read-only
list in `tests/fixtures/preview-sequence.json` and
`tests/fixtures/scan-sequence-2000ppi.json` passes.

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
  **256** since 2026-11-17 (100 before; "Position tolerance" below). Until 2026-11-16, two captures differed by 64 on the first
  measurement (25 803 / 25 867) and the others were identical; on
  2026-11-17, a warm capture differed by 128 on that same read (25 739) and
  a cold one by 192 on two checked reads (below).
  Since 2026-11-16 (user's rule, after the first real test) the check
  applies only to page 0x20 reads made after a window that requests a
  position (SET WINDOW offset 50 not 0); the reads before it are logged and
  parsed, not compared. In FlexColor's preview that leaves two reads
  unchecked. The first, after session start, shows the state left by
  earlier use (8 203 after power-on, where the capture had 6 155). The
  second, after the first calibration windows (target 0), is probably a
  measurement (protocol.md §5): it is the one that differed by 64, then
  128, between captures, left unchecked by choice. Until 2026-11-16 the threshold of
  100 rested on no checked read that varied. The captures of 2026-11-17
  contradict that: in a new cold run (A1) two checked reads differed by 192
  from the cold capture (14 027 / 14 219), so the runner would have stopped
  that preview before SCAN (safe, but the threshold is to be decided again;
  protocol.md §11). Between that read and the first checked one, only the
  captured window with target 25 000 is sent. Everything else in the guard
  and the runner is unchanged.
- **Waits on 0xDF.** We poll 0xDF after exactly the commands where FlexColor
  polled it, until the state FlexColor last saw there: `00 00`, or `00 01`
  after SCAN. Only the global list of busy states is accepted in every
  wait: `08 01`, `08 40` (2026-11-12), `08 02`, `08 03`, `08 06`,
  `08 07` (right after power-on, 2026-11-16). Any other state stops the
  run, except `08 80` in one wait and `08 00` (below). The wait after an emergency stop (DB) uses the same set (plus `08 00`
  since 2026-11-18, below), although
  both captures show only `08 01` there: this changes nothing that is sent
  (only 0xDF after DB, the guard allows nothing else), only how long the
  app keeps polling (up to 120 s) before reporting "not ready".
  **`08 00` after the final DB** (user's decision, 2026-11-18): our real
  cold preview of that day saw `08 00` right after its final DB, where the
  captures show `08 01` (protocol.md §7). `08 00` is now accepted as busy
  in the wait after the final DB of the preview or of the scan, and in the
  wait after the emergency DB, even as the first state read; elsewhere,
  including after the scan's middle DB, only right after another accepted
  `08 xx` (next point). Nothing new is sent: only 0xDF until `00 00`.
  **`08 00` right after an accepted `08 xx`** (user's decision, 2026-11-18,
  after a second stop on `08 00`, cold preview step 81: `08 07`, `08 03`,
  `08 01` ×6, `08 00`): in every 0xDF wait, preview and scan, `08 00` is
  accepted as busy when the state read just before in that wait was an
  accepted `08 xx` other than `08 00`. In any other wait than the one
  after a final or emergency DB, `08 00` read first, or right after
  another `08 00` (two in a row were never seen; after SCAN this sends the
  emergency DB at once rather than after up to 120 s), still stops the
  run. `08 80` in the scan and `08 04` stay refused. Only 0xDF reads, same time limit (120 s). The meaning of
  the bytes is a **[hypothesis]** (protocol.md §7).
  **States of the scan captures** (user's decision, 2026-11-18): a state
  seen only in a scan capture is accepted only in the wait where it
  appears there, not added to the global list. `08 80`: in the wait after
  the first `f0 00 01 01 01 01` of the warm preview (seen before the
  2 000 ppi scan). Not in the cold preview, and not in the 2 000 ppi
  scan: only the 3 200 ppi scan capture shows it at that step (seq 809),
  not the 2 000 ppi one. `08 04` (1 000 ppi scan, a step our
  2 000 ppi scan does not have): nowhere. The 2 000 ppi scan session itself
  shows only states of the global list (protocol.md §7).
- **Stop at the first unexpected response**:
  - a status other than GOOD;
  - a wrong number of bytes;
  - an INQUIRY other than `Imacon` / `Flextight X1`;
  - a SCAN response other than `00 00`;
  - a measured position out of tolerance;
  - a line counter going back in the image phase, between the image
    SCAN (`1b 00 00 01 01 00`) and the next DB, in the preview and the
    scan. Outside that phase it is not checked (user's decision,
    2026-11-18: during a real scan's white and black references it went
    from 11 to 10; nothing we send depends on it; protocol.md §5);
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

## Real X1: cold or warm sequence, chosen by page 0x20 (2026-11-17)

Replaces the cold-only rule of 2026-11-16 (next section), after the
captures of 2026-11-17 (protocol.md §11). User's decisions.

- **Choice.** The warm and cold sequences are the same up to and including
  the first page 0x20 read after `CF 00 01 80`, once the cold capture's page
  0x28 read is left out (a second cold capture has none). The runner sends
  that common part, then reads bytes 19-24:
  - 2 048 × 3 (power-on values): the cold sequence;
  - values left by earlier use, each channel within the range seen at
    that read in every session that did not start cold (2026-11-12 and
    2026-11-17: 1 911-1 945 / 1 845-1 856 / 1 883-1 895), widened by 64
    (1 847-2 009 / 1 781-1 920 / 1 819-1 959): the warm sequence. After such
    values FlexColor sent the warm capture's sequence in five sessions (W,
    B, the previews of the 1 000 and 3 200 ppi runs); in two it sent
    something else (A2, a second preview in the same FlexColor session;
    the preview of the 2 000 ppi run, below);
  - anything else: stop (`unrecognisedStartState`), before any window,
    mode, exposure, image read or SCAN.
  That FlexColor decides from this read is a **[hypothesis]** consistent
  with every capture; both sequences are FlexColor's own.
- **Guard.** Built from both captures (`preview-sequence-cold.json`
  without its page 0x28 read, and `preview-sequence.json`): each command
  must be the next one of a captured sequence; where they differ, the first
  command sent decides which one is followed. The runner's choice and the
  guard are independent: the guard only lets through what one capture did.
- **Page 0x28** is no longer sent.
- **Page 0x24** (32 bytes, read once per scan by FlexColor) joins
  `CommandPolicy.readOnly`: a MODE SENSE like the others, captured three
  times with the same response.
- **Position tolerance: 256** (user's decision). The check is meant for
  gross anomalies (differences in the thousands). The largest difference
  seen on a checked read is 192, in one capture right after power-on (A1,
  two reads); every other checked read of every capture matched exactly;
  differences come in steps of 64. 256 leaves one step of margin without
  losing what the check is for. Every page 0x20 read whose position differs
  from the expected one (the captured one; in a scan, after the substituted
  window, the position sent), checked or not, is written to the run's log
  (expected, measured, difference) so that the tolerance can be revised
  with later sessions. FlexColor captures of 2026-11-18: before the window
  with target 25 000, +64, +128, +64, +64 against the captured 25 867,
  all on the same side, 128 below the limit at most. The cold preview of
  that day read 25 675 where our cold sequence expects 14 219, but it had
  already sent other windows (ratio 32 000 000 and offsets 54 / 58 =
  454 612 / 856 631 instead of 16 000 000 and 354 583 / 576 354) before
  that read (protocol.md §12): our cold sequence sends those of
  2026-11-16, with which that read gave 14 027 to 14 219 in every capture
  and every real preview up to 2026-11-18. Note of 2026-11-25 (journal):
  two real cold previews read 13 579 (the runner stopped there, before
  SCAN) and 13 963 (accepted), with the original calibration; the
  tolerance is unchanged until three cold starts are captured with
  FlexColor (user's decision, 2026-11-25). **Only the cold
  sequence of 2026-11-16** (user's decision, 2026-11-18): no second cold
  variant.
- **Option A: the read before the window with target 25 000** (user's
  decision). In the warm sequence, the page 0x20 read right after the
  first calibration windows (target 0) is now always checked, with the
  same tolerance (256), although no window has requested a position yet.
  Reason: in the preview of the 2 000 ppi run it gave 24 523 (25 739-25 867
  in the five other warm sessions of 2026-11-12/17; 25 931, 25 995, 25 931,
  25 931 in four of 2026-11-18: +64 to +128, under the tolerance) and FlexColor then did not send the
  window with target 25 000 (protocol.md §11). Beyond the tolerance the
  preview stops there (`unexpectedCarriagePosition`) and nothing else is
  sent; the message (`carriage-position` since lot A, "Lot A: error
  catalogue") says the carriage was not where expected, that the preview
  stopped before positioning it, and to switch the X1 off and on before
  starting the preview again. The log has the read, expected and
  difference. As after any other stop (the session and modes may still be
  active), the next preview asks for the switched-off-and-on box: no
  exception (user's decision).
  FlexColor's other path (no window with target 25 000) is not reproduced:
  one capture only.
- **Confirmation.** The fourth box ("the X1 was switched off and on")
  is asked only after a real preview that did not complete (stop, anomaly,
  quit or crash; a flag kept between launches, cleared by a run whose
  scanner side completed, and put back as it was when the scanner could
  not be opened). Limit: the flag belongs to one Mac (its preferences). A
  real preview interrupted on another Mac, or a FlexColor run interrupted
  on the reference Mac, is not known: after such a run, switch the X1 off
  and on before the next preview (test-session.md, part E). Reason: a cold run stopped
  during calibration still shows 2 048 × 3, so the choice would start the
  cold sequence again on a scanner left half calibrated, which no capture
  shows. After a complete preview, page 0x20 is enough.

## Real X1: scan (2026-11-17, step 2; simulator only so far)

User's decisions; nothing has been sent to the real X1.

- **What is sent.** FlexColor's scan session of the 2 000 ppi capture
  (`tests/fixtures/scan-sequence-2000ppi.json`, seq 834-1760;
  `ScanScript.flexColor4813Scan2000ppi`): same holder, same frame
  (609 × 614 pixels), same resolution. Every value is the captured one,
  except one.
- **The one substitution.** The window right before `1b 00 08 06 01 00`
  (the 400-line step, protocol.md §12) carries at offset 50 the position
  just read on page 0x20, as FlexColor did (16 651 in the capture). The
  runner sends it only if it is within the allowed range; otherwise it
  stops before that window. Until 2026-11-19 the range was the captured
  16 651 ± 256 (16 395-16 907), from that one capture. **Since 2026-11-19
  (user's decision)**: 16 651, 16 907 and 16 971 ± 256, the positions
  FlexColor measured there in the 2 000 ppi scans of
  `scan-sequence-2000ppi.json` (2026-11-17) and
  `scan-sequence-2000ppi-twice.json` (essai-F, 2026-11-18, another frame):
  16 395 to 17 227 (`ScanScript.focusPositionRange`). essai-I's 16 331 (a
  1.0 × 3.0 cm frame, 2026-11-18) is outside, by the user's choice. Reason: a real scan stopped on
  2026-11-19 at 16 971, a position FlexColor itself had measured. The value
  substituted is bounded the same way (it is the position read); the check
  after the window is unchanged (± 256 around the position sent). The
  guard (`CapturedSequenceGuard.scan`) accepts that window with another
  value in the same range only, at that place only, every other byte being
  the captured one; anything else is refused. Rule 4 of CLAUDE.md says so.
- **Two position checks around that window** (user's decision):
  1. *Before it*: the position read just before must be within the allowed
     range (16 395 to 17 227 since 2026-11-19), or nothing more is sent (the
     window is not sent; anomaly `positionOutOfRange`).
  2. *After it*: every later page 0x20 read of the session is compared with
     the position **sent** in that window, not with 16 651: the carriage
     must have reached the target it was given, within 256. Otherwise the
     scan stops (`DB` if after the step's SCAN).
  The log notes every read that differs from what is expected (expected,
  measured, difference).
- **Observed in the three scans** (2026-11-17), page 0x20 position:

  | Scan | Read before the window | Sent in the window | Reads after it |
  |---|---|---|---|
  | 2 000 ppi | 16 651 | 16 651 | 16 651 (54 reads) |
  | 1 000 ppi | 8 081 | 8 081 | 7 998 (29 reads), -83 from the target |
  | 3 200 ppi | 24 971 (25 547 before the two windows with target 25 000) | 24 971 | 24 971 (102 reads) |

  The target sent was always the position read just before; after it the
  position stayed constant for the whole session, at the target or 83
  below it. **[confirmed]**
- **Start state.** The session must start warm: no scan right after
  power-on was captured. Its first page 0x20 read must show values left by
  earlier use (`startStateMismatch` otherwise); before that read only the
  session start and reads are sent.
- **0xDF `00 06`.** The wait after `1b 00 08 06 01 00` ends on `00 06`,
  where FlexColor started its one-line reads. It is a wait target of the
  scan script only, never a busy state, so a preview never accepts it.
- **Page 0x24** is read (read-only list since the same day).
- **Stop.** `1b 00 08 06 01 00` counts as SCAN for the stop rules: after
  it, an anomaly sends `DB` then waits for `00 00`.
- **Tested on the simulator**: the script is the captured session command
  for command, with FlexColor's waits; the run goes through the guard;
  the decoded image matches the synthetic film (609 × 614); positions
  within the tolerance are substituted and accepted, beyond it nothing more
  is sent; a scanner just switched on is refused; a fault during the
  400-line step sends the stop.
- **In the app** (user's decisions, interface validated before it was
  written):
  - **Scan button**: on the virtual X1, available whenever nothing runs
    and an export folder is chosen (replay of the scan session). On the real X1, only with the hidden
    setting `EnableRealScan` (separate from `EnableRealPreview`), nothing
    running, an export folder, and a real preview whose scanner side
    completed just before, with no real run since: **a new complete preview
    before every real scan**, as in the captures (each is one preview, then
    one scan; scan after scan was never captured). Otherwise disabled, with
    the reason in its tooltip.
  - **Confirmation** before every real scan, two boxes (short titles, one
    line each; the holder reference is in the text above them): same holder
    as the capture (6×7, 50200403), film in place, nothing moved since the
    preview; the capture's frame and resolution (609 × 614 px at
    2 000 ppi) are used, not the panel's. No "FlexColor is closed" box:
    FlexColor does not run on Tahoe, and another client holding the scanner
    already gives a clear error. Start is enabled only when both are ticked;
    Return does not start it.
  - **During the scan**: the bottom bar shows the phase derived from the
    command being sent, not from a fixed order (the white/black reference
    read comes before or after the 400-line step depending on the
    resolution):
    calibration, "Focusing: n of 400 lines", "White and black
    references", "Image: n of 1 064 lines" (priming lines included).
    "Focusing" names the 400-line step after its **[hypothesis]**
    (protocol.md §12). Stop as for the preview. The image is shown at
    the end only, once decoded.
  - **File**: a 16-bit RGB TIFF, linear, without profile, 2 000 ppi in its
    resolution tags, saved in the export folder with the export name
    template. Nothing else goes into it: no description, no serial number.
    The values are not FlexColor's (it applies its own curve and profile);
    the geometry is.
  - **Log**: `x1scan-scan-<HHmmss>.txt` and `.raw` in the capture folder
    (outside the repository), cap3 format, readable by
    `tools/decode/decode_scan.py`: header, every command and response, the
    positions that differ from what is expected, the result and the file
    saved. Only this log holds the serial number (page 0x26 response).
  - A scan that does not complete counts as an interrupted real run: the
    next preview asks for the power cycle. After any real scan, complete or
    not, Scan stays disabled until a new complete preview.
  - The confirmation names the substituted value for what it is: the
    carriage position of the 400-line step, read just before (within the
    tolerance of the capture).

## Real X1: the sequence right after power-on only (2026-11-16)

Superseded on 2026-11-17 by the section above (cold or warm, chosen by
page 0x20); kept for the reasoning.

- The first real tests stopped at the first page 0x20 read (position 8 203
  against 6 155), then at a wait on 0xDF (`08 07`). FlexColor's capture
  right after power-on showed why: from a cold start it sends another
  sequence (protocol.md §11) and goes through other busy states.
- **On the real X1 only that cold sequence is sent** (user's decision,
  option A): `PreviewScript.flexColor4813Cold`, and a guard built from
  `tests/fixtures/preview-sequence-cold.json`. The virtual X1 still replays
  the warm capture.
- **Power-on check.** The first page 0x20 read must give 2 048 × 3 in bytes
  19-24, or the preview stops (`PreviewAnomaly.notJustSwitchedOn`) and the
  alert says to switch the X1 off and on again. Before that read only reads,
  the startup `D2` and the session start `CF 00 01 80` have been sent, as in
  both captures: no window, mode, exposure, image read or SCAN. Whether D2
  and CF move anything is unknown (CLAUDE.md rule 4 counts them as
  state-changing).
- **What the check does not cover.** In the cold capture bytes 19-24 stay at
  2 048 × 3 until the calibration (still at seq 285, 1 928 / 1 843 / 1 882
  at seq 325). A cold run stopped before that point (anomaly, Stop) leaves
  2 048 × 3 with a session open, modes set and the carriage possibly moved:
  a second run without switching the X1 off would pass the check. That 2 048
  × 3 means "just switched on" is a **[hypothesis]**; the protection then
  rests on the advice of every alert (switch off and on again) and on a
  fourth check in the confirmation: "the X1 was switched off and on since
  the last real preview" (user's decision).
- The warm sequence could not be chosen at that read: the two sequences
  already differ before it (the page 0x28 read, cold only). Using both would
  have meant sending a command FlexColor did not send in one of them. Kept
  for later: a warm capture right after a cold one, without a restart, to
  understand what triggers the page 0x28 read. The rule then planned: 2 048
  × 3 → cold; all three between 1 750 and 2 050 and not all 2 048 → warm;
  anything else → stop.
- The page 0x28 read belongs to the captured cold sequence; it is **not**
  added to `CommandPolicy.readOnly` (the inspector does not read it).
- Fixture: converted with `tools/capture/cap3_to_fixture.py` (serial
  number anonymised, no image data). cap3.py prints at most 64 bytes per
  response: the INQUIRY (96 bytes) and page 0x21 (100 bytes) responses
  were completed from the warm fixture, whose complete responses come from
  `tools/x1probe`; their first 64 bytes are identical (marked
  `completed_from`). They only feed the virtual X1 and the identity check.


## Application icon (2026-11-18)

User's decision: the app icon belongs to the icon's copyright holder
(named in `LICENSE-ICON`) and is **not** under the MIT licence
(`LICENSE-ICON`, README's licence section, About; CLAUDE.md rule 3).
`LICENSE` stays the standard MIT text (user's decision, 2026-11-18): with a
line excluding the icon, GitHub no longer recognised it as MIT ("Other").

- **Name of the copyright holder** (user's decision, 2026-11-18): an
  exception to "no client or studio names" (CLAUDE.md rule 2), only in
  `LICENSE` (its copyright line only, `Copyright (c) 2026 <holder>`, part
  of the standard MIT text; user's decision, 2026-11-18: the same holder
  as in the About panel, replacing the author's name and "the X1-Scan-ARM
  contributors"), `LICENSE-ICON`, the licence section of `README.md`, the app's
  copyright line (`INFOPLIST_KEY_NSHumanReadableCopyright` in
  `project.pbxproj`, `InfoPlist.xcstrings`; About) and the files of
  `app/X1Scan/Icon/`. Everywhere else: "the icon's copyright holder".
- **Terms** (`LICENSE-ICON`): use and redistribution unmodified, only in
  builds of X1 Scan made from this repository (forks included if they keep
  the name X1 Scan); a derivative distributed under another name must
  replace the icon; no other use without written permission.
- The licences are copied into the app (`LICENSE`, `LICENSE-ICON`) and
  shown in the About panel's credits, under "Icon licence (not MIT)" (first:
  it is short) and "Code licence (MIT)".
- The CI builds the app with Xcode 26.5, pinned (the `.icon` needs Xcode
  26), and checks that the built app has the icon and both licences.

Sources in
`app/X1Scan/Icon/`: two SVG layers of 1024 × 1024 (background gradient
#31435A → #0F161F, opaque; "X1" in white, outlined), split from the
user's single Illustrator file, and `AppIcon.icon`, the Icon Composer
document (Xcode 26 format): the gradient as the document's background
fill, the "X1" layer alone in one group, Liquid Glass defaults, no shadow
or highlight added by hand. The target uses it through
`ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`; the SVG layers are
excluded from the target (only the `.icon` is compiled). The source
layers in `app/X1Scan/Icon/` are the reference; `AppIcon.icon/Assets/`
holds an identical copy of the "X1" layer and the `.icon`'s fill repeats
the background colours: change both together. The About panel's
copyright line (English and French, `InfoPlist.xcstrings`) names both
licences.

- **Option D** (user's decision, 2026-11-18, after comparing four
  renders): the dark appearance keeps the blue gradient (a fill
  specialization for `dark` equal to the default fill, instead of Icon
  Composer's neutral dark), and the "X1" outline has a 14-unit white
  stroke (round joins) in the source layer and in the `.icon`, for the 16
  and 32 px sizes. The four renders stay outside the repository.

## Holder detection (2026-11-19, plan; not implemented yet)

- The cold and warm sequences X1 Scan replays already read the holder
  code line at full CCD width (`28 00 01 00 01 01 00 bb e0 00`, seq 355 of
  `preview-sequence-cold.json`, seq 299 of `preview-sequence.json`). Detecting the holder
  needs no new command: X1 Scan decodes that line (`X1Image.HolderCode`)
  and looks the code up in `holders.json` (`code`).
- **Real X1, holder other than the 6×7** (user's decision, 2026-11-19):
  the run stops right after that read, with the message "Holder <format>
  detected; only the 6×7 is supported for now". Nothing else is sent. A
  line that cannot be decoded, or a code not in `holders.json`, stops the
  run the same way, with its own message (holder not recognised). What
  FlexColor itself sends after that read to end cleanly has never been
  captured: the X1 is left as it is after that read. **[hypothesis]**
  that this is harmless, to be watched on the first such stop.
- Later, other holders: after the code read, go on with that holder's
  captured preview, only from a capture whose commands up to the code read
  are identical to our sequence (the captures of 2026-11-18 of the 6×6 /
  6×4.5, the 6×6×2 and twice the 24×36×4 are; docs/test-
  session.md part I adds the others). Holders with the two low-resolution
  passes (6×6 / 6×4.5, 6×6×2, 24×36) may not be replayable byte for byte if
  the second pass depends on the original. Cold start: 6×7 only.
- Simulator: the other holders' code lines are generated in the tests from
  their bar pattern; no other raw code line enters the repository.

## Offset 62 of the 400-line window (2026-11-19)

**Decided by the user (2026-11-19)**: option A below (the value from the
calculator's window, recomputable by the guard); 32 units accepted as the
validation criterion on captured frames, at 600 ppi and above; below 600
ppi, no free frame. Implemented on 2026-11-19 in the simulator only
(see "Window calculator" below), with the rounding to the nearest unit. The guards below (1 to 5) were proposed with it and are
to be confirmed with the implementation. A window calculator goes beyond
"byte for byte" (CLAUDE.md rule 4): rule 4 must be changed, with the
user's approval, before anything it computes is sent to the real X1.

The proposal as it was made:

Parts H and K (protocol.md §9) show that FlexColor computes offset 62
from its own frame coordinates [hypothesis, strongly supported], which
are not in the window: no formula of the window's values gives
FlexColor's value byte for byte. For a future window calculator (frames
that FlexColor never scanned), for the user's decision:

- **Where the value comes from: two options.**
  - A. From the calculator's window: 15 500 + 28 800 × (offset 18 +
    (offset 26 − 2 × gap − 2) ÷ 2) ÷ (ratio ÷ 10 000), rounded (the rounding
    to be fixed with the implementation, the same in the calculator and the
    guard). A guard can
    recompute it from the window alone. On the 37 focus windows captured,
    it is within −6 to +24 of FlexColor's value (mostly above).
  - B. From the calculator's own frame (its exact middle along the drum,
    15 500 + 28 800 per inch), as FlexColor seems to do. Closer to
    FlexColor's method, but a guard cannot recompute it from the window
    alone; it would check it against the window's image lines (below).
- **32 units: a validation criterion, not a check made during a scan.**
  The difference with what FlexColor would send for the same frame cannot
  be known for a frame FlexColor never scanned. So 32 applies when the
  calculator is given the frames of the captured scans: its offset 62 must
  then be within 32 of FlexColor's value (simulator test, every captured
  scan). 32 units = 1/900 in = 0.028 mm along the drum (one unit ≈
  0.88 µm, [hypothesis]); largest difference observed 24 (0.021 mm),
  margin 8 (7 µm), that margin resting on two 600 ppi windows only. Along
  the drum the line pitch is ratio ÷ 10 000: 0.028 mm is about 1.8 lines
  at 1 000 ppi and 5.9 lines at 3 200 ppi. The 400-line step reads the film
  at that position while the focus is swept: such a shift within a frame
  of a millimetre or more should not change the focus found. **[hypothesis]**
- **Resolutions.** Part K suggests an output-pixel effect of about
  28 800 ÷ resolution units (48 at 600 ppi, 96 at 300). So the 32 units are
  proposed for 600 ppi and above only (the resolutions captured); below
  that, either no calculator, or a tolerance of max(32, 28 800 ÷
  resolution) **[hypothesis]**, to be checked by a capture first.
- **Guards during a scan.**
  1. Only offset 62 (4 bytes, LE) of the 400-line window (ratio
     21 674 665, the window right before `1b 00 08 06 01 00`); every other
     byte follows the confirmed rules or the capture.
  2. Option A: the value sent is exactly the formula of the session's
     image window. Options A and B: it lies between the drum positions of
     the first and the last image line of that window (offset 18 and
     offset 18 + offset 26, converted at 28 800 per inch from 15 500),
     within a few units.
  3. Before any free frame: the validation above, on every captured scan.
  4. Simulator only until the user approves; then the first real runs
     with frames identical to captured ones (the whole windows compared),
     a confirmation before each run, every command logged.
  5. Any other field the calculator computes (offsets 14, 18, 22, 26,
     54 / 58 and the rest) needs its own decision.

## Window calculator (2026-11-19, simulator only)

**User's decisions (2026-11-19).** `X1Kit/Sources/X1Geometry/
ScanWindowCalculator.swift`: a frame on the film (inches) and a
resolution give the image window (before the 400-line step) and the
400-line window. Target `X1Geometry` has no dependency and is not in the
X1Kit product: nothing in the app, the transport, the guards or the scan
script can reach it. Later, only X1Preview may depend on it, in that
direction only, after CLAUDE.md rule 4 is changed.

- **Limits**: 6×7 holder only; the menu of resolutions of "Window
  calculator v1" below (first 600 to 3 200 ppi); a frame that
  rounds to no pixel, leaves the CCD (offset 14 + width > 7 992 ÷
  binning) or starts before line 0 is refused. The length of the opening
  along the drum is not known: no check there beyond 16 bits.
- **Constants**: all in one named set, `WindowCalibration.origin20261119`
  ("origine-2026-11-19"): *f* = 1.000, *M* = 3 200, *x* = −0.129 in
  (the frame origin from CCD pixel 3 996), 1.644 in (the frame origin
  from line 0 along the drum: the centre of essai-I's "centred" frame,
  1.6427 to 1.6442 in, protocol.md §9; centred by eye, a convention), the lens model of 54 / 58, +10 000,
  ratio 21 674 665, 15 500 and 28 800 per inch. A new set is added after
  a recalibration (docs/test-session.md J3); sets are not edited.
- **Rules** (protocol.md §9). [confirmed] on the captured scans, exact:
  offsets 10, 26 (against the TIFF height), bytes 48, 49, and offsets 50 =
  0 and 62 = 15 500 of the image window. Offsets 54 / 58: within 1 (54 one
  too high at *O* = 2 000, 2 880, 3 000; family 1). Offsets 14, 18, 22:
  reproduced by construction in the round trip (family 1 takes the frame
  from them), [hypothesis] as rules; in prediction of the same frame at
  other resolutions they differ (14 by up to 5 pixels, 18 and 22 by 1:
  family 2). All the rules are [hypothesis] for other frames. Offset 10 = ⌊resolution × *f* × 50 000 /
  3⌋; byte 48 = 1; byte 49 = min(4, ⌊*M* ÷ resolution⌋); offset 14 =
  3 996 ÷ binning + (*x* + left) × resolution, offset 22 = width ×
  resolution, offset 18 = (1.644 + top) × ratio ÷ 10 000, TIFF height =
  height × resolution, each rounded to the nearest; offset 26 = ⌊TIFF height ×
  5/3⌋ + 2 × gap + 2; offsets 54 / 58 = the lens model at *O*, rounded;
  image window offsets 50 = 0, 62 = 15 500. 400-line window: ratio
  21 674 665, offsets 14 / 22 of the image window, 18 = 0, 26 = 401, 54 /
  58 + 10 000, offset 62 by option A (`focusLinePosition(imageWindow:)`,
  rounded to the nearest; the one place of that rounding). A future check
  of offset 62 during a scan would call that function from X1Preview,
  before the transport: X1Transport does not depend on X1Geometry.
- **Not computed** (read or replayed): offset 50 of the 400-line window
  (left at 0), FlexColor's focus correction of 54 / 58 in the image window
  sent after the 400-line step, the binned start window, the reference
  windows and their order.
- **Field decisions (guard 5), for the simulator**: the exact fields (10,
  48, 49, 50, 62 of the image window, 26) are accepted, and the 400-line
  window's constants, being the same in all 31 captured scans
  (`focusWindowConstants`). The fields within 1 (18, 22, base 54 / 58):
  **proposed**, the user decides after part J (user's decision of
  2026-11-19). Offset 14 is within 1 only in the round trip; predicted
  across resolutions it differs by up to 5 pixels (family 2). **User's
  decision (2026-11-19): a tolerance of ±5 pixels in prediction,
  simulator only, provided the frame stays in the CCD; provisional, to be
  reviewed after part J.** As implemented: family 2 checks every offset 14
  difference against ±5 (`columnPredictionTolerance`) and that each
  predicted window, moved by 5 pixels either way, stays within the CCD
  (offset 14 ≥ 0 and offset 14 + offset 22 ≤ 7 992 ÷ binning); the
  calculator itself still refuses only a window outside the CCD. 600 ppi:
  decided, "Window calculator v1" below. For
  the real X1, no decision yet: before rule 4 is changed, a table of each
  field (rule, unit, largest difference observed, in mm, proposal) goes
  to the user.
- **Tests** (`X1Kit/Tests/X1GeometryTests`; the captures do not hold
  FlexColor's frame, only its description):
  - family 1, consistency and non-regression, not a validation: each of
    the 28 6×7 scans with the frame taken from its own window (a round
    trip; offsets 14, 18, 22, 26 equal by construction). Differences, as
    they are: offset 54 is 1 too high at *O* = 2 000, 2 880 and 3 000 (14
    scans, both windows). Offset 62 (option A) is within −6 to +24 of
    FlexColor's.
  - family 2, the prediction: the frame of one scan predicts the same
    untouched frame at other resolutions (essai-I 7 → 2-6, essai-L 2 →
    3-4, essai-N 2 → 3-6 and 8 → 9). Differences: offset 14 up to 5 pixels
    (3 200 → 2 000 ppi, binning 1), offsets 18 and 22 by 1, and **offset
    62 beyond the 32 units at 600 ppi: +48, +43, +53** (FlexColor's value
    is about one 600 ppi output pixel lower there, protocol.md §9, part
    K). **The decided criterion (32 units at 600 ppi and above) is not
    met at 600 ppi in prediction.** Decided by the user: 600 ppi is left
    out of the menu, the criterion stays 32 units ("Window calculator
    v1" below).
  - the three scans with other holders are refused.
- **Before any real use**: a validation on the real X1 (a target; the
  frame asked against the frame obtained), after the change of rule 4.

## Window calculator v1: menu, focus, guard (2026-11-19, simulator only)

**User's decisions (2026-11-19)**, on top of "Window calculator" above.
Nothing computed is sent to the real X1: CLAUDE.md rule 4 is unchanged,
to be decided after part J.

- **Holder**: the 6×7 only. The other holders stay on captured replays.
- **Menu of resolutions**: 1 000, 1 500, 2 000, 3 000, 3 200 ppi
  (`WindowCalibration.resolutions`; any other value refused). All were
  captured with the 6×7, with their binning, *O* and order of the
  references (1 000 and 1 500: references first; 2 000: after; 3 000 and
  3 200: first; protocol.md §9). 600 ppi was in the brief but is left out:
  offset 62 predicted there is 43 to 53 units above FlexColor's (family
  2), beyond the 32 units, which stay the criterion (docs/hypotheses.md).
  Nothing below 600 ppi; other resolutions only after a capture.
- **Focus: our own measure on the 400 lines, plus a manual correction.**
  Offsets 54 / 58 of the image window sent after the 400-line step =
  those of the 400-line window (base + 10 000) − 50 × (*i* +
  correction): *i* the line our measure finds sharpest, the correction in
  lines (1 line = 50 units, protocol.md §9 [hypothesis]), default 0
  (`ScanWindowCalculator.imageWindow(_:focus:sharpestLine:correction:)`).
  *i* + correction must be one of the 400 lines swept (0-399), otherwise
  refused. The value chosen, *i* and the correction go in the scan's log
  and, later, in the master file (step 2).
- **Our measure** (`X1Image.FocusSweep`, green channel flat-fielded with
  the calibration read of the scan resolution): three simple measures
  proposed, each a [hypothesis] (gradient energy, variance of the 1-D
  Laplacian, gradient energy over the squared mean level). Compared with
  FlexColor's *i* on the 36 captured scans with 400 lines
  (`FocusSweepReportTests`, data exported by `tools/decode/
  export_focus.py`, outside the repository): see the journal of
  2026-11-19. For each scan the report also gives each measure's score at
  FlexColor's line, in % of the highest score of our curve. **User's
  decision (2026-11-19): gradient energy is the provisional measure
  (`FocusSweep.provisionalMeasure`); no acceptance criterion yet, it will
  be set after the recalibration.**
- **Offset 50** of the 400-line window: the position read on page 0x20
  just before, as today (not computed).
- **Guard** (`X1Geometry.ComputedWindowGuard`, simulator only; not an
  extension of `CapturedSequenceGuard`, so that it stays in X1Geometry,
  which nothing in the app or the transport can reach): offset 62 of the
  400-line window recomputed from the image window by option A with the
  calculator's own function (exact, one rounding in one place), the
  400-line window's other fields (calibration constants, the image
  window's column, width, binning, 54 / 58 + 10 000), and the image
  window after the step: every field but 54 / 58 unchanged, 54 / 58 one of
  the 400 positions swept, the same line for both.
- **Not done in this step** (the user's choice, 2026-11-19): the start,
  calibration and reference windows and their order are not computed yet;
  step 2 (the app, simulator only) after the user's approval. The four
  suggestions still open from the review are left for step 2 (user's
  decision of 2026-11-19): a single entry point for the guard; distinct
  `FocusSweep` errors for the two widths; the sharpness report setting
  aside a badly exported folder instead of stopping; `FocusSweep` in
  CLAUDE.md.

## Lot 1: exposure indicator (2026-11-19, provisional thresholds)

User's brief of 2026-11-19 (lot 1, part D). The Exposure section of the
panel shows how much of the CCD's range the last preview uses. Read only:
nothing is sent to the scanner and nothing in the image changes.

- **What is measured** (`ExposureMeter`): the preview's raw samples
  (`PreviewImage.raw`, realigned, before the flat field), once the preview
  is complete. Clipped: pixels with at least one channel at or above the
  clipping level. Near the noise floor: pixels whose channels are all at
  or below the noise floor. Range used: from the darkest level (per-pixel
  minimum channel) to the brightest (per-pixel maximum), each at the
  0.1 % percentile so that isolated defects do not count, as a share of
  the span noise floor → clipping level.
- **Thresholds** (`ExposureThresholds.provisional`, the only place they
  are set): clipping level 64 000, noise floor 1 024, on the 16-bit raw
  scale (0 to 65 535); tails 0.1 %. **[hypothesis] Not measured**: round
  values near both ends of the scale, chosen so that the indicator could
  be built. To be replaced by measurements on the X1: dark frames (lamp
  off or an opaque holder) for the noise floor, an over-exposed frame
  (empty holder) for the clipping level; an empty holder reads up to
  about 58 000 (protocol.md §10), which suggests the clipping level may
  be lower than 64 000.
- **Display**: a gauge over the full raw scale (hatched: below the noise
  floor; green: the levels used; red: above the clipping level, solid
  from 0.1 % of clipped pixels, the precision of the text), the text
  "CCD range used NN % · N.N % clipped", and a checkbox that overlays the
  clipped pixels (red) and those near the noise floor (violet) on the
  preview, display only.
- **Advice**: planned (it will point to quality modes: several passes,
  HDR), hidden in lot 1 (`ExposureSection.showsAdvice`), because those
  modes do not exist yet.
- **Virtual X1** (user's request of 2026-11-20): its previews show the
  test pattern with a clipped patch (rows 200-299, columns 20-35 %) and a
  dense one (columns 65-80 %), `SyntheticFilm.exposurePatches`, so that
  the overlay can be tried; the range used then always reads 100 % there.
  Its scans keep the plain test pattern. Columns 0-4 of every preview are
  near the noise floor (protocol.md §10): the violet line at the left
  edge. User's decision (2026-11-20): leave them out of the measure in
  principle, but only once real captures (part J) show they are not
  image; nothing coded until then (hypotheses.md).

## Lot 1: layout and geometry (2026-11-19)

User's brief of 2026-11-19 and decisions on the plan. No colour processing,
and no command sent to the scanner: everything here acts on pixels already
received, on the display or on exported files.

- **Panel**: sections Original (film, holder, orientation), Scan
  (resolution, scale, input, output), Exposure, Histogram (folded at first
  launch), Output; a folded section shows a summary of its values. The
  Main / Advanced tabs are gone; they come back with corrections.
- **Recipe** (`Recipe`, JSON `"version": 1`, `<name>.x1recipe.json` next
  to the image): orientation (quarter turns clockwise after an optional
  horizontal mirror), fine angle (degrees, −45 to 45, steps of 0.1 in the
  recipe; lot 1b: the controls move by whole degrees, see below; positive
  clockwise on screen), crop frame normalised in the image after
  the quarter turns and before the fine angle (physical units: a preview
  pixel counts 3 in height), proportions, portrait, lock, constraint. The
  pixels are never turned in place: the frame and the angle can later be
  written as an instruction for a raw developer (pixels not turned) in the
  DNG of a later lot.
- **Files** (user's decision): the scan's automatic save writes the
  decoded scan as a TIFF, not turned or cropped (the master until the DNG;
  "raw" in the user's words, not the raw CCD samples before the flat
  field), with its recipe. Export (⇧⌘E) renders the recipe into the image
  shown and writes a new file with its recipe: for a saved scan,
  `<master>_v1.tif`, `_v2`…, the first name whose image and recipe are
  both free, never replacing the master; for a preview, the name template
  as before.
- **Rendering** (`RecipeRenderer`): quarter turns and mirror are exact
  permutations. A scan without a fine angle: the crop takes whole pixels
  (no resampling). With an angle, or for a preview (its 1 × 3 pixels,
  even without angle or frame: user's request of 2026-11-25, X1-12.tif
  was 1 038 × 75 px for a 6×6 frame): Lanczos-3, in floating point, onto
  square pixels the size of the source pixel's shorter side (user's
  decision: a preview gets 3 times more rows), then the crop. An
  incomplete preview (stopped or failed, even after its last row; a
  stopped scan has no image) is not exported: Export is disabled and its tooltip says "Incomplete preview:
  make a new preview" (user's decision of 2026-11-25, X1-12.tif came from
  a stopped preview). The bottom bar's size estimate
  is that of the file written. With the constraint on, the frame is kept
  inside the turned image, also when a recipe is read from a file.
- **The scanned area is not changed.** The X1 still scans FlexColor's
  captured window; the turned frame must fit in the area scanned. Enlarging
  the scan window to cover a turned frame waits for the window calculator
  to be validated by captures (TODO in `AppModel.refreshImage`).
  Meanwhile the frame is not applied to a scan (user's decision of
  2026-11-25, X1-14: its master is the captured area, about 0.77 cm
  square, whatever the frame): on a scan, `AppModel.appliedRecipe` has
  no frame and free proportions; the frame is neither drawn nor made
  there, Export applies the orientation and the angle only, the recipe
  beside the master is the one applied, and the Framing section says
  "Frame not applied: the scan covers a fixed area until the window
  calculator is connected". The proportions chosen stay in the recipe
  for the next preview.
- **Display**: the image layers turn with the recipe (layer transforms,
  never resampled pixels); the grid (thirds, fine, centre cross) and the
  crop frame are overlays, never scanned or exported. The frame drawn on a
  preview is dropped when another image (the scan) comes; the turns and
  the angle are kept.
- **The frame follows the image** (user's decision, step F): a quarter
  turn turns the frame exactly (normalised coordinates) and exchanges a
  named or custom ratio (6×7 becomes 7×6; the image's own proportions turn
  with it); a mirror mirrors the frame and changes the sign of the fine angle; the
  frame then covers the same source pixels.
- **Proportions** (user's decision): width × height as named (6×7: 6 wide,
  7 high), X exchanges them; a ratio chosen in the menu (Original
  included) takes the direction of the frame, or without a frame of the
  image (an upright frame stays upright); a custom ratio keeps the width
  and height typed, whatever the frame's direction, and is exchanged by a
  quarter turn like a named ratio (13×18 becomes 18×13; user's decision of
  2026-11-20).
- **Handles** (user's decision of 2026-11-20): a corner dragged keeps the
  opposite corner in place and stays on its side (never flips over); it
  stops at the image's edge (the turned image with the constraint on, the
  image itself otherwise) and at a smallest side of 24 screen points, or
  less where the room from the fixed corner is smaller. Free proportions:
  the side that reaches an edge stops, the other goes on along it. A new
  frame starts after a drag of 5 points and stops at the edge the same
  way (`CropGeometry.resized`).
- **Crop mode** (Crop or Straightening Rule tool; user's decisions of
  2026-11-20, all confirmed by the user the same day): Done and Return
  leave it with its changes, back to the tool used before it (hand or
  zoom); choosing another tool also keeps the changes. Esc puts back the
  whole recipe as it was when the mode was entered (frame, angle,
  proportions, lock, constraint, turns and mirror), unless a preview or
  scan is running: then Esc stops it first, whatever the tool, as the
  Stop button and the confirmations promise; while the stop is under way
  Esc does nothing. A new image area (the scan after the preview) drops
  the frame Esc would put back. Reset (an icon next to Done; replaced in
  lot 1b, see "Lot 1b" below: always shown, the orientation reset too, ⌘Z
  undoes it): the whole image, free proportions and no angle; the turns,
  mirror, lock and constraint are kept, and Esc still goes back to the
  state on entering the mode. Key X exchanges the frame's width and height as soon as the
  mode is on, wherever the keyboard focus is in the main window, except
  while text is typed in a field or a sheet is open; held down, it acts
  once.
- **Straightening rule**: the line's direction folded into (−90°, 90°];
  within 45° of horizontal it is made horizontal, otherwise vertical; the
  angle is added to the current one.
- **Not in this lot**: Auto (edges) is shown disabled; corrections, film
  types, presets, DNG, ICC profiles, quality modes are left out.

## Lot 1b: panel tabs, Information area, tool column (2026-11-20)

User's brief of 2026-11-20 and decisions on the plan. A reorganisation of
the interface only: nothing sent to the scanner changes.

- **Tabs**: the panel is, top to bottom, a tab bar (Prepare, Scan,
  Output; ⌥⌘1-3 in the View menu, ⌘0 and ⌘1 stay with the zoom), the
  tab's sections (scrolling), the Information area and the Preview and
  Scan buttons. Develop (corrections, lot 3) has its place between Scan
  and Output but is not shown: no empty tab, no inactive control. The tab
  shown and the folded sections are remembered between launches.
- **Prepare**: Original (film, holder) and **Framing**, a permanent
  section that replaces the crop options shown at the top of the panel in
  lot 1: orientation, proportions and lock, angle, straighten (rule; Auto
  (edges) disabled), grid kind, tint (colour and opacity of the grid),
  constrain to image. The name "Crop and Straighten" is gone: the section
  is Framing everywhere; the tool keeps its name (Crop, « Recadrage » in
  French). Choosing the Crop tool or the rule (C, R) shows Prepare with
  Framing unfolded; in crop mode the section is lightly tinted and its
  title row carries Done (Done, Return and Esc unchanged). **Reset** (user's
  decision after the tests of lot 1b) is always on the title row: it puts
  back the orientation, the proportions, the fine angle and the frame (not
  turned, free, 0°, the whole image), keeps the lock and the constraint,
  and Edit > Undo (⌘Z) undoes it (Redo resets again) as long as nothing
  else has changed the recipe and no other image has come: a turn, a
  frame, Esc in crop mode, a new preview (whatever its size; user's
  decision after the push of lot 1b) or the scan removes the Undo,
  so that ⌘Z never brings back a state left in between or the frame of
  another image; in crop mode Esc still goes back to the state on entering
  the mode. This replaces lot 1's Reset, which kept the
  turns and worked only in crop mode. The
  tool keys H, Z, C, R work wherever the keyboard focus is in the main
  window (a tab or a control of the panel after a click), except while
  text is typed in a field, as X does; a tab clicked with the mouse gives
  the focus back to the image (from the keyboard or VoiceOver it stays in
  the tab bar) (user's tests of lot 1b: C and R did nothing once a panel
  control had the focus).
  Folded: "6×7 · −1° · 90°" (proportions, fine angle and turns when not
  zero, mirror).
- **Scan**: resolution, scale, input, output. **Output**: unchanged.
- **Information** (common to every tab, not scrolling): Histogram then
  Exposure, each foldable; when the window is low, the tab's content
  scrolls (minimum height kept).
- **Tool column**: Hand and Zoom, a line, Crop and Rule, a line, Grid
  (click: show or hide; right click: kind, colour, opacity) and Exposure
  Zones (the Exposure section's checkbox, the same setting; a neutral
  icon, a half-hatched circle, not a warning sign: user's decision). The
  pipettes and the densitometer come with lot 3. Until 2026-11-21 Grid
  and Exposure Zones were at the bottom; moved up at the user's request,
  order still to be decided.
- **Tooltips** (a rule for every lot from now on): every control of the
  panel, every tab and every tool has a native one-sentence tooltip, in
  English and French. Detailed help (⌥ + hover) comes later. A function
  with a keyboard shortcut ends its tooltip with the shortcut in
  parentheses ("Crop: draw and adjust the frame, in Prepare › Framing
  (C)", "Resolution, scale and sizes of the scan (⌥⌘2)"; user's decision
  after the push of lot 1b): Mac symbols for ⌘ ⌥ ⇧ and the arrows, the
  keys without a letter in full, in the application's language (Return,
  Esc, Space; Retour, Échap, Espace). A key may also be named inside the
  sentence ("Hand: move the image; hold Space to use the Hand for a moment
  (H)"). It is taken from the source the menus and the key handling use
  (`AppShortcut`), never copied by hand. `ShortcutTests` checks that:
  - every shortcut is mentioned in a tooltip, at the end or inside it;
  - each key the window and the canvas handle (their lists `windowKeys`
    and `canvasKeys`) is recognised from its own shortcut by the matcher
    they both use (`AppShortcut.matching`), letters and keys without a
    letter alike, with Shift ignored except for the arrows, as before;
  - the other shortcuts are in a list of menu shortcuts, with a key
    equivalent;
  - every sentence is in the catalogue, translated into French, with a
    comment, with the place of a key named inside it ("%@") exactly once
    where there is one and nowhere else;
  - no translation contains a shortcut with a symbol (⌃ ⌥ ⇧ ⌘ or an
    arrow), nor a key's name in parentheses ("(Esc)", "(Espace)").

  It does not detect: a lone letter copied by hand ("(C)"), nor a key's
  name copied as a word of the sentence ("hold Space"), since a sentence
  may hold such words; a case missing from the window's or the canvas's
  own `switch` (the key would be recognised but do nothing); a menu item
  that does not take its key from `AppShortcut` (the list of menu
  shortcuts in the test is written by hand). The debug probe
  (`-X1ScanKeyProbe`) presses the keys in the application itself.
  Not changed (user's decision): the real X1's confirmations keep their
  "(⌘. or Esc)". The Settings note "Scanner Information (⌘I)" takes its
  shortcut from `AppShortcut` since lot A ("Built-in help").
- **Not in this lot**: the RGB values under the pointer in the
  Information area come with the pipettes and the densitometer, in lot 3
  (user's decision after the tests of lot 1b); nothing is shown for them
  before, no inactive control.
- **Language** (user's decision, replacing the brief's point F): the
  Language menu of Settings > General stays, with the sentence "Restart X1
  Scan to apply the language." next to it.
- **Fine angle** (user's decision): the slider, the typed field and the
  arrow keys move by whole degrees (−45° to 45°). An arrow goes to the
  next whole degree in its direction (from −1.3°, → gives −1° and ← gives
  −2°); ⇧ + arrow to the next multiple of 5° (from −1.3°, → gives 0°,
  then 5°). The straightening rule
  keeps the angle it measures to the tenth: the recipe keeps tenths, and
  the field, the summary and the rule's label show whole degrees, or a
  tenth when the rule measured one ("−1.3°").

## Built-in help (lot A, 2026-11-20)

From the user's brief of 2026-11-20 and the answers to its plan (points 1,
2, 9 and 10: the recommendations taken).

- **One source**: Markdown pages in `docs/help/fr` and `docs/help/en`,
  same file names and same anchors in both languages (tested). There is
  no help text anywhere else; the error messages' texts are in the String
  Catalog, and the Troubleshooting entries add to them (when it happens,
  what it means) rather than repeat them.
- **Format** (point 1): a help window in the application (Help > X1 Scan
  Help, ⌘?), with its own search, and the pages in the results of the Help
  menu's search field through `NSUserInterfaceItemSearching`; no Apple Help
  Book. Reasons: testable, light and dark mode with the system's colours,
  the Help button of a message opens an exact anchor, no cache of the
  system's help viewer.
- **Conversion** (point 2): the `.md` files are copied unchanged into the
  application (folder reference `docs/help`) and turned into HTML when a
  page is shown (`HelpMarkdown`, a small tested subset), not by a build
  phase. The Keyboard Shortcuts page is completed at that moment from
  `AppShortcut.helpTable`: never written by hand (tested, and the
  shortcuts written in the other pages must be some shortcut of the table).
- **The menu shortcuts without a tooltip** (zoom, Hide Settings Panel,
  Redo, Scanner Information, Settings, Help) joined `AppShortcut`
  (`menuOnly`); the menus take their keys from it, unchanged (tested). The
  Settings > Scanner note now takes ⌘I from the same source (the point
  left open by lot 1b).
- **Content** (point 9): the public help does not name the hidden settings
  of the real X1; it says that preview and scan on the real X1 are being
  validated, and describes the path in discovery mode. Steps that involve
  the scanner give the X1's state. X1 Scan needs macOS 26.
- **Rule** (CLAUDE.md, "Built-in help"): every batch that adds or changes
  a feature updates its help pages in both languages; x1-ui checks it.
- **Icons** (user's request of 2026-11-21): a page shows the icon of each
  tool and icon button next to its name, written `{icon:<key>}`. The keys
  and the symbols come from one table, `AppIcon` (X1ScanCore), which the
  interface uses too; a test checks that the application names none of
  these symbols itself, and that every icon of the table appears in both
  languages. The application draws them when a page is shown (system
  symbols through AppKit, the swap-proportions icon through its own view)
  into a `data:` PNG used as a CSS mask of the text's colour, so that it
  follows light and dark mode. No exported image of a system symbol is in
  the repository. Text-only buttons (Preview, Scan, Done) have no icon.
- **Hardware page** (2026-11-21): `hardware.md` gives the connection chain
  with Apple's model and part numbers (A1790 / MMEL2, A1463 / MD464, both
  no longer sold new) and links to ASFireWire, described only as its own
  repository does (restores FireWire on macOS 26 Tahoe with DriverKit;
  install guide on its website), as a third-party project in beta. The
  help's links may be `https` web addresses (opened in the browser).

## Lot A: error catalogue (2026-11-20)

- **Identifiers**: every case the user can see has a stable identifier
  (`IssueID`, e.g. `no-scanner`, `unexpected-state`), its texts in the
  String Catalog (`issue.<id>.title`, `.cause`, `.step1` to `.step3`, English
  and French) and its Troubleshooting entry `troubleshooting.md#<id>`
  (tested). A case not foreseen gives `unknown`, with its details.
- **Presentation only**: `IssueClassifier` reads what the runner, the
  guards, the transport and the export already decided. The alerts keep
  their cases and their moment; the guards, the runner and the log are
  unchanged. The message shows the operation, a title, the likely cause,
  one to three steps (the advice to switch the X1 off and on first, and
  only once), a Help button, and the technical text of before in a folded
  Details part (Copy Details). A safety check's message says the stop is
  on purpose, to protect the scanner.
- **Transport errors** (plan, point 5): the runner keeps them as text
  (`PreviewAnomaly.transport(String)`, `.couldNotOpen(String)`); X1Kit was
  not changed. The text is compared with `TransportError`'s own
  descriptions, so a changed wording fails the tests. Timeouts give
  `scanner-timeout`, a device gone `disconnected`, a refusal of the guard
  `guard-refused`, other IOKit errors `unknown`.
- **ASFireWire** (point 4): not told apart from an X1 that is off (IOKit
  sees no device in both cases); `no-scanner` names both causes.
- **Holder** (point 8): no capture shows how the X1 answers without a
  holder, and the holder code is not read by the application: the
  identifier `holder-missing` and its entry are reserved, nothing leads to
  them, nothing is guessed. `notJustSwitchedOn` (a fixed cold script the
  application never runs) is shown as `unexpected-response`.

## Lot A: discovery mode (2026-11-20)

- **What it is**: File > Try Without a Scanner, or the button of the "No
  X1 found" message. The application runs on the virtual X1 (the same
  `VirtualScanner` and `PreviewSession` as `tools/run-virtual.sh`, which is
  unchanged: it imposes the source at launch, with no banner and no mark).
  A banner above the image says "Discovery mode — no scanner connected",
  with Leave Discovery Mode. Not saved: every launch starts outside it.
- **Safety** (user's decision): in discovery mode no transport to a real
  X1 is opened, even when one is connected: `startRealPreview`,
  `startRealScan`, `readRealScanner` and the presence check refuse, and the
  source stays virtual (tested with spies on every way to the real X1).
  Leaving puts back the source of before, without saving it, and looks for
  the X1 again (point 7).
- **Presence check** (point 3, user's decision): `cx1_find` looks up the
  I/O Registry for an Imacon / Hasselblad device and reads its properties
  only: no plug-in interface, no opening, no command (a test checks the
  C source; x1-reviewer checks it). It runs at launch when the source at
  launch is the real X1, and on leaving discovery mode; nothing with the
  virtual source. None found: "No X1 found", which offers discovery mode.
- **Samples**: a file written in discovery mode has a suffix (`_sample`,
  `_exemple` in French), the TIFF ImageDescription "X1 Scan discovery mode
  sample: synthetic image, not a scan." and `"sample": true` in its recipe
  (written only when true: other recipes are unchanged). Files written
  outside the mode have no description, as before.
- **Image** (point 6): the virtual X1's synthetic test pattern for now.
  The user's own photograph will go to `app/X1Scan/Sample/discovery-film.tiff`
  with its licence in `LICENSE-SAMPLE` (as `LICENSE-ICON`); `SampleFilm`
  then makes the virtual X1's film from it (`SyntheticFilm(transmission:)`,
  simulator only). No photograph is in the repository (tested).
  User's decision of 2026-11-21: **two images** of the same film, one for
  the preview and one for the scan. Each becomes its own film through
  `SampleFilm.film(from:rowsPerColumn:)`: 3 for the preview (its pixels are
  drawn 1:3, "Pixel aspect", a [hypothesis]), 3/5 for the scan (raw lines
  of 3/5 of a column, `ScanDecoding.linesPerOutputLine`, so that the decoded
  scan's pixels are square). Today `SampleFilm` reads one image with
  `rowsPerColumn` 1 and gives it to both passes: no photograph is added
  before that changes (README roadmap).

# Project journal

## 2026-11-12: first contact with a real X1

Setup: Flextight X1, Intel Mac on macOS 10.14 Mojave, FlexColor 4.8.13.

1. **Enumeration**: the X1 appears in IOKit as a standard SBP-2 SCSI scanner
   (type 6), `Imacon` / `Flextight X1` / `R185`, open to SCSITaskUserClient.
2. **First commands from our own code** (`tools/x1probe`): INQUIRY,
   TEST UNIT READY and REQUEST SENSE answer correctly, cold, without
   FlexColor ever having run.
3. **Initialisation captured** (lldb): FlexColor only reads (INQUIRY, vendor
   mode pages, log page, registers). No firmware download: the X1 runs from
   flash.
4. **Our tool replays these reads**: the serial number is in vendor mode page
   0x26.
5. **Preview captured** with the scanner's responses: full sequence
   (calibration, positioning loop, SCAN, line counter, READ, stop) and wait
   rule on 0xDF.
6. **Preview decoded without FlexColor** (`tools/decode`): RGB 16-bit LE
   interleaved, flat field from the calibration lines, one-line R/B gap, 3:1
   aspect. Geometry identical to FlexColor's preview of an IT8.7/1 target.

Lesson: FlexColor's alert "Impossible de terminer votre requête à cause de ."
means another program already has the scanner open.

Next: capture a full-resolution scan; replay a preview from our own code.

## 2026-11-12: preview fixtures

Added `tests/fixtures/`: the 766 SCSI exchanges of one preview
(serial number anonymised, no image data) and the per-column white / dark
calibration levels. They will drive a simulator and a conformance test.
Correction: vendor page 0x25 is not static. Byte 21 changes over time
(0x1c / 0x1d back and forth within one preview), so it is a live reading,
probably a sensor, not a firmware date.

## 2026-11-12: X1Kit, step 1 (no user interface)

Swift package `X1Kit/`: transport (IOKit with a read-only guard, and a
simulator replaying the preview capture), protocol (commands and response
parsers), FlexColor's preview sequence, image decoding and 16-bit TIFF export.
Our preview sends the same commands as FlexColor (CDB, transfer length,
data_out, same order) and waits on 0xDF at the same points; the decoded
simulated preview matches the synthetic film. Nothing has run on a real
scanner. Decisions are in `decisions.md`.

Found while writing the sequence:
- After SCAN, FlexColor does not wait for 0xDF `00 00`: it starts reading as
  soon as it reads `00 01`.
- White and dark references are read after `F0 01 01 00 01` and
  `F0 01 00 00 01`: they differ in flag B, not C (protocol.md §8 corrected).

## 2026-11-12: application, step 2 (shell on the virtual X1)

The macOS application `X1 Scan` (`app/`): AppKit window with toolbar
(Preview, Scan disabled, Stop, Export), a floating glass tool capsule (hand,
zoom, crop rectangle without effect), the image area (fit, zoom, pan, 3:1
aspect at display only) and a palette column (Scanner, Histogram, Info,
Export) that folds into an icon bar. English and French.

The preview runs on the virtual X1 only and the image builds up line by
line. The real X1 is only read (identity, state, counters), on request, and
closed right after. Nothing has run on a real scanner.

X1Kit changes:
- `PreviewRunner.run(progress:)` reports steps, phases, page 0x20 reads and
  READ data; the command sequence is unchanged (tested).
- `IncrementalPreviewDecoder` decodes block by block, identical to the batch
  decoding (tested).
- `SimulatedX1` accepts an early `DB` after SCAN (emergency stop) and replays
  the 0xDF states captured after FlexColor's end-of-scan stop. How a real X1
  answers a `DB` sent mid-scan is not captured **[hypothesis]**: a clean stop
  on the virtual X1 proves nothing for the real scanner.
- `PreviewGeometry.pixelAspectRatio` (3, hypothesis) is the only place the
  aspect factor is set.

Open: colour space for display (linear sRGB, provisional), aspect factor,
floating palettes and workspaces (modelled only).

## 2026-11-14: roadmap and related software

Roadmap gains a read-only calibration backup step (read-only commands only,
kept outside the repository) and future ideas; 20More added to related
projects (feature ideas only, see decisions.md); holder identification noted
as a hypothesis in protocol.md, where we also note that the holder type used
during the captures was not recorded.

## 2026-11-14: read-only policy matches the captures byte for byte

`CommandPolicy.readOnly` now compares each CDB with the captured one: only
the MODE SENSE page and per-page length and the 0xEE address vary, within
the values seen; a test replays every captured read of the fixture.

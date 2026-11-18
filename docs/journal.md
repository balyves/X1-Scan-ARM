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
kept outside the repository) and future ideas; a commercial Flextight
application noted as a source of feature ideas only (see decisions.md); holder identification noted
as a hypothesis in protocol.md, where we also note that the holder type used
during the captures was not recorded.

## 2026-11-14: read-only policy matches the captures byte for byte

`CommandPolicy.readOnly` now compares each CDB with the captured one: only
the MODE SENSE page and per-page length and the 0xEE address vary, within
the values seen; a test replays every captured read of the fixture.

## 2026-11-14: application step 2b

Scanner menu and Scanner Information window replace the Scanner palette;
detailed zoom (steps 6.25-1600 %, Fit, Fill, typed values, recomputed on
resize); Window menu to show and hide palettes; Settings window (language,
serial masking, appearance, background, startup zoom and source, export);
Stop red only during a preview; square-root histogram; real next export
name. Nothing sent to a scanner changed; the app still only reads the real
X1, on request.

## 2026-11-14: future ideas and candidate building blocks

README roadmap gains future ideas (linear DNG, ICC profiles, densitometer,
3F re-opening, strip batch scanning, metadata palette); decisions.md lists
candidate building blocks and their licences, to check again before use.

## 2026-11-14: colour, licences and 3F precautions

IT8.7/1 profiling stays in roadmap step 8; the future idea keeps only the
ICC profile embedded at export. decisions.md adds licence details (lcms2
core only, DNG SDK and DNG patent licence to check, output profiles never
committed) and the rules for existing 3F files.

## 2026-11-14: application step 2c

Palettes: several open beside the icon bar, drag-and-drop order, floating
panels (detach, attach); Palettes button in the toolbar group; custom
background colour; file name builder with roll, frame and counter
settings; Settings with an icon toolbar; Fit no longer computed from an
unknown view size. Two timing-sensitive session tests made robust (slower
virtual image reads in the tests). Nothing sent to a scanner changed.

To do later: make the stop tests deterministic (the virtual X1 waits for a
signal from the test instead of a 100 ms delay per image read).

## 2026-11-14: procedure for the next scanner session

`docs/test-session.md`: preparation, read-only ASFireWire test on the
development Mac, capture of a real scan on the reference Mac, what to keep
and pass on. `cap3.py` gains `X1CAP_RAW` and `X1CAP_SCAN_MB` (image data
after each SCAN limited to a contiguous start; calibration reads, CDB
byte 5 = 01, never skipped).

## 2026-11-14: application step 3, settings panel

Palettes replaced by a fixed settings panel on the right, after Epson Scan
2 (Scanner, Original, Main / Advanced, Output, Preview and Scan buttons),
with a tool column beside it and no window toolbar; R G B, estimated file
size and zoom in the bottom bar. Exports in RGB or grey, 16 bits (linear,
raw) or 8 bits (sRGB curve and profile, provisional), with no compression,
LZW or ZIP (with the horizontal predictor), written by our TIFF writer and
read back by ImageIO. Zoom menu applies only confirmed choices (likely
cause of the 6.25 % report); token buttons insert at the caret.

## 2026-11-14: film holders

Holder menu fed by a data file of the 21 holders of Hasselblad's
compatibility table (reference, format, opening, frames; data only) and by
custom holders, managed in Settings > Holders. protocol.md: the X1 might
report the reference of the inserted holder (a commercial Flextight
application shows "6×7 [50200420]") **[hypothesis]**, to check at the next session by noting the
reference of the holder used.

## 2026-11-14: step 3 fixes after testing

Scanner section removed from the panel (source in Settings > Scanner);
explanation under the buttons when Preview is unavailable on the real X1;
all panel sections open at first launch. The panel could not be widened:
its holding priority (750) was above the divider drag, and the width code
expected two subviews where macOS 26 also counts the divider; now 260-640
pt, restored after the first layout. Zoom shows "—" without an image and
Fit applies when the preview arrives; no R G B without an image.

## 2026-11-16: step 4, captured preview on the real X1 (code only)

FlexColor's captured preview can be replayed on the real X1, behind a
hidden setting, a confirmation before every run, and a guard that lets
through only the captured sequence, byte for byte, built from the capture
itself. Every command and response is logged in cap3.py's format. Not run
on the scanner yet. Found in the capture: FlexColor reads image lines
before the line counter announces them; the run follows it, with a 30 s
READ timeout (pending the user's approval). Usage counters observed (counters 1 and 6 ≈ minutes of
operation, counter 3 = scans) **[hypothesis]**. Name of the commercial
Flextight application removed from the documents (history unchanged).

## 2026-11-16: CI back to green; step 4 adjustments

The CI's app job had failed since 2026-11-14 (runs X1Kit #5-#7): the stop
tests depended on timing, and on GitHub's slower runners the preview passed
SCAN, or ended, before the stop arrived. The virtual X1 can now be paused at
a chosen command until the test lets it go on: the stop tests are
deterministic (the "to do later" of 2026-11-14). IOKit timeouts and other
delivery failures are now reported as such (SCSI service response), not
read as a scanner status (0x02 would have read as CHECK CONDITION). The user
approved the 30 s READ timeout (10 s for other commands). Scanner
menu: Read Identity and the source items removed (Scanner Information and
Settings > Scanner have them). The capture of 2026-11-12 used the 6×7
holder, reference 50200403.

## 2026-11-16: first preview on the real X1 (13:14)

Development Mac, ASFireWire 0.6.0, IT8.7/1 in the 6×7 holder (50200403).
The run stopped at step 38, the first page 0x20 read after `CF 00 01 80`:
position 8 203 against 6 155 in the capture. Nothing moved; the X1 was
restarted. The user's analysis: that read shows the state left by earlier
use, not a measurement. After power-on page 0x20 holds 2 048 × 3 (bytes
19-24), 8 203 and 0 lines; the capture, made after several previews, had
1 936 / 1 846 / 1 891, 6 155 and 824 (protocol.md §5). The position
tolerance now applies only after a window that requests a position.

## 2026-11-16: the sequence right after power-on

Three more tests on the real X1 (13:27, 13:29, 13:31). The first two still
ran the previous build and stopped at the first page 0x20 read again. The
third ran the new build, went past it and stopped at a wait on 0xDF: `08
07` after the first `F0`, a state the runner did not know. Nothing was sent
after either stop.

The user then captured FlexColor right after power-on (cold lamp, 6×7
holder 50200403): 821 commands, all status 0x00. The sequence differs from
the warm one: a page 0x28 read before the session start, other calibration
windows (ratio 62 500), more `F0`, and the busy states `08 02`, `08 03`,
`08 06`, `08 07`. From the preview-width calibration on it is the same.
The two sequences already differ before the first page 0x20 read, so the
choice between them cannot be made there: the user chose to send only the
cold sequence for now, behind a check of the power-on values (2 048 × 3).

To do later: a warm capture right after a cold one, without switching the
X1 off, to see what triggers the page 0x28 read.

Holder timing in the cold capture (user, 2026-11-16): inserted after
FlexColor was opened, just before the preview, which matches the 0xD3
activity between the initialisation and the session start. Test-session E3
now inserts it at the same point (after Read Identity, just before the
preview). The confirmation of a real preview gets a fourth check: the X1
was switched off and on since the last real preview.

## 2026-11-16: first complete preview on the real X1 (15:14)

Development Mac, macOS 26 Tahoe, ASFireWire 0.6.0, the sequence right
after power-on (test-session part E). **Success**
**[confirmed]**:

- the 208 commands outside polling were identical, byte for byte, to
  FlexColor's capture right after power-on (`flexcolor-froid.txt`);
- 380 statuses, all 0x00;
- 0xDF states `08 01`, `08 02`, `08 03`, `08 06`, `08 07`, `08 40`, then
  `00 00` (all already listed in protocol.md §7);
- it ended with `DB` and `CF 00 02 80`;
- the decoded image is correct. Mean white reference about 54 148 /
  52 342 / 44 168 (R/G/B), dark about 314 / 288 / 305.

This is the first complete preview driven by our own code: roadmap step 6
("Preview driven by our own code") is done. It also means the large READs
(47 952, 120 240 and 240 480 bytes) went through ASFireWire. The run log stays outside the
repository.

Also observed today (once): after the FireWire cable was moved from one Mac
to the other, the X1 was detected only once it had been switched off and on
again. Test-session now asks for it wherever the cable changes Mac.

## 2026-11-17: what makes FlexColor choose the cold or the warm sequence

Two more FlexColor captures by the user (logs outside the repository): A,
the X1 just switched on, two previews in one FlexColor session; B,
FlexColor restarted with the X1 still warm, one preview. Analysed against
the two fixtures (protocol.md §11):

- The warm and cold sequences are identical up to the first page 0x20 read
  after the session start, apart from the page 0x28 read, and diverge right
  after it; that read shows the power-on values before both cold runs and
  values left by earlier use before the warm ones. **[confirmed]** It is the
  only response that separates cold from warm runs in all five sessions
  (the 0xD3 activity also comes before a warm one). FlexColor choosing from
  it is a **[hypothesis]**.
- Page 0x28 was not read this time: the cold run A1 is the cold fixture
  without it. **[confirmed]** It is not what selects the sequence.
- B is command for command the warm fixture of 2026-11-12; it becomes a
  second warm fixture, `preview-sequence-warm-2.json`. **[confirmed]**
- A second preview in the same FlexColor session is a third, shorter
  sequence, with a window and a READ found in neither fixture (calibration
  partly reused **[hypothesis]**).
- Measured positions differ between captures by 128 (B) and 192 (A1). With
  the tolerance of 100 our runner would have stopped A1 (checked reads) but
  not B (the difference is on the unchecked read). A1 is the cold sequence,
  the one sent to the real X1: the threshold has to be decided again
  (decisions.md).

## 2026-11-17: first scans captured (1 000, 2 000, 3 200 ppi)

Three FlexColor runs by the user, each a preview then a scan of a small
frame, plus FlexColor's 16-bit TIFF of each scan (all outside the
repository). Fixtures `scan-sequence-1000ppi.json`, `-2000ppi`,
`-3200ppi`; new decoder `tools/decode/decode_scan.py`. Details in
protocol.md §9, §10 and §12. **[confirmed]** unless noted:

- SET WINDOW offset 10 = resolution × 50 000 / 3 at 1 000, 2 000 and
  3 200 ppi (that the preview is 160 ppi is a **[hypothesis]**).
- Lines have 24 more pixels than asked (8 at 1 000 ppi, binning 3), at
  the start of the line, dark in the image.
- A scan reads its own white and dark at full width (50 + 180 lines), then
  a 400-line step after `1b 00 08 06 01 00`. Those 400 lines are not dark:
  one place of the film, at the middle of the frame along the drum, read
  over and over, with a sharpness peak in the middle: a focus sweep
  (**[hypothesis]**, strongly supported). The order of the two steps
  changes between captures. 0xDF shows a new state, `00 06`, before that
  step's reads.
- The image follows `1b 00 00 01 01 00`: 41 one-line priming reads (15 at
  1 000 ppi) = 2 × the R/B gap (20, or 7) + 1, then 20-line blocks.
- FlexColor reads exactly floor(TIFF lines × 5/3) image lines. Decoded,
  realigned and resampled by 3/5, our image matches FlexColor's TIFF
  (correlation of log values 0.997-0.999 at 2 000 and 3 200 ppi). The
  "about 1.7" factor is 5/3.
- MODE SENSE page 0x24 (32 bytes) appears, once per scan; not in the
  read-only policy.
- No cold session in these runs; all six sessions are warm and follow the
  page 0x20 rule. No page 0x28.
- A scan cannot be a pure replay of a capture: its windows carry the frame
  and a position measured during the same session.


## 2026-11-17: scan decoding in Swift, scans on the virtual X1 (step 1)

First step of the plan for real scans (decided today, docs/decisions.md
to follow with step 2): everything on the virtual X1, nothing sent to the
real scanner.

- `X1Image/ScanDecoding.swift`: the steps of `tools/decode/decode_scan.py`
  (margin, flat field from the full-width calibration, R/B gap from the
  priming lines, 5/3 → 1 resampling). On the three real scans of
  2026-11-17 it gives the same linear values as the Python decoder (largest
  difference below 1e-4 on every pixel, once Python's clip at 1e-4 is
  applied; optional test `sameResultAsThePythonDecoderOnARealScan`, fed by
  `decode_scan.py --export`, run locally with the captures, which stay
  outside the repository).
- The simulator now serves scans: synthetic per-column white and dark,
  dark margin pixels, the line gap of each SCAN taken from the capture's
  priming lines. A test replays each scan fixture and checks the decoded
  image against the synthetic film.
- Still open before a real scan (step 2): the position tolerance (192 or
  256; largest difference seen on a checked read: 192), page 0x24 in the
  read-only policy, 0xDF `00 06` only during a scan, and the single
  substitution of the measured position in the 400-line window.

## 2026-11-17: real preview, cold or warm chosen by page 0x20 (step 2, part 1)

User's decisions of the day, in docs/decisions.md ("Real X1: cold or warm
sequence"). Nothing was sent to the real X1.

- The runner sends the part common to both captured previews, reads page
  0x20 and goes on with the cold sequence (power-on values) or the warm one
  (values left by earlier use); anything else stops there, before any
  window, mode, exposure or READ (only reads, D2 and the session start
  come before it).
  The cold sequence no longer reads page 0x28.
- The guard follows either capture; where they differ, the first command
  decides.
- Position tolerance 256 (largest difference seen on a checked read: 192).
  The run's log notes the chosen sequence and every position that differs
  from the capture.
- Page 0x24 (32 bytes) joins the read-only list.
- The "switched off and on" box is asked only after a real preview that did
  not complete.
- `CaptureLog` now writes `-- 0 octets` for commands without data, like
  cap3.py: the converter could not read our own logs without it.
- Option A (user's decision, after the review): the warm sequence's page
  0x20 read before the window with target 25 000 is always checked
  (tolerance 256). In the 2 000 ppi run's preview it gave 24 523 and
  FlexColor skipped that window; we stop there instead. Why 24 523: a state
  left by an earlier session is the **[hypothesis]** (that preview was the
  first session of its FlexColor run), to check at the next capture
  session.

## 2026-11-17: the 2 000 ppi scan on the simulator (step 2, part 2)

- `ScanScript.flexColor4813Scan2000ppi`: FlexColor's scan session of the
  2 000 ppi capture, command for command, with its 0xDF waits (including
  the windows, after which FlexColor polled 0xDF too), `00 06` after
  `1b 00 08 06 01 00`.
- The runner fills the window of the 400-line step with the position read
  just before, within the tolerance; the scan guard accepts that one
  difference only (docs/decisions.md, "Real X1: scan"; CLAUDE.md rule 4).
- On the simulator, the run goes through the guard and the decoded image
  is 609 × 614 pixels, FlexColor's size for that scan. Nothing was sent to
  the real X1; the app does not run scans yet.
- After the substituted window, page 0x20 reads are compared with the
  position sent, not the captured one (user's decision). In the captures
  the position after that window stays constant: at the target at 2 000
  and 3 200 ppi, 83 below it at 1 000 ppi (8 081 sent, 7 998 read).

## 2026-11-17: scan in the app, on the virtual X1 (step 2, part 3)

Interface validated by the user before it was written (docs/decisions.md,
"Real X1: scan", "In the app"). On the virtual X1 the Scan button replays
FlexColor's 2 000 ppi scan session, decodes it (609 × 614 px) and saves a
16-bit TIFF at 2 000 ppi in the export folder. On the real X1 it is behind
`EnableRealScan`, a complete real preview and a two-box confirmation;
tested only against the simulator behind the scan guard. Phases come from
the commands sent ("Focusing" for the 400-line step, a **[hypothesis]**).
The run log is now closed after the end of the session, so that it can
note the file saved. Nothing was sent to the real X1.


## 2026-11-18: 0xDF `08 00` after the final DB of a real preview

First real preview of the day: the cold sequence was chosen by the first
page 0x20 read, the position differences were -64 (within 256) and the
image was complete. Right after the final `DB`, 0xDF answered `08 00`, a
state never seen before (FlexColor's captures show `08 01`, then `00 00`).
The runner stopped at that step (step 205), sent its emergency `DB`, and
the X1 answered `08 01`, then `00 00`. The state is **[confirmed]**
(observed once); that it ends by itself without the second `DB` is a
**[hypothesis]**.

Fix (user's decision): `08 00` is accepted as busy only during the wait
that follows the final `DB` of the preview or of the scan, and the wait
after the emergency `DB`. Anywhere else, including after the scan's
middle `DB`, it still stops the run (`ScannerState.isBusyAfterStop`,
`StateAfterStopTests`; protocol.md §7, decisions.md "Waits on 0xDF").

## 2026-11-18: 0xDF states of the scan captures

Before the first real scan, every 0xDF state of the three scan captures
was listed with the wait where it appears. `ObservedStatesTests` walks the
warm previews (five captures), the cold preview and the 2 000 ppi scan
session against the scripts; the 1 000 and 3 200 ppi scan sessions, which
have no script, were checked by hand, listing their states.
The 2 000 ppi scan session itself shows only states already accepted.
Two states are outside the global list, both **[confirmed]**:

- `08 80`, after `08 01` and for a long time (69 and 96 reads), then
  `08 40`, `00 00`: after the first `f0 00 01 01 01 01` of the warm
  preview before the 2 000 ppi scan (seq 325), and after the
  `f0 00 01 01 01 01` of the 3 200 ppi scan session (seq 809).
- `08 04`, once: 1 000 ppi scan session, seq 803, a step without
  equivalent in the 2 000 ppi scan.

User's decision: accept a state only in the waits where a capture shows
it. `08 80` is accepted in the warm preview's wait after its first
`f0 00 01 01 01 01` only; not in the cold preview, and not in the
2 000 ppi scan (at that step only the 3 200 ppi capture shows it). `08 04` is
accepted nowhere. The warm previews before the scans, the cold preview
and the 2 000 ppi scan session are now walked against the scripts in the
tests: every state they show is accepted at its step.

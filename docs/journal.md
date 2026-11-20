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
windows (ratio 16 000 000; first noted as 62 500, read one byte off), more `F0`, and the busy states `08 02`, `08 03`,
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

## 2026-11-18: second stop on 0xDF `08 00`, in the middle of the cold preview

A second real cold preview stopped at step 81, in the wait after the
first `f0 00 01 01 01 01`: `08 07`, `08 03`, `08 01` ×6, then `08 00`
(before SCAN, so no emergency `DB`). Second observation of `08 00` that
day **[confirmed]**; FlexColor's captures never show it.

User's hypothesis, noted as **[hypothesis]**: `08` = busy, the second
byte = the activity in progress, and `08 00` a short transition between
two activities that FlexColor, polling more slowly, never caught.

User's decision: in every 0xDF wait, preview and scan, `08 00` is
accepted as busy when it follows an `08 xx` state accepted in that wait
(`ScannerState.isTransientAfter`, `TransientStateTests`). Not after
another `08 00`: two in a row were never seen, and after SCAN that would
delay the emergency `DB` by up to 120 s. Only 0xDF
reads, same time limit; `08 80` (scan) and `08 04` stay refused. Our
polling interval: 100 ms pause after each read, at most 120 s per wait.

## 2026-11-18: first real scan, stopped at the references

Cold preview complete (`08 00` accepted). The scan then went through
calibration and the 400-line step: measured position 16 843, 192 above
the captured 16 651, substituted within the tolerance. It stopped at
step 458, during the white and black references (8 016-pixel reads):
"line counter went back from 11 to 10". In the 2 000 ppi capture the
counter read 11 (0x0b) at both reads of that phase; here 11, then 10
**[confirmed]**.

The runner checked the counter after any SCAN-type command, including
the focus sweep `1b 00 08 06 01 00`. In all the captures the counter
only goes up between the image SCAN `1b 00 00 01 01 00` and the next
`DB` (9 image phases checked). User's decision: check it in that phase
only, preview and scan; elsewhere, not at all (nothing we send depends
on it). Its meaning outside the image phase is a **[hypothesis]**
(`LineCounterTests`, protocol.md §5).

## 2026-11-18: first real scan, complete

At 08:39 X1 Scan ran FlexColor's captured 2 000 ppi scan on the real X1,
on macOS 26 Tahoe, after a complete cold preview: 746 exchanges, no error
status. The focus step measured 16 779, 128 above the captured 16 651,
and that position was substituted (within the tolerance of 256). The
TIFF is 609 × 614 pixels, RGB 16-bit, 2 000 ppi, and the image is
correct (checked outside the app) **[confirmed]**.

Three corrections that morning, each after a stopped run (entries
above): 0xDF `08 00` accepted after a final or emergency `DB`; `08 00`
accepted in every wait right after an accepted `08 xx`; page 0x20's line
counter checked in the image phase only.

One display bug: the app showed the scan stretched vertically, with the
preview's pixel aspect ratio of 3. Scans are now shown with square
pixels (`Viewport.setImage(width:height:pixelAspectRatio:)`). The hidden
settings `EnableRealPreview` and `EnableRealScan` were turned off
afterwards (test-session.md F4).

## 2026-11-18: FlexColor captures: two scans in a row, warm previews, holders

Captures on the Mojave Mac with FlexColor 4.8.13 (fixtures in
`tests/fixtures/`, README there; details in protocol.md §11-§13):

- **F**: X1 switched on just before, a cold preview, then two 2 000 ppi
  scans of the same frame with no preview between them. FlexColor does
  everything again for each scan **[confirmed]**; the second scan session
  differs only by one `F0` less, one page 0x20 read more, the target
  position of the 400-line window (16 907, then 16 971) and offsets 54 / 58 after the 400-line
  step: 750, then 450 below the base, hence +300 in the image window.
  Page 0x24 is identical in every scan; all corrections are multiples of
  50, consistent with a focus sweep of 400 steps of 50 from base + 10 000
  and FlexColor keeping the sharpest line **[hypothesis]**. The cold
  preview read 25 675 after `F0 00 00 01 01 01` and sent the window with
  target 25 000, which the cold capture of 2026-11-16 did not: in every
  capture that window follows a position above 25 000 **[confirmed]**,
  so FlexColor seems to send it only then **[hypothesis]**.
- **G1-G3**: three warm previews, FlexColor restarted before each:
  commands identical to the warm capture; 25 931, 25 995, 25 931 before
  the window with target 25 000. The 24 523 case did not come back. G3
  also shows 0xDF `08 00` for the first time in a FlexColor capture:
  `08 01` ×8, `08 00`, `08 40`, `00 00` after the first
  `f0 00 01 01 01 01`; FlexColor kept polling **[confirmed]**. Our runner
  accepts that sequence (`08 00` right after an accepted `08 xx`).
- **H**: eight previews, one per holder, Format menu never touched.
  FlexColor reads one CCD line at the holder's leading edge: a code of
  bright bars at a regular pitch, different for each of the seven
  holders **[confirmed]**; every other non-image response is the same
  whatever the holder, so FlexColor decodes the code itself
  **[hypothesis]**, strongly supported. For holders with two formats or two
  frames it adds two low-resolution passes (`1b 00 01 01 01 00`). The
  preview resolution depends on the holder (102 to 265 ppi), apparently
  to fit the opening in a fixed preview size **[hypothesis]**. In the
  wait after `f0 00 01 01 01 01` some of these previews also show 0xDF
  `08 04` and `08 05`, briefly, between other busy states **[confirmed]**;
  our runner would refuse them, which is safe: on the real X1 we only
  send the 6×7 sequences.

Nothing was sent to the real X1.

## 2026-11-18: holder code decoder

`X1Image.HolderCode` decodes the holder code from one line of raw pixels:
bright runs (runs much shorter than the typical bar ignored), pitch from
the span of slots 0-16, slots rounded to the pitch, one bar per slot;
the frame slots (0-3, 5, 6, 16 bright, 4 dark) must be there, and the code
is the set of bright slots 7-15. It gives the seven codes of the holder
previews and nothing for a line without the holder edge
(`HolderCodeTests`, on the seven code lines kept in
`tests/fixtures/holders/holder-code-lines.json` with the user's
agreement). Not used by the app yet; nothing was sent to the X1.

## 2026-11-18: one cold sequence only

The two cold FlexColor captures diverge at the first window after the
first page 0x20 read (ratio 16 000 000 and offsets 54 / 58 = 354 583 /
576 354 on 2026-11-16; 32 000 000 and 454 612 / 856 631 on 2026-11-18),
before the read that gave 14 219 and 25 675. With the windows of
2026-11-16, which our cold sequence sends, that read gave 14 027 to
14 219 in every capture and real preview (14 219 on 2026-11-16, 14 027 and
14 155 on 2026-11-18). The earlier note that our sequence "would stop" on
a run like the second capture was wrong: that case came from FlexColor's
own windows. User's decision: keep only the cold sequence of 2026-11-16
(protocol.md §12, decisions.md). The exception for the seven holder code
lines is now in CLAUDE.md rule 2 and the reviewer's instructions;
test-session.md part G lists the next capture session.

## 2026-11-18: guided capture session, timestamps in cap3.py

`tools/capture/guided-session.sh` guides the capture session of
test-session.md part G on the reference Mac (bash 3.2, nothing to
install): one lldb run of FlexColor with `cap3.py` per capture, named,
ended when FlexColor is quit; each step shown, timed in
`essai-notes.txt`, with screenshots (whole screen and every FlexColor
window); `--from N`
to resume. It never talks to the X1. Tested here in its dry-run mode
only (no FlexColor, no lldb): the 22 steps, resumes at steps 8, "08" and
"010", invalid options, end of input. Not yet run with lldb on Mojave:
`lldb --batch`, Ctrl-C (lldb in its own process group) and the window
list for the screenshots are to be checked there.

`cap3.py` now ends each CDB line with `  t=HH:MM:SS.mmm`.
`cap3_to_fixture.py` keeps it as `time`, and accepts more than 9 999
commands (a 5-digit counter, which the 4-digit pattern did not match);
both decoders ignore it. Checked on a capture rewritten with timestamps
and numbers past 9 999: same fixture and same decoder input as before.

## 2026-11-18: guided session (part G): window rules, holder previews

The guided script ran on the reference Mac for steps 1-22 (X1 on,
FlexColor launched by the guide under lldb for each capture; X1 off and on
for step 22), with no error or stop. Captures stay outside the repository;
`tests/fixtures/scan-windows-2026-11-18.json` keeps their windows, page
0x20 positions and motion/mode commands only. Deviations from the plan,
from the windows and FlexColor's TIFFs: step 6 was scanned at 3 000 ppi
(not 2 500); step 12 kept a 1.0 × 1.0 cm frame (not 3.0 × 1.0); step 17
was first made with the 24×36×4 by mistake, then again (`--from 17`) with
the 24×36.

Findings (protocol.md §9 "Window rules", §12, §13), checked by
`ScanWindowRulesTests` on the 15 scans:

- Image window: ratio = resolution × holder factor × 50 000 / 3 (factor
  1, 0.977, 1.0245, 0.8855 for the 6×7, 24×36×4, 24×36, 4×5); binning =
  min(4, ⌊*M* ÷ resolution⌋), *M* per holder (3 200 for the 6×7, 6 300 and
  2 040 for the 35 mm strips and the 4×5 are hypotheses; the scans only
  bound them); width = TIFF width; lines = ⌊TIFF height × 5/3⌋ + 2 × gap +
  2 with a gap of round(20 ÷ binning). [confirmed] on these scans.
- 6×7: offset 14 and offset 18 put the same frame at the same place at
  every resolution (CCD pixel 3 996 fixed on the film; offset 18 in lines
  of ratio ÷ 10 000 per inch), matching where FlexColor drew the frame on
  its preview. Offsets 54 / 58 before the focus step follow the optical
  resolution (resolution × binning) by a thin-lens-like model, within 1 on
  six values. [hypothesis] as general rules.
- The focus step and its correction behave as described before (base +
  10 000, then a multiple of 50 on both). Offset 62 of the focus window is
  probably 32 bits (byte 64 set in three windows: up to 97 134) and depends
  on the frame by a rule not found: a calculator cannot produce it yet
  (found later the same day: see the next entry).
- The references come before the focus step when the optical resolution
  is 3 000 or more, after it otherwise (20 scans).
- The first session of a FlexColor run starts with the ratio and optics
  of the holder used last (warm), other values after a cold-type start;
  it also reads the holder code, at full CCD width: the earlier note that
  the first preview has no code was wrong. New code: 6×7 = 14, 15. Each
  holder's preview window is the same as in the morning.

holders.json now gives the openings in inches as Hasselblad's holder sheet
(v4, 2019; facts only, sheet not in the repository) writes them, the
maker, the patent printed on Hasselblad holders (US 6,081,352) and the
code read for the eight formats captured; Settings > Holders and the
guide show mm and inches. User's decisions: the labels follow the sheet's
titles (50200407 and 50200410, where the sheet contradicts itself, keep
the title with a `note`), and the 6×7 code line (essai-K, full CCD width)
is the eighth code line kept in the repository (CLAUDE.md rule 2,
decisions.md); `HolderCodeTests` decodes it as 14, 15.

## 2026-11-18: offset 62 of the focus window; application icon

Offset 62 of the 400-line window does not seem to come from the
preview's content [hypothesis]: none of the measures tried on the
flat-fielded preview inside each frame (mean, density, contrast,
gradients, raw maximum) follows it (|r| ≤ 0.6 on the twelve 6×7 scans, seven distinct frames).
It follows the frame's position along the drum: 15 500 + 28 800 × the
middle of the frame's image lines in inches (offset 18 and offset 26
without the priming lines, divided by ratio ÷ 10 000), within 21 on the
20 scans of 2026-11-17 and -18 (four holders). [confirmed] on those
values; that it is the drum position of the focus line, 28 800 per inch
from 15 500 at line 0, is a [hypothesis], strongly supported. The exact
rounding is not known (protocol.md §9). `ScanWindowRulesTests` checks it
on the 15 scans of the afternoon.

The application has an icon: a design of the icon's copyright holder
(not under the MIT licence: `LICENSE-ICON`), split into
two SVG layers and assembled as an Icon Composer document
(`app/X1Scan/Icon/AppIcon.icon`); rendered with `ictool` in the light,
dark and tinted appearances at 1024, 128, 32 and 16 px, and shown by the
Finder. The fixtures the app does not read (holder previews and code
lines, warm-3 to -5, two scans in a row, the window fixture) are no longer
copied into the app bundle. The About panel shows both licences, copied
into the app; the copyright line is in English and French. The CI pins
Xcode 26.5 and checks the icon and the licences in the built app.

## 2026-11-18: standard MIT LICENSE; icon option D

With a line excluding the icon, GitHub no longer recognised `LICENSE` as
MIT ("Other", `NOASSERTION`). `LICENSE` is the standard MIT text again;
the exclusion stays in `LICENSE-ICON`, the README's licence section and
the About panel (CLAUDE.md rule 3, decisions.md).

The user chose option D of the icon among four renders (kept outside the
repository): the blue gradient also in the dark appearance, and a
14-unit stroke on the "X1" for the 16 and 32 px sizes.

## 2026-11-18: LICENSE copyright line

GitHub recognises `LICENSE` as MIT again after the standard text was put
back. Its copyright line now names the same holder as the About panel
(user's decision), instead of the project's author "and the X1-Scan-ARM
contributors"; every commit so far is by the user's account. The rest of
the MIT text is unchanged. CLAUDE.md rules 2 and 3, the reviewer's
instructions and decisions.md allow the holder's name in `LICENSE` on
that line only.
The About panel's copyright line follows: "© 2026 <holder>. Code: MIT
licence; icon not under the MIT licence" (and in French).

## 2026-11-19: part H planned (offset 62)

docs/test-session.md part H and the guide (`--part H`, steps 23-32): one
FlexColor run, 6×7 holder: one 0.50 × 0.50 cm frame left untouched at
2 000, 600 and 3 200 ppi (does offset 62 follow the frame or the rounded
window lines?), then moved by FlexColor's smallest steps and given two
other heights, to find the rounding behind the −6 to +21 residuals of
offset 62. Its unit is probably 1/28 800 inch (about 0.88 µm) [hypothesis]. Not
run yet.

## 2026-11-19: original calibration; parts I and J; holder decision

Tomorrow (2026-11-20) another program recalibrates the X1 and writes the
new calibration into the scanner. **Every capture and real run up to
2026-11-19 inclusive was made with the X1's original calibration.** Parts
H and I are to be captured today, still with it.

docs/test-session.md part I and the guide (`--part I`, steps 33-41): the
first preview of each holder whose run starts like our warm sequence (a
run after a 6×7-type holder), the 6×6 and 6×6×2 again with another
original. Part J: the check after the recalibration (reads only, then
FlexColor captures, then a comparison, and only then X1 Scan on the real
X1).

User's decision for the real X1: a holder other than the 6×7, detected
from the code line our sequences already read, stops the run right after
that read with a clear message (decisions.md, "Holder detection"; not
implemented yet).

`InfoPlist.xcstrings`: the bundle names Xcode extracted (CFBundleName,
CFBundleDisplayName) are kept, with the French value "X1 Scan".

## 2026-11-19: parts H and I captured (original calibration)

Both done with the guide, 08:21-09:12, the last captures with the X1's
original calibration (protocol.md §9, §12, §13; `scan-windows-2026-11-19.json`):

- Part H: FlexColor's zoom was at 160 %, so it scanned at PPP × 1.6
  (3 200 and 960 ppi). The untouched frame gave 59 542 at 3 200 ppi (twice)
  and 59 515 at 960 ppi: offset 62 follows the window at each resolution,
  but no formula of the window's values alone is exact (best within about
  ±10 units, 0.01 mm). FlexColor probably uses its own frame coordinates
  [hypothesis]. The lens model of offsets 54 / 58 matched a seventh,
  unfitted value (O = 2 880) within 1. Four of the eight scans skipped the
  calibration and references (rule unknown). A scan cancelled during the
  400-line step shows how FlexColor stops there: no more reads, 0xDF
  polled until `00 00`, then `DB` and `CF 00 02 80`. The heights typed at
  steps 30 and 31 were not taken; the step of that field is not known.
- Part I: the nine codes match the table; for the 6×7, 6×9, 6×6 / 6×4.5,
  6×6×2, 4×5, 24×36×6 and 24×36 runs, the commands up to the code read
  are those of our warm sequence; the 6×7 run is `preview-sequence.json`
  itself, and the 6×6 / 6×4.5 and 6×6×2 runs repeat 2026-11-18 to the end,
  low-resolution passes included, with another original. Every holder read
  now has a warm first preview starting like ours. The references typed
  were not the numbers: the guide's question is clearer now.

The guide now says that the 24×36 / 36×24 holder (50200401) has two
openings, one horizontal and one vertical (holders.json still lists one
24 × 35 mm opening: to be corrected after the user's answer), and asks to check FlexColor's
zoom at 100 % in part H. README roadmap: moving the crop frame with the
keyboard (arrows one step, Shift + arrows ten), with VoiceOver.

## 2026-11-19: two openings for the 24×36 / 36×24 holder

User's decision: `holders.json` gives the 24×36 / 36×24 holder (50200401)
its two openings, one vertical (24 × 35 mm, 0.94″ × 1.38″) and one
horizontal (35 × 24 mm, 1.38″ × 0.94″), as the holder sheet; Settings >
Holders shows both.

## 2026-11-19: part K planned (offset 62, zoom 100 %)

docs/test-session.md part K and the guide (`--part K`, steps 42-50,
essai-N): FlexColor's zoom at 100 %, one 0.50 × 0.50 cm frame untouched
at 3 200, 2 000, 1 000 and 600 ppi, then moved twice by one preview pixel
at 3 200 ppi and read again at 600 ppi. Part H could not tell whether
offset 62 follows FlexColor's own frame coordinates or the window's
lines (zoom 160 %, two resolutions). To be captured before the
recalibration of 2026-11-20 if possible.

## 2026-11-19: real scan stopped at 16 971; focus position range widened

A real scan (X1 Scan, 2 000 ppi, log x1scan-scan-121232, outside the
repository) stopped before the window of the 400-line step: position read
16 971, the rule then accepted 16 651 ± 256. FlexColor itself had measured
16 907 and 16 971 there (essai-F, 2026-11-18), and our real scans 16 843
and 16 779 (2026-11-18). The rule came from the capture of 2026-11-17
alone. User's decision: accept 16 651, 16 907 and 16 971
(`scan-sequence-2000ppi*.json`) ± 256: 16 395 to 17 227
(`ScanScript.focusPositionRange`); the value sent is that position,
so it is bounded the same way; the check after the window is unchanged
(± 256 around the position sent). The guard accepts the same range.
Tested on the simulator with 16 971 (and 16 395, 17 227; 16 394 and
17 228 refused). CLAUDE.md rule 4 and decisions.md updated. Not tried on
the real X1 yet.

Positions read before that window in the captures, for reference: at
2 000 ppi, 16 651 (2026-11-17), 16 907 and 16 971 (essai-F); in part G
(essai-I, other frames) 16 843 five times, 16 907, and 16 331 for the
1.0 × 3.0 cm frame; other resolutions and holders: 4 907, 6 155 (twice),
7 691, 7 831, 8 081 (twice), 12 145, 24 203, 24 971 (in three captures:
the 3 200 ppi scan of 2026-11-17, essai-I, essai-L).

## 2026-11-19: part K captured (offset 62, zoom 100 %)

Done with the guide, 11:04-11:29, the last capture with the original
calibration. One frame left untouched gives offset 62 = 59 713 at 3 200,
2 000 and 1 000 ppi [confirmed], where the windows would have made them
differ by about 4: not the window's lines [confirmed], FlexColor's own
frame coordinates [hypothesis, strongly supported]. At 600 ppi it is 48
less (one 600 ppi output pixel; an output grid [hypothesis]), and the
moved frame 63 less, which that does not explain. From the window's values
alone the formula stays within −6 to +24 on all 37 focus windows: no
byte-for-byte formula. A tolerance limited to that field is proposed for
the user's decision (decisions.md). `ScanWindowRulesTests` now covers 31
scans; the lens model of offsets 54 / 58 holds for part K too.

## 2026-11-19: decision on offset 62

User's decision (decisions.md, "Offset 62 of the 400-line window"): a
future window calculator takes offset 62 from its own window (option A,
recomputable by the guard); 32 units are the validation criterion on
captured frames, at 600 ppi and above; no free frame below 600 ppi.

## 2026-11-19: InfoPlist.xcstrings, Xcode's form

Contrary to the entry above (the bundle names kept with
`extractionState: extracted_with_value` so that Xcode would leave the
file alone), Xcode removed that field from both names and the final
newline; values and translations are unchanged. The file is committed in
that form.

Reference scans made before the recalibration (IT8 target, outside the
repository, kept for docs/test-session.md part J): with FlexColor at
2 000 ppi (neutral settings twice, default settings once, FlexColor's
default frame), and with X1 Scan (twice a preview then the replayed scan
of the capture of 2026-11-17; one preview TIFF and two scan TIFFs kept).

## 2026-11-19: working rules

User's rules, now in CLAUDE.md: reports in a fixed form (decisions
waiting first, then the state, then a short detail; no wide tables);
documentation, journal and fixtures are pushed after one x1-reviewer pass
with no blocking item, while code that talks to the scanner still needs
the user's approval before push; one review pass for documentation, at
most two for that code; `docs/hypotheses.md` lists the open hypotheses
(first version); x1-reviewer plays devil's advocate on every new
[confirmed] conclusion.

## 2026-11-19: part K added to the post-recalibration check

docs/test-session.md J2 now runs part K again after the previews
(essai-N2, zoom 100 %), and J3 compares its windows with essai-N of
`scan-windows-2026-11-19.json`: offsets 54 / 58 and the focus positions
decide J4; offset 62 is noted only. The guide still writes `essai-N`
(its name is fixed in `guided-session.sh`); essai-N2 is the analysis name.

## 2026-11-19: window calculator, simulator only

`X1Geometry.ScanWindowCalculator` (docs/decisions.md, "Window
calculator"): 6×7, 600-3 200 ppi, constants in one set
"origine-2026-11-19". Family 1 (round trip, consistency only): offset 54
1 too high at O = 2 000, 2 880, 3 000. Family 2 (prediction across
resolutions): offset 14 up to 5 pixels, 18 and 22 by 1, and offset 62
43 to 53 units above FlexColor's at 600 ppi, beyond the 32 accepted. A
validation on the real X1 (target, frame asked against frame obtained)
is needed before any real use, after CLAUDE.md rule 4 is changed.
Open for the user: offset 14 in prediction, and whether 600 ppi stays
allowed given offset 62 there.

## 2026-11-19: window calculator v1, step 1 (library, simulator only)

User's decisions (docs/decisions.md, "Window calculator v1"): 6×7 only;
menu 1 000, 1 500, 2 000, 3 000, 3 200 ppi (600 left out: offset 62 there
43 to 53 units above FlexColor's in prediction; the 32 units stay the
criterion); focus by our own measure on the 400 lines plus a manual
correction in lines, the result always one of the 400 lines swept.

- `ScanWindowCalculator.imageWindow(_:focus:sharpestLine:correction:)`:
  with FlexColor's *i* it gives 54 / 58 of FlexColor's image window
  exactly in all 31 captured scans (*i* = 149 to 224).
- `ComputedWindowGuard` (X1Geometry, simulator only): offset 62 recomputed
  by option A, the 400-line window's other fields, 54 / 58 one of the
  positions swept, every other field of the image window unchanged by the
  step. It accepts the calculator's windows of the 28 6×7 scans and
  refuses each field the tests alter.
- Sharpness: `tools/decode/export_focus.py` exports the 400 lines of the
  36 captured scans that have them (essai-C to -N; essai-L session 5,
  cancelled, left out), and `FocusSweepReportTests` (X1_FOCUS_CHECK_DIR)
  compares our line with FlexColor's. Our − FlexColor, in lines:
  - all 36 scans: gradient energy max 47, mean |diff| 7.8; Laplacian
    variance 47, 8.4; normalised gradient energy 47, 8.2;
  - 29 scans of the 6×7 at the menu's resolutions: 31 / 6.6, 31 / 6.9,
    31 / 7.1; within 5 lines: 19, 18, 18 scans; within 10: 22, 21, 21.
  - The largest: essai-I 2 (600 ppi) −47, essai-N 4 (2 000 ppi) −31,
    essai-I 4 (1 500 ppi) −27; the three measures agree on most scans.
  No criterion chosen: the user's decision. Scans whose session has no
  calibration read use the last earlier one of the capture with the same
  width (essai-D 2, essai-I 2-4, the other holders).

User's decisions on that report (2026-11-19, decisions.md, "Window
calculator" and "Window calculator v1"):

- Sharpness: gradient energy is the provisional measure; no criterion,
  set after the recalibration. The report now gives, for each scan, each
  measure's score at FlexColor's line in % of the highest score of our
  curve. 29 6×7 scans at the menu's resolutions: lowest 60.0 / 59.4 /
  59.9 % (essai-I 4, 1 500 ppi), mean 95.1 / 93.8 / 95.1 %. Of the 36
  scans: 100 % on the four where the three measures agree with FlexColor
  (three of them in the 29); below 90 % with gradient energy:
  essai-I 2 (600 ppi, 69.0 %), essai-I 4 (60.0 %), essai-N 4 (88.1 %),
  N 5 (88.5 %), N 8 (85.9 %).
- Offset 14 in prediction: ±5 pixels, simulator only, provided the frame
  stays in the CCD; provisional, to be reviewed after part J (checked in
  family 2).
- Offsets 18, 22 and base 54 / 58 within 1: proposed, decided after part J.
- The "[confirmed]" of the calculator's rules is limited to the round
  trip for offsets 14, 18 and 22; option A's middle of the frame counted
  from offset 18 added to docs/hypotheses.md.
- The four open review suggestions are left for step 2.


## 2026-11-19: lot 1, layout and geometry (application, virtual X1)

Lot 1 of the application, from the user's brief (docs/decisions.md, "Lot 1:
layout and geometry" and "Lot 1: exposure indicator"). Five commits, A to E:
panel sections with summaries; orientation (exact turns and mirror) and the
recipe, with the raw scan kept as master and versions `_v1`, `_v2`… on
Export; the grid and a tool column with active tools only; the exposure
indicator on the preview's raw samples (provisional thresholds); crop
frame, proportions, fine angle, straightening rule, Lanczos-3 rendering.
Nothing sent to the scanner changed: the scan sequences, guards and
transport are untouched. Tried on the virtual X1 only; the user tests the
application next, then on the real X1.

## 2026-11-19: lot 1, step F (user's decisions after the first report)

The crop frame now follows the image: exact quarter turns of the frame
(named ratio exchanged) and mirror (fine angle negated), tested for the
four turns, the mirror and back; a ratio chosen keeps the frame's
direction. CLAUDE.md gains a line on `X1ScanCore/Geometry`.

## 2026-11-19: lot 1 finished, waiting for the user's tests

Lot 1 is done: steps A to F, then the grid (one thin line, with a choice
of colour and opacity), the rule in the crop frame's colour and the noise
zones in violet, and a test of a custom ratio turning with the frame.
11 commits, not pushed, wait for the user's tests of the application (on
the virtual X1, then the real one). The order of the panel's sections is
not changed until the new organisation of the panel is approved.

## 2026-11-20: custom ratio, user's decision

A custom ratio keeps the width and height typed, whatever the frame's
direction, and turns with the frame at a quarter turn (13×18 becomes
18×13), as lot 1 does (docs/decisions.md, "Lot 1: layout and geometry").

## 2026-11-20: exposure patches on the virtual X1

The virtual X1's previews now show two patches, one clipped and one
dense, to try the exposure overlay (decisions.md, "Lot 1: exposure
indicator"). Asked where the thin violet line at the edge of the overlay
comes from: on the virtual X1, apart from the dense patch, the only
pixels near the noise floor are preview columns 0-4, at the left edge,
whose white reference is at the dark level in the calibration profile of
2026-11-12 (protocol.md §10) **[confirmed]**; that they are masked CCD
pixels is a **[hypothesis]**. A line elsewhere around the image would
not come from the overlay's zones.

## 2026-11-20: lot 1 fixes after the user's tests (virtual X1)

From the user's tests of lot 1 on the virtual X1 (decisions.md, "Lot 1:
layout and geometry"): crop handles stop at the image's edge and at a
smallest size, never flipping over; Done and Return go back to the tool
used before the crop mode, Esc puts back the recipe of the mode's start
(a running preview or scan is stopped first), and Reset gives the whole
image with no fine angle. Nothing sent to the scanner changed; not pushed.

User's answers the same day: Reset's free proportions and Esc putting
back the whole recipe (turns included) are confirmed; preview columns
0-4 are to be left out of the exposure measure once part J has checked
them on real captures; key X now works in crop mode wherever the focus
is in the main window, except while typing in a field.

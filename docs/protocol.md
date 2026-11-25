# Flextight X1 protocol

Status of each statement:
**[confirmed]** observed on a real X1 (captures of 2026-11-12, FlexColor 4.8.13
Mac on macOS 10.14 Mojave) or reproduced with our own tools;
**[hypothesis]** plausible interpretation, not yet proven.

Multi-byte values: CDB fields are big-endian (SCSI convention). Data
**inside vendor pages and parameter blocks is little-endian**, unless noted.

Every capture described here was made up to 2026-11-19, with the X1's
original calibration (a recalibration was planned for 2026-11-20;
docs/journal.md). Values that come from the calibration may differ after it.

## 1. Transport

- FireWire 400 device (S400, even on a FireWire 800 bus). **[confirmed]**
- IEEE 1394 IDs: vendor 0x305F, model 0x1F40. Unit spec 0x609E, command set
  0x104D8: the standard T10 values for **SCSI over SBP-2**. Nothing
  proprietary in the transport. **[confirmed]**
- macOS publishes it as a SCSI peripheral of type 6 (scanner) with
  `SCSITaskDeviceCategory = SCSITaskUserClientDevice`. No system driver claims
  it, so any program can open it with Apple's public **SCSITaskUserClient**
  API (`SCSITaskLib`). This is what FlexColor does. **[confirmed]**
- Only one client at a time. If another program has the device open,
  `IOCreatePlugInInterfaceForService` returns `0xE00002BE`
  (`kIOReturnNoResources`). FlexColor then shows an alert with an empty
  reason ("Impossible de terminer votre requête à cause de ."). **[confirmed]**

## 2. Firmware

The X1 boots on firmware stored in its own flash memory. Cold, without any
host software, it answers INQUIRY with its real identity and TEST UNIT READY
with GOOD. During initialisation and preview, FlexColor sends **no firmware,
FPGA or microcode download** (no WRITE BUFFER, no 0xD0). **[confirmed]**

(Older SCSI Flextights such as the Precision II need their microcode uploaded
at every power-up; the X1 does not.)

## 3. CDB layout used by FlexColor

- Groups 0 and 6 (opcodes 0x00-0x1F, 0xC0-0xDF): 6 bytes
  `[op, p1>>16, p1>>8, p1, len, 0]`
- Other groups: 10 bytes `[op, 0, p1 (BE32), len (BE24), 0]`

## 4. Commands

| Op | Name | Dir | Bytes | Notes |
|---|---|---|---|---|
| 0x12 | INQUIRY | in | 96 | `Imacon` / `Flextight X1` / `R185`. Bytes 36-95 are zero. **[confirmed]** |
| 0x00 | TEST UNIT READY | - | 0 | GOOD when idle. **[confirmed]** |
| 0x03 | REQUEST SENSE | in | 18 | Fixed format. **[confirmed]** |
| 0x5A | MODE SENSE(10) | in | 12-100 | Vendor pages 0x20, 0x21, 0x23, 0x24 (scans only), 0x25, 0x26, 0x27, 0x28 and 0x29 (the only ones seen), CDB `5a 00 PP 01 00 00 00 LL LL 00`. See §5. **[confirmed]** |
| 0x4D | LOG SENSE(10) | in | 52 | Vendor page 0x30, CDB `4d 00 30 00 00 00 00 00 34 00`. See §6. **[confirmed]** |
| 0xEE | read register | in | 1 | CDB `ee 00 00 00 01 AA 00 00 01 00`, AA = 0x04-0x19. Polled continuously. **[confirmed]** |
| 0xD3 | status / sensors | in | 2 | `00 0e` at rest, other values during activity. Possibly the scan button plus sensors. **[hypothesis]** |
| 0xDF | scanner state | in | 2 | See §7. **[confirmed]** |
| 0xD2 | ? | - | 0 | `d2 00 00 01 00 00`, once at start-up. Effect unknown. |
| 0xCF | session start / end | - | 0 | `cf 00 01 80 00 00` before a preview, `cf 00 02 80 00 00` after. **[hypothesis]** |
| 0xF0 | set mode | out | 2 | CDB `f0 00 A B C D 00 00 02 00`, data `00 00`. See §8. |
| 0x24 | SET WINDOW | out | 68 | See §9. |
| 0xE4 | CCD exposure | out | 12 | `05 04 10 00 05 04 20 00 05 04 30 00`: three LE16 values (0x0405) followed by a channel id 0x10/0x20/0x30 (R/G/B). **[hypothesis]** |
| 0xE1 | ? | in | 4 | Read once during calibration (`04 c5 ff ff`). |
| 0x1B | SCAN | in | 2 | `1b 00 00 01 01 00`, returns `00 00`. Starts the acquisition. **[confirmed]** Before the image of a scan (not a preview), also `1b 00 08 06 01 00`, returns `00 00`, followed by 400 one-line reads (§12). **[confirmed]** |
| 0x28 | READ(10) | in | n | See §10. **[confirmed]** |
| 0xDB | stop | - | 0 | `db 00 00 00 00 00`, end of scan. **[confirmed]** |

Not used by FlexColor on the X1 during initialisation and preview: 0xE0
(motor), 0x55 (MODE SELECT), 0x3B (WRITE BUFFER), 0xD0, READ BUFFER 0x3C.
READ BUFFER with buffer id 0xD8 returns ABORTED COMMAND (sense key 0xB) on the
X1: it belongs to other models. The firmware drives the motors itself.

Holder identification: the X1 may be able to identify the inserted film
holder (a commercial Flextight application advertises this feature for
Flextight scanners; nothing yet shows it on the X1 in particular). No dedicated command seen; 0xD3, page
0x27 and the 0xEE registers, whose meaning is unknown, should be compared
with different holders inserted (read-only, `tools/x1probe`). **[hypothesis]**
The holder used for the captures of 2026-11-12 was the 6×7, reference
50200403 (reported by the user on 2026-11-16).
In the capture right after power-on (2026-11-16, same holder), 0xD3 leaves
`00 0e` after the initialisation (seq 224) and alternates between `00 00`,
`00 c6` and `00 d9` until just before the session start (seq 265), around
the page 0x28 read (seq 259); FlexColor polls it about 40 times there, then
it reads `00 0e` again. **[confirmed]** 0xD3 may report the holder being
inserted and drawn in, and FlexColor may have been waiting for it.
**[hypothesis]**

Holder reference: the X1 might report the **reference number** of the
inserted holder: a commercial Flextight application displays "6×7
[50200420]" (an 8-digit Hasselblad
reference; the 6×7 holder of the compatibility table is 50200403, so the
number shown may belong to another variant). To check at the next session:
note the reference written on the holder used, and look for it (decimal,
hex or BCD) in the read-only responses (0xD3, page 0x27, 0xEE registers)
and in the captures. **[hypothesis]**

Since 2026-11-18 (§13): FlexColor reads a binary code on the holder's
leading edge in one CCD line, different for each of the holders
tried (seven in that capture, eight with the 6×7 later). **[confirmed]** Across those eight sessions every other non-image
response is the same whatever the holder (INQUIRY, pages 0x21, 0x23,
0x25, 0x26, 0x27, 0x29, log page 0x30, 0xEE registers 0x04-0x19; 0xE1
always `04 c5 ff ff`; 0xD3 nothing tied to the holder); only page 0x20's
position varies. **[confirmed]** So the X1 itself reports no holder and
FlexColor decodes the code in software. **[hypothesis]**, strongly
supported.

## 5. Vendor mode pages

Standard MODE SENSE(10) header (8 bytes, no block descriptor), then page code
and page length.

| Page | Length | Content |
|---|---|---|
| 0x20 | 22 | **Scan status**, see below. Read before every image block. |
| 0x21 | 80 | Many 16-bit values around 0x17xx: calibration table (focus / optics / CCD positions?). **[hypothesis]** |
| 0x23 | 49 | Twelve LE32 values, often round (980 000, 816 000, 514 000…): motor positions or travel lengths. **[hypothesis]** |
| 0x25 | 12 | **Not static.** Byte 21 of the response changes over time: 0x1b then 0x1c a few minutes apart, and 0x1c / 0x1d alternating within one preview, going back and forth. **[confirmed]** A value that goes down again points to a sensor reading (temperature?) rather than a clock; it is not a firmware date. **[hypothesis]** Bytes 12-16 (`01 23 0f 0a 03`) stay constant; their meaning is unknown. |
| 0x26 | 44 | **Identity**: 10-byte field (dashes when unset), then the serial number in ASCII (`FX1…`). This is where FlexColor gets the serial number. **[confirmed]** |
| 0x24 | 24 | Read once per scan (32 bytes requested), just before the window of the 400-line step (§12; a page 0x20 read comes between them), never in a preview: `1b 00 00 00 00 00 00 00 24 18 00 01 00 6e 04 01 00 ab 10 01 00 ab 10 01 00 00 02 01 00 01 00 01`, the same in the three scans of 2026-11-17 (1 000, 2 000, 3 200 ppi). **[confirmed]** Meaning unknown. In `CommandPolicy.readOnly` since 2026-11-17 (docs/decisions.md). |
| 0x27 | 9 | Unknown. |
| 0x28 | 18 | Read once (30 bytes requested), only in the capture right after power-on of 2026-11-16, just before the session start: `15 00 00 00 00 00 00 00 28 12 00 58 02 00 00`, 14 × `ff`, `00`. **[confirmed]** Not read in the capture right after power-on of 2026-11-17, nor in any warm capture: not needed for the sequence after power-on. **[confirmed]** Meaning unknown; what makes FlexColor read it is unknown. Not in `CommandPolicy.readOnly`; no longer sent by our cold sequence (docs/decisions.md, 2026-11-17). |
| 0x29 | 1 | Unknown (`07`). |

**Page 0x20 (scan status)** **[confirmed unless noted]**
Offsets from the start of the 34-byte response.
- bytes 19-24: three LE16 values, one per channel? In the capture (after
  several previews) 1 936 / 1 846 / 1 891; after power-on 2 048 / 2 048 /
  2 048, the middle of a 12-bit scale. Per-channel calibration values (lamp
  or CCD gain/offset). **[hypothesis]** They do not change during the
  captured calibration (the same from the first read to the last), so they
  were set earlier, or by something else.
- bytes 27-28 (LE16): a **measured position**.
  FlexColor writes a target position into the scan window (§9, offset 50),
  the scanner reports the position reached (e.g. target 25 000 → 24 971,
  target 9 000 → 8 971), and FlexColor may send the measured value back in
  the next window. Focus or optics positioning. **[hypothesis]**
- **Values after power-on** (test of 2026-11-16, first read after
  `CF 00 01 80`, X1 just switched on): bytes 19-24 = 2 048 × 3, bytes 27-28
  = 8 203, bytes 31-32 = 0. The capture, made after several previews without
  a restart, had 1 936 / 1 846 / 1 891, 6 155 and 824 at the same point.
  **[confirmed]**
  That first read shows the state left by earlier use (824: the lines of the
  previous preview; 6 155: its last position), not a new measurement.
  **[hypothesis]** The second read, after the first calibration windows
  (target 0), already differs (25 867, and 25 803 in another capture)
  without any position request: the scanner moved or repositioned itself
  during calibration, so that read is probably a measurement.
  **[hypothesis]**
  The captures of 2026-11-17 support it: the first read of the session
  after a scan shows that scan's state. After the 2 000 ppi scan (window of
  1 065 lines, last position 16 651) the next session starts with position
  16 651 and 1 066 lines; after the 1 000 ppi scan (582 lines), with 583
  lines. **[confirmed]**
- bytes 31-32 (LE16): **number of lines acquired** since SCAN. Increases
  during the scan. In the capture of 2026-11-12, FlexColor reads page 0x20
  once before each 20-line READ, and in 40 of the 41 cases the READ asks
  for lines the counter does not announce yet (e.g. 37 acquired, lines up
  to 43 requested); the counter is never below the lines already delivered
  (4 to 22 ahead). The last value read is 808, before the last READ; 822
  lines are read in all (3 single lines, 40 × 20, 1 × 19). **[confirmed]**
  In every capture (7 files, 9 image phases: previews and scans at 1 000,
  2 000 and 3 200 ppi) the counter never goes back between
  `1b 00 00 01 01 00` and the next `DB` (up to 2 062 at 3 200 ppi)
  **[confirmed]**. Values read outside that phase **[confirmed]**: 0, 2,
  then 11 at the two reads just before each preview's image SCAN (and at
  the two reads of a scan's white and black references, after the 400-line
  step at 2 000 ppi, before it at 1 000 and 3 200 ppi); 824, 583 or 1 066
  at the start of a session; 824 right after a preview's `DB`. On the real
  X1 (2026-11-18) the two reads of the scan's references gave 11, then 10
  **[confirmed]**. What the counter means outside the image phase (for
  instance the last lines of the previous run at the start of a session)
  is a **[hypothesis]**.
  The scanner then holds a READ until its lines exist. **[hypothesis]**
  (The READs after SCAN are asynchronous in FlexColor; the capture has no
  timing for them.)

## 6. Log page 0x30 (usage counters)

Seven LE32 values after the 4-byte header. One of them increases by exactly 1
per preview (about 6 950 on our unit): **total scan count**. Two others
increase with time (operating or lamp hours?). **[hypothesis]**

Observation of 2026-11-16 (read-only, on the development Mac through
ASFireWire): counters 1 and 6 both rose by 4 between 12:11 and 12:15, about
1 per minute, so probably **minutes of operation** (power on, or lamp);
counter 3 is the **number of scans**. **[hypothesis]**

## 7. Scanner state (0xDF)

| Value | Meaning |
|---|---|
| `00 00` | ready |
| `08 01` | busy (after F0, SCAN, stop): mechanical movement **[hypothesis]** |
| `08 40` | busy, other phase, often follows `08 01` |
| `08 02`, `08 03`, `08 06`, `08 07` | busy. Right after power-on (2026-11-16): after the first `F0` FlexColor read `08 07`, `08 06`, `08 02`, `08 06`, `08 40`, then `00 00`; `08 03` after the first `F0 01 01 01 01`. In warm scan sessions (2026-11-17), `08 06` and `08 02` also follow the SCAN commands (§12). **[confirmed]** |
| `08 80` | busy, seen in two captures of 2026-11-17, each time after `08 01` and polled many times in a row (69 and 96 reads), then `08 40`, `00 00` **[confirmed]**: after the first `f0 00 01 01 01 01` of the warm preview captured before the 2 000 ppi scan (seq 325), and after the `f0 00 01 01 01 01` of the 3 200 ppi scan session (seq 809, the step of seq 876 at 2 000 ppi). Accepted only in the warm preview's wait (`PreviewStep.alsoBusy`); not in the 2 000 ppi scan, whose capture does not show it at that step (there: `08 07`, `08 03`, `08 02`, `08 40`, `00 00`) |
| `08 04` | busy **[confirmed]**: 1 000 ppi scan session, after its first `f0 00 01 01 01 01` (seq 803; `08 06`, `08 04`, `08 40`, `00 00`), a step the 2 000 ppi scan does not have; and in the holder previews of 2026-11-18 (`tests/fixtures/holders/`, 4×5, 6×9 and 6×6 / 6×4.5 again), in the wait after `f0 00 01 01 01 01`, between `08 01` and `08 40`. Not accepted anywhere: we run neither |
| `08 05` | busy **[confirmed]**: holder previews of 2026-11-18 (6×9, 24×36×4, 6×6 / 6×4.5 again), in the wait after `f0 00 01 01 01 01`, right after `08 07` and before `08 01`. Not accepted anywhere: we run none of those sequences |
| `08 00` | seen three times on 2026-11-18 **[confirmed]**. Twice on the real X1 with our runner: first state after the cold preview's final `DB`, where every FlexColor capture shows `08 01` then `00 00` (the runner then stopped and sent its emergency `DB`; the X1 answered `08 01`, then `00 00`; that `08 00` ends by itself, without that second `DB`, is a **[hypothesis]**); and in the wait after the first `f0 00 01 01 01 01` of a cold preview (step 81): `08 07`, `08 03`, `08 01` ×6, `08 00`. Once in a FlexColor capture (`preview-sequence-warm-5.json`, seq 336, wait after the `f0 00 01 01 01 01` of seq 327): `08 01` ×8, `08 00`, `08 40`, `00 00`; FlexColor went on polling. Accepted as busy after a final or emergency `DB`, and in every wait right after an accepted `08 xx` state (below) |
| `00 01` | seen once right after `1b 00 00 01 01 00`; FlexColor starts reading image lines on this value **[confirmed]** |
| `00 06` | seen once right after `1b 00 08 06 01 00` (the 400-line step of a scan, §12), after `08 06` / `08 02` / `08 01`; FlexColor starts its one-line reads on this value. After that step's `DB`, a single `00 00`, then the next window. **[confirmed]** (three scans) |

Our own preview of 2026-11-16 on the real X1 (sequence right after
power-on, journal) saw the same busy states, `08 01`, `08 02`, `08 03`,
`08 06`, `08 07` and `08 40`, then `00 00`, with every status 0x00
**[confirmed]**.

The global list of busy states, accepted in every wait, is `08 01`,
`08 02`, `08 03`, `08 06`, `08 07` and `08 40`. Busy is **[confirmed]** for
these and for `08 80` and `08 04` as well: FlexColor went on polling until
`00 00` (or `00 01` after SCAN) each time. `08 80` and `08 04` are not in
the global list: each is accepted only in a wait where a capture of the
script we run shows it (table above). `08 00`
is accepted as busy (user's decisions, 2026-11-18):

- in the wait after the final `DB` of the preview or of the scan, and
  after the emergency `DB`, even as the first state read;
- in every wait, preview and scan, when the state read just before in
  that wait was an accepted `08 xx` state other than `08 00` (the global
  list, or `08 80` where it is accepted). In any other wait than the one
  after a final or emergency `DB`, `08 00` read first, or right after
  another `08 00` (never seen), still stops the run; alternating `08 01`,
  `08 00`, `08 01`… is accepted until the 120 s limit. `08 80` (in the
  scan) and `08 04` stay refused.

**[hypothesis]**: the first byte `08` means busy and the second byte the
activity in progress (in the holder previews `08 04` and `08 05` also
appear briefly between other busy states, §7 table); `08 00` would be a short transition between two
activities, which FlexColor, polling more slowly, never caught. The
meaning of the low byte is otherwise unknown.

Our polling: one 0xDF read, then a pause of 100 ms
(`PreviewConfiguration.pollInterval`) before the next, so a little more
than 100 ms between two reads; at most 120 s per wait (`stateTimeout`),
then the run stops. FlexColor's interval is not known (the captures have
no timestamps).

FlexColor polls 0xDF after most actions and waits for `00 00` before the next
step, except after SCAN, where it goes on as soon as it reads `00 01`.
**[confirmed]**

## 8. Mode command 0xF0

Four flags A B C D in the CDB. Sequence seen during a preview:
`00 00 01 01`, `00 01 01 01`, `00 00 00 01`, `00 02 00 01`, `01 01 01 01`,
`01 01 00 01`, `01 00 00 01`. White calibration lines are read after
`01 01 00 01`, dark lines after `01 00 00 01`. The two differ only in **B**:
B = 0 seems to close the light path (shutter or lamp). **[hypothesis]**

## 9. SET WINDOW (0x24), 68 bytes

CDB `24 00 00 00 00 00 00 00 44 00`. Standard 8-byte header (bytes 6-7 =
descriptor length 0x003C, big-endian), then a vendor descriptor with
little-endian fields:

| Offset | Size | Calibration | Preview | Meaning |
|---|---|---|---|---|
| 10 | 4 | 32 000 000 or 8 000 000 | 2 666 666 | Step / speed ratio. Preview = 8 000 000 / 3, and preview pixels are about 3 times longer than wide. **[hypothesis]** |
| 22 | 2 | 7 992 | 1 998 | Pixels per line (7 992 = full CCD, 1 998 = 7 992 / 4). **[confirmed]** |
| 26 | 2 | 2 or 3 | 823 | Number of lines (preview); mode during calibration. |
| 48 | 1 | 1 | 1 | ? |
| 49 | 1 | 1 | 4 | Horizontal binning factor? **[hypothesis]** |
| 50 | 2 | 0, 25 000, 9 000, 8 971 | 0, 6 250 | Target position (see page 0x20); bytes 52-53 are always 0. |
| 54 | 4 | 454 612 | 454 612 | Start position on the drum? |
| 58 | 4 | 856 631 | 856 631 | End position on the drum? |
| 62 | 4 | 15 500 | 15 500 | Drum position of the focus line in the 400-line window? (§9; LE32: above 65 535 in some) |

**Scan windows** (captures of 2026-11-17: one scan each at 1 000, 2 000 and
3 200 ppi of a small frame; `tests/fixtures/scan-sequence-*.json`). Lists
of three values are in capture order: 2 000, 1 000 and 3 200 ppi.

- **Offset 10 = resolution × 50 000 / 3** (truncated): 16 666 666 at
  1 000 ppi, 33 333 333 at 2 000 ppi, 53 333 333 at 3 200 ppi.
  **[confirmed]** (three resolutions, each with FlexColor's TIFF). The
  formula would make the preview's 2 666 666 160 ppi, but preview lines
  need an aspect factor of 3 (§10), not the 5/3 of the scans:
  **[hypothesis]**. The 400-line window of every scan (§12) has 21 674 665
  whatever the scan resolution (**[confirmed]**); by the formula,
  1 300.48 ppi (**[hypothesis]**).
- Offset 14 (LE16): first pixel of the frame across the CCD, in pixels at
  the scan resolution (2 005, 354, 722): image column *i* is calibration
  column margin + offset 14 + *i* (§10). **[confirmed]** (the flat field is
  right only with that mapping).
- Offset 18 (LE16): 770, 456, 1 145; 0 in the 400-line window. Start of the
  frame along the drum? **[hypothesis]**
- Offset 22: pixels per line = width of the frame in pixels (609, 345,
  1 148), the same as FlexColor's TIFF. **[confirmed]**
- Offset 26: lines read + 1 (1 065, 582, 2 070; §10). 401 in the
  400-line window (400 lines read). **[confirmed]**
- Byte 49: 1 at 2 000 and 3 200 ppi, 3 at 1 000 ppi, 4 in the preview:
  horizontal binning. **[hypothesis]**, consistent with the margins (§10).
- Offset 50 in the 400-line window: the position just read on page 0x20
  (16 651, 8 081, 24 971). **[confirmed]** Offset 62 there: 26 560, 28 259,
  27 156 (15 500 elsewhere): the drum position of the focus line, below
  **[hypothesis]**.
- Offsets 54 and 58: in the 400-line window 10 000 more than in the windows
  before it; in the image window (and the white and black reference window
  of the 2 000 ppi order) both change by the same multiple of 50, between
  −1 200 and +2 550 in the 20 scans captured (2026-11-17 and -18).
  **[confirmed]** Consistent with a focus value swept from base + 10 000
  down in 400 steps of 50 (one per line), FlexColor keeping base + 10 000
  − 50 × *i* for the line *i* it finds sharpest (*i* = 149 to 224 here).
  **[hypothesis]** In all 31 scans of `scan-windows-2026-11-18.json` and
  `-19.json`, the image window after the step is base + 10 000 − 50 × *i*
  for 54 and 58 with the same whole *i*, 149 to 224 **[confirmed]**
  (`ScanWindowCalculatorTests`). FlexColor's measure is not known. Three
  simple measures on the flat-fielded green channel (`X1Image.FocusSweep`:
  gradient energy, variance of the 1-D Laplacian, gradient energy over the
  squared mean) give a line 0 to 47 lines from that *i* on the 36 captured
  scans with 400 lines (mean of the absolute difference 7.8 to 8.4 lines);
  on the 29 scans of the 6×7 at 1 000-3 200 ppi, 0 to 31 (6.6 to 7.1)
  **[confirmed]** for those captures, with `tools/decode/export_focus.py`'s
  choice of calibration read (2026-11-19 journal). Which measure
  is closest to FlexColor's, and whether the difference matters for the
  image: **[hypothesis]**, docs/hypotheses.md. Page
  0x24, read before each 400-line step, is identical in all the scans, so
  it is not the source.
- The base values of offsets 54 and 58 (windows before the 400-line step)
  are optical settings: see "Window rules" below.
- Offset 62 in the 400-line window (15 500 elsewhere): byte 64 is 1 in
  three windows of 2026-11-18, 0 in all others **[confirmed]**; read as
  LE32 like offsets 54 and 58, they give 87 177, 97 134 and 85 760
  **[hypothesis]**, strongly supported (the values then continue those of
  the other windows). Values: 26 560 to 28 259 on 2026-11-17, 26 877 for
  the frame scanned twice on the morning of 2026-11-18, 30 146 to 97 134 in
  the afternoon scans (6×7 frames from 30 146, top, to 87 177, bottom;
  58 215 to 64 667 for the others; 24×36×4 97 134, 4×5 85 760, 24×36
  32 734). **[confirmed]** Mean level, density, contrast, gradients and raw
  maximum of the flat-fielded preview over each frame give |r| ≤ 0.6 with
  it on the twelve 6×7 scans of the afternoon (seven distinct frames; computed outside the
  repository from the raw captures) **[confirmed]**: it does not seem to
  come from the preview's content **[hypothesis]**.
  It follows the position of the frame along the drum:
  62 ≈ 15 500 + 28 800 × (offset 18 + (offset 26 − 2 × gap − 2) ÷ 2) ÷
  (ratio ÷ 10 000), the middle of the frame's lines without the priming
  lines (§10), in inches at the scan's line pitch, reproduces all 25
  windows (24 distinct scans of 2026-11-17 to -19 and the one cancelled;
  four holders, 600 to 3 200 ppi)
  within −6 to +21 **[confirmed]** for those values; `ScanWindowRulesTests`
  checks it on the 23 scans of 2026-11-18 and -19. So offset 62
  is the drum position of the line where the focus is measured (the
  400-line step reads the middle of the frame, §12), 15 500 being line 0
  of every other window, at 28 800 per inch (one unit = 1/28 800 in ≈
  0.88 µm; 15 500 ≈ 13.67 mm from position 0 of offset 62). **[hypothesis]**, strongly
  supported.

  **Part H (2026-11-19, essai-L)**. FlexColor's zoom was at 160 %: it
  scanned at PPP × 1.6 (3 200 ppi for "2 000", 960 for "600";
  `ScanWindowRulesTests`), so the frame left untouched was read twice at
  3 200 ppi and once at 960 ppi, with 59 542, 59 542 and 59 515.
  **[confirmed]** Offset 62 depends on the resolution, so it is not one
  fixed position of the frame. **[confirmed]** Whether it follows the
  window or FlexColor's own rounded coordinates is not known: from the
  windows the two values should differ by 14.4, they differ by 27.
  **[hypothesis]** No formula of the window's values
  alone gives it exactly: of the forms tried (the middle at offset 18 +
  offset 26 ÷ 2 − gap − 1, − 1.5 or − 2 lines, with truncation, rounding or
  none), the best matches 4 of the 25 windows, and the others stay within
  about ±10 (−9 to +12 with − 1.5). A free fit gives 15 500 (±1), 1.000 ×
  offset 18, 0.500 × offset 26, −1.03 to −1.04 × gap and −1.9 lines
  (residuals within 8). **[confirmed]** That the form is right and the
  remainder is rounding: **[hypothesis]**.
  FlexColor probably computes it from its own frame coordinates, which it
  also rounds to the window's lines (at 960 ppi it may also have moved the
  frame to its output pixel grid). **[hypothesis]** A calculator can give
  it within about ±12 units (0.01 mm), not byte for byte.

  **Part K (2026-11-19, essai-N, zoom 100 %)**. One 0.50 × 0.50 cm frame
  left untouched gives 59 713 at 3 200, 2 000 (twice) and 1 000 ppi, and
  59 665 at 600 ppi; moved twice by one press of the down arrow (22 and 16 lines, less than
  one preview pixel; test-session K1), 59 839 and 59 920 at
  3 200 ppi, and that last frame 59 857 at 600 ppi. **[confirmed]** So
  offset 62 is the same at 3 200, 2 000 and 1 000 ppi **[confirmed]** and
  different at 600 ppi. It does not follow the window's lines: from the
  windows, 3 200 and 2 000 / 1 000 ppi should differ by about 4 units, and
  they are equal **[confirmed]** (a difference of 4 units: consistent, not
  large). That FlexColor computes it from its own frame coordinates:
  **[hypothesis]**, strongly supported. At 600 ppi the untouched frame is
  48 lower, one 600 ppi output pixel (28 800 ÷ 600): FlexColor may move the
  frame to its output pixel grid at coarse resolutions **[hypothesis]**;
  part H fits it (27 between 3 200 and 960 ppi with the zoom at 160 %, under
  one output pixel, 30 units on the film). But the moved frame is 63 lower
  at 600 ppi (59 920 → 59 857), more than one output pixel, which a simple
  move to that grid does not explain **[confirmed]**; the cause is not
  known. Those coordinates are not in the window: from the window's values alone, the formula above
  stays within −6 to +24 of FlexColor's value on all 37 focus windows
  captured (2026-11-17 to -19), the largest at 600 ppi. **[confirmed]** A
  window calculator, which has its own frame, gets offset 62 from it; it
  cannot reproduce FlexColor's value for the same frame byte for byte
  (docs/decisions.md, proposal of 2026-11-19).

**Window rules** (2026-11-18: 12 scans with the 6×7 holder in one
FlexColor run, the same 1.0 × 1.0 cm frame at 600, 1 000, 1 500, 2 000,
3 000 and 3 200 ppi, the same size near each edge, and a 1.0 × 3.0 cm
frame; one 1 000 ppi scan each with the 24×36×4, 24×36 and 4×5 holders;
`tests/fixtures/scan-windows-2026-11-18.json`). **[confirmed]** for those
values; as rules for other frames and resolutions, **[hypothesis]**.
`ScanWindowRulesTests` checks on the 15 scans: the image window's ratio,
binning, width and lines, the 400-line window and its offset 62, the focus correction, the
order of the references, the 6×7 model of 54 / 58 at the four optical
resolutions of essai-I, and the constant frame position (spread only) of
the 6×7 centred frames. The other statements below were checked by hand
on the captures.

- **Holder factor** *f* (calibration ratio ÷ resolution ÷ 10 000): 6×7
  1.000, 24×36×4 0.977, 24×36 1.0245, 4×5 0.8855. The image window ratio
  (offset 10) is truncated resolution × *f* × 50 000 / 3. Binned scans
  start with a window of ratio resolution × *f* × 10 000.
- **Binning** (byte 49) = min(4, ⌊*M* ÷ resolution⌋), with *M* per holder.
  The scans only bound it: 3 000 to 3 999 for the 6×7, 4 000 or more for the
  24×36×4 and the 24×36, 2 000 to 2 999 for the 4×5 **[confirmed]**. A run
  starts with ratio 10 000 × 3 200 after the 6×7, 6×6 / 6×4.5, 6×6×2 and
  6×9, 10 000 × 6 300 after the 24×36×4 and 24×36×6, 10 000 × 2 040 after
  the 4×5 (§12), the X1's highest resolutions for those formats: *M* = 3 200,
  6 300 and 2 040 for them **[hypothesis]**. No run started after the
  24×36: its *M* is unknown (its preview optics fit *O* = 5 000, below). Optical resolution *O* =
  resolution × binning: 2 000 to 3 200 with the 6×7 holder, 4 000 for the
  35 mm holders at 1 000 ppi, 2 000 for the 4×5.
- **Width** (offset 22) = width of FlexColor's TIFF.
- **Lines** (offset 26) = ⌊TIFF height × 5 / 3⌋ + 2 × gap + 2, R/B gap =
  20, 10, 7, 5 lines at binning 1, 2, 3, 4 (round(20 ÷ binning)); §10.
- **Across the CCD** (offset 14), 6×7: the same centred frame at the six
  resolutions has its centre at offset 14 + width / 2 = 3 996 ÷ binning +
  *x* × resolution, with *x* = −0.129 in (±0.0012): CCD pixel 3 996 (the
  middle of 7 992) stays on the same point of the film whatever the
  optical resolution, and offset 14 counts pixels at the scan resolution
  from the first CCD pixel.
- **Along the drum** (offset 18), 6×7: offset 18 ÷ (ratio ÷ 10 000) is the
  same (1.4460 to 1.4472 in) at the six resolutions: offset 18 counts lines
  at the scan's line pitch, ratio ÷ 10 000 lines per inch (5/3 × the
  resolution); the preview window (ratio 2 666 666, 266.67 lines per inch,
  1 998 pixels at binning 4 and *O* = 3 200, 800 pixels per inch) fits the
  same rules. Mapped into the preview this way, the frames fall where
  FlexColor drew them on its preview (screenshots of steps 5 and 12,
  within about 2 preview pixels). The middle of that frame along the
  drum: offset 18 ÷ (ratio ÷ 10 000) + TIFF height ÷ resolution ÷ 2 =
  1.6427 to 1.6442 in at the six resolutions **[confirmed]**; that this is
  the middle of the frame (image lines starting at offset 18, not after
  the priming lines) **[hypothesis]**; the window
  calculator takes 1.644 in as its origin along the drum, a convention
  (the frame was centred by eye; docs/decisions.md, "Window calculator").
  With the other holders the origin along
  the drum is not known (one scan each).
- **54 / 58 before the 400-line step**, 6×7 holder: a function of *O* only.
  58 = 1 136 908 − 896 886 417 ÷ *O* and 54 = 1 094 694 − 896 148 801 ÷ *O*
  − 112.511 × *O* reproduce, within 1, the six values of *O* seen with
  that holder or at the start of a session (1 600, 2 000, 2 400, 2 656,
  3 000, 3 200); at 3 541 (start of the cold session of essai-K, §12) both
  are 1 000 below. A seventh value, not used for the fit, also matches
  within 1: *O* = 2 880 (960 ppi at binning 3, part H: 459 499 / 825 489).
  **[confirmed]** 58 linear in 1 / *O* and 54 in
  *O* and 1 / *O* is what a lens to film distance and a total track give
  for a thin lens at magnification ∝ *O*: offsets 54 and 58 move the CCD
  and the lens (zoom and focus). **[hypothesis]**, strongly supported. With
  the other holders the values differ (4×5 at *O* = 2 000: 389 424 / 630 478;
  24×36×4 and 24×36 at *O* = 4 000: 424 688 / 906 408 and 414 943 /
  918 048), by an amount not explained: the film plane is not at the same
  place. The **preview** windows of the other holders do fall on the 6×7
  model: 4×5 at *O* = 2 040, 24×36 at 5 000, 24×36×6 at 6 300 (within 6),
  24×36×4 1 000 below its 6 300. **[hypothesis]**: one lens model, and a
  holder-dependent change for scans only. A calculator can use only the
  observed (holder, *O*) pairs.
- **400-line window**: ratio 21 674 665, offset 14 and width of the image
  window, offset 18 = 0, 401 lines, binning of the image window, target =
  position read just before, 54 / 58 = base + 10 000, offset 62 above.
- **Order**: the white and black references come before the 400-line step
  when *O* ≥ 3 000 (8 scans, with those of 2026-11-17), after it when *O* ≤
  2 400 (12 scans).

## 10. READ(10) and image data

CDB `28 00 01 00 NN FF LL LL LL 00`:
NN = number of lines, FF = 01 for calibration reads and 00 for image reads,
LL = byte count (BE24) = NN × bytes per line. **[confirmed]**

Data format **[confirmed]**:
- **RGB interleaved, 16-bit little-endian**, full 16-bit range (up to ~58 000
  on an empty holder).
- Preview: 2 004 pixels per line (1 998 requested + 6), 12 024 bytes per line.
  Full CCD width for calibration: 7 992 pixels.
- Preview columns 0-4 (calibration profile of the 2026-11-12 preview,
  `tests/fixtures/preview-calibration-profile.json`): the white reference
  is at the dark level there (column 0: white 330 / 300 / 314, dark
  314 / 285 / 310); column 5 is about half-way (26 325 / 24 952 / 21 542),
  then about 50 000. **[confirmed]** on that capture. Like the scans' width
  margin below (6 extra pixels at binning 4, the first ones), they are
  probably masked or unlit CCD pixels, not image. **[hypothesis]** In the
  application they read as near the noise floor: the violet line at the
  left edge of the exposure overlay.
- Image reads are issued asynchronously by FlexColor (next read queued while
  the previous block is processed). Everything else is synchronous.

Corrections the host must apply **[confirmed on a preview]**:
1. **Flat field**: per column and channel, `(raw - dark) / (white - dark)`,
   with the white and dark lines read during calibration.
2. **Line gaps**: the three CCD rows are physically offset. At preview
   resolution, red leads green by one line and blue trails by one line.
3. **Aspect**: preview lines are about 3 times coarser along the drum than
   across it. A factor of 3 reproduces FlexColor's preview geometry; the
   exact physical ratio is **[hypothesis]** (§9).

`tools/decode/decode_preview.py` applies these steps and reproduces
FlexColor's preview geometry exactly (colour profile not applied).

**Scan data** (2026-11-17, 1 000, 2 000 and 3 200 ppi; decoded with
`tools/decode/decode_scan.py`) **[confirmed unless noted]**:

- **Width margin**: every line has 24 more pixels than the window asks for
  (633 for 609, 1 172 for 1 148; 8 016 for the full CCD's 7 992), 8 more at
  1 000 ppi (353 for 345; 2 672 for 2 664). The extra pixels come first and
  are dark in the image lines (level ~230-260, like the dark lines). In
  the white calibration lines the last few of them are lit (at 2 000 ppi,
  columns 20-23 about 460, 4 980, 45 000, 46 200; at 1 000 ppi column 7
  about 34 200), so they are not all masked pixels. **[confirmed]** Margin
  = 24 / binning, which also fits the preview (2 004 = 1 998 + 6, binning
  4). **[hypothesis]** (three binnings seen).
- **White and dark**: one full-width calibration read of 230 lines (23 ×
  10 lines, CDB byte 5 = 01) per scan: 50 white lines (~53 000), then 180
  dark ones (~250-300). Image column *i* uses calibration column margin +
  window offset 14 + *i*.
- **Priming lines**: after `1b 00 00 01 01 00`, FlexColor reads one line at
  a time 41 times (2 000 and 3 200 ppi) or 15 times (1 000 ppi), then
  20-line blocks. Priming = 2 × the R/B gap + 1.
- **R/B gap**: 20 lines at 2 000 and 3 200 ppi, 7 at 1 000 ppi (1 in the
  preview), in the same direction as the preview. The gap does not grow
  with the resolution between 2 000 and 3 200 ppi. **[confirmed]** Why is
  unknown.
- **Lines**: FlexColor reads 5/3 lines per line of its TIFF: 1 023 for 614,
  566 for 340, 2 028 for 1 217, that is floor(TIFF lines × 5/3), plus the
  priming lines. After R/B realignment, resampling by 3/5 gives FlexColor's
  geometry: correlation of log values with its TIFF 0.997-0.999 at 2 000
  and 3 200 ppi (R, G, B), 0.94-0.98 at 1 000 ppi. Same orientation, no
  flip. Why 1 000 ppi matches less well is unknown: excluding clipped
  pixels, or changing the gap, the resampling phase or the column offset,
  does not improve it.
- FlexColor's TIFF is not linear: against the flat-fielded data, its log
  values follow a slope of about 0.51-0.55 (a gamma near 1/2) with a
  residual of about 4 % (its curve and colour profile). Exact pixel values
  are therefore not reproduced; the geometry is.

## 11. Preview sequence (FlexColor 4.8.13)

Polling of 0xEE, 0xD3 and 0xDF omitted, except where the wait matters.

1. Initialisation: INQUIRY, MODE SENSE 0x26 0x27 0x25 0x21 0x29 0x23,
   LOG SENSE 0x30, `D2`.
2. `CF 00 01 80`, page 0x20.
3. Calibration, repeated with different windows and modes:
   `F0` → wait `DF = 00 00` → `24` → `E4` → page 0x20 → `28` (1 line,
   7 992 px) …; positioning loop via offset 50 of the window and page 0x20.
4. White and dark references at preview width: `F0 01 01 00 01` →
   5 × READ 10 lines (white); `F0 01 00 00 01` → 18 × READ 10 lines (dark).
5. Final window (§9, preview column), `1B` SCAN, wait for `DF`.
6. Loop: page 0x20 (line counter) → READ 20 lines without waiting for the
   counter (§5), until all lines are
   read (41 reads for 819 lines).
7. `DB` stop, wait `DF = 00 00`, `CF 00 02 80`.

With and without film in the holder, the sequence and the windows are
identical. Holder: 6×7, reference 50200403 (reported on 2026-11-16).

**Right after power-on** (capture of 2026-11-16, X1 just switched on, cold
lamp, same holder; `tests/fixtures/preview-sequence-cold.json`) the
sequence differs from the one above (made after several previews without a
restart). **[confirmed]**
- One more read before the session start: MODE SENSE page 0x28 (30 bytes).
- The first page 0x20 read gives 2 048 × 3 (bytes 19-24), position 8 203,
  0 lines.
- Calibration: the first windows have ratio 16 000 000 instead of
  32 000 000 (offset 10, LE32; first written here as 62 500 and 125 000,
  read one byte off) and
  other bytes 54-61 (`17 69 05 00 62 cb 08 00`); a window with target
  10 000 and one with target 0 come first, then `F0 00 00 01 01` (with the
  busy states of §7), page 0x27, the full-CCD windows, `E4`, `F0 00 01 01
  01`, two page 0x20 reads (14 219), the window with target 9 000…
- From the window with ratio 8 000 000 (preview-width calibration) to the
  end of session, the commands are the same as in the warm capture.
- 821 commands in all (766 warm), all with status 0x00.

**Choice between the two sequences** (captures of 2026-11-17 added:
`essai-A`, X1 just switched on, two previews in one FlexColor session, A1
then A2; `essai-B`, FlexColor restarted with the X1 still warm, one
preview; logs outside the repository; "outside polling" means without
0xEE, 0xD3 and 0xDF):

- In the four full captures (warm W of 2026-11-12, cold C of 2026-11-16,
  cold A1 and warm B of 2026-11-17), the commands outside polling are
  identical up to and including the first page 0x20 read after
  `CF 00 01 80` (39 commands), apart from C's page 0x28 read; they diverge
  at the next command (warm: `F0 00 00 00 01 01`; cold: the window with
  ratio 16 000 000). **[confirmed]**
- That page 0x20 read gives the power-on values (2 048 × 3, position
  8 203, 0 lines) before both cold sequences (C, A1), and values left by
  earlier use before the warm ones (W 1 936 / 1 846 / 1 891, B 1 921 /
  1 845 / 1 883, A2 1 911 / 1 845 / 1 883; position 6 155, 824 lines).
  **[confirmed]** A2's bytes 19-24 and position equal those of A1's last
  page 0x20 read (lines 824 against 808). **[confirmed]** The state left by
  the previous preview, not a new measurement (§5): **[hypothesis]**,
  strongly supported.
- Other responses also differ before the divergence (0xD3 polling, byte 21
  of page 0x25, log page 0x30), but page 0x20 is the only one that
  separates the cold runs from the warm ones in all five sessions: the
  0xD3 activity (`00 c6` before C, A1 and A2, and `00 d9` in C) also comes
  before A2, which is warm.
  **[confirmed]** FlexColor chooses the sequence from that page 0x20 read.
  **[hypothesis]**
- The three scan captures of the same day (§12) add six warm sessions
  (three previews, three scans): each first page 0x20 read shows values
  left by earlier use, none the power-on values, and none is followed by
  the cold calibration. **[confirmed]** Consistent with the rule above;
  still no second cold capture besides A1 and C.
- After values left by earlier use, FlexColor does not always send the
  warm capture's sequence. In the preview of the 2 000 ppi run (2026-11-17)
  it did, up to the second page 0x20 read of the session (the first
  measurement after the target-0 windows): that read gave 24 523 where
  every other warm session gave 25 739-25 995 (25 931, 25 995, 25 931 and
  25 931 in the four of 2026-11-18). FlexColor then read page
  0x20 again and did **not** send the window with target 25 000: it went
  on with the window with target 9 000. **[confirmed]** So the warm
  sequence also depends on that measurement. **[hypothesis]**: 24 523 is a
  state left by an earlier session. That preview was the first session of
  its FlexColor run; the run before it (B, a preview) ended about 15
  minutes earlier, and the first page 0x20 read of the session showed the
  usual 6 155 / 824, so nothing confirms it yet. Three more warm previews
  on 2026-11-18 (FlexColor restarted before each,
  `preview-sequence-warm-3.json` to `-5`) sent exactly the warm capture's
  commands (206 outside polling) and read 25 931, 25 995 and 25 931 before
  the window with target 25 000: the 24 523 case did not come back.
  **[confirmed]** Our runner checks that read (tolerance 256) and stops before
  the window with target 25 000 (docs/decisions.md).
- Page 0x28 is not part of the choice: A1 is identical to C without its
  page 0x28 read (207 commands outside polling). **[confirmed]** What makes
  FlexColor read it is still unknown. The uncalibrated state of page 0x20
  is ruled out (A1 has it without the read); the holder being inserted
  while FlexColor waited (the 0xD3 activity, §4) is weakened: A1 and A2
  show the same 0xD3 activity without a page 0x28 read. **[hypothesis]**
- B is identical, command for command (CDB, data_out, length; 206 outside
  polling, all status 0x00), to W. **[confirmed]**
  (`tests/fixtures/preview-sequence-warm-2.json`.)
- A second preview in the same FlexColor session (A2) is a third sequence,
  not a subset of the warm one: 168 commands outside polling from the
  session start (183 in W and B), with fewer full-CCD calibration steps
  (6 `F0`, 7 windows, 3 `E4` instead of 9, 12 and 5). Against W: 13
  commands (full-CCD windows with ratio 32 000 000, `E4`, `F0`, page
  0x20, two READs…) are replaced by a single window (ratio 8 000 000,
  1 998 pixels); one READ is replaced by a one-line READ of 12 024 bytes
  (`28 00 01 00 01 01 00 2e f8 00`); 3 commands are left out (the
  full-CCD window with ratio 8 000 000, an `E4`, `F0 00 01 01 01`).
  183 − 13 + 1 − 3 = 168. It also measures a position (6 059).
  **[confirmed]** (ratios first written here divided by 256, read one byte
  off.) FlexColor keeps part of the calibration of the first preview.
  **[hypothesis]** Since 2026-11-18 that window, that one-line read and
  6 059 are in the fixtures: sessions 2 to 8 of `tests/fixtures/holders/`
  start with the same structure (the window's ratio is inherited, §13), and
the one-line read is the holder code (§13). A2
  probably read the holder code. **[hypothesis]** (A2's commands not yet
  compared one by one with those sessions)
- Measured positions (page 0x20, bytes 27-28) differ between captures of
  the same sequence; the three differences observed are multiples of 64:
  64 (two warm captures of 2026-11-12), 128 (B against W, 25 739 / 25 867),
  192 (A1 against C, 14 027 / 14 219, twice). **[confirmed]** With the
  tolerance of 100 (docs/decisions.md), our runner would have stopped in
  A1: those two reads come after the window with target 10 000, so they are
  checked. B's difference is on the read before any window requests a
  position, which is not checked: B would have passed. **[confirmed]** (the
  runner's rule applied to the captured responses).

## 12. Scan sequence (FlexColor 4.8.13)

Captures of 2026-11-17 (`tests/fixtures/scan-sequence-1000ppi.json`,
`-2000ppi`, `-3200ppi`): X1 warm, in each FlexColor run one preview, then
one scan of a small frame (0.77 × 0.78 cm at 2 000 ppi, 0.88 × 0.86 cm at
1 000 ppi, 0.91 × 0.97 cm at 3 200 ppi) in RGB 16-bit, each in its own
session (`CF 00 01 80` … `CF 00 02 80`). All captured statuses 0x00 (the
asynchronous image reads have no captured status); no page 0x28 read.
**[confirmed]**

Every scan session starts like a warm preview session (same reads; first
page 0x20 with values left by earlier use, see §5 and §11), then:

1. **Calibration at the scan resolution**: windows at full CCD width
   (7 992 or 2 664 pixels), `E4`, `F0` modes, then the full-width white and
   dark read (230 lines, §10): the 50 white lines after
   `F0 00 01 01 00 01`, the 180 dark lines after `F0 00 01 00 00 01` (§8).
2. **400-line step** (focus, **[hypothesis]**, below): page 0x20, MODE
   SENSE page 0x24, page 0x20, a window with offset 10 = 21 674 665, 401
   lines and the measured position as target (§9),
   then `1b 00 08 06 01 00` and 400 one-line reads, then `DB`. These lines
   are not dark: they show the film, at the middle of the frame along the
   drum (after flat field, their mean profile best matches image line
   522 of 1 064, 284 of 581, 1 018 of 2 069, about 49 %; r = 0.87-0.996),
   nearly constant from line to line, and the
   sharpness of each line (mean difference between neighbouring pixels)
   rises to a single maximum near line 200 and falls again, in all three
   scans. **[confirmed]** A focus sweep: the scanner reads one line while
   moving the focus, and FlexColor picks the sharpest position.
   **[hypothesis]**, strongly supported.
3. **Image**: the window of the frame (resolution, offset 14, width,
   lines), `1b 00 00 01 01 00`, priming lines, 20-line blocks with a page
   0x20 read before each, a last shorter block, `DB`, `CF 00 02 80`.

The order of steps 1 and 2 is not fixed: at 1 000 and 3 200 ppi the
white/dark read comes before the 400-line step; at 2 000 ppi it comes after
it, with a single full-width window before the white/dark read (two at
3 200 ppi, with target 25 000). The 1 000 ppi
session also skips the `F0 00 00 00 01 01` that follows the first page
0x20 read in the others, and starts with a window of ratio 10 000 000,
binning 3. **[confirmed]** The captures of 2026-11-18 (§9, "Window rules")
explain both: every binned scan starts with a window of ratio resolution ×
holder factor × 10 000 (not a 600 ppi window), and the references come
first when the optical resolution is 3 000 or more (1 000 ppi at binning 3
and 3 200 ppi: 3 000 and 3 200; 2 000 ppi: 2 000). **[confirmed]** on 20
scans; the reason for that order is not known.

**Position around the 400-line step** (page 0x20, bytes 27-28): the
window of that step targets the position read just before it (16 651,
8 081, 24 971), and every later read of the session gives one constant
value: the target at 2 000 and 3 200 ppi, 83 below it at 1 000 ppi
(7 998 for 8 081). **[confirmed]** (three scans)

Unlike the preview, a scan cannot be replayed byte for byte from a capture
in general: the image window carries the frame (offsets 14, 18, 22, 26)
and the resolution, and the 400-line window carries the position measured
just before (offset 50) and values not explained yet (54, 58, 62).
**[confirmed]** for offset 50; **[hypothesis]** for the others.

**Two scans without a preview between them** (2026-11-18,
`scan-sequence-2000ppi-twice.json`: X1 switched on just before, a cold
preview, then two 2 000 ppi scans of the same frame, each in its own
session). FlexColor does everything again for the second scan: session
start, calibration at the scan resolution, 400-line step, white and black
references, image (594 commands outside polling each time). The two scan
sessions differ only in: the second has no `F0 00 00 00 01 01` after the
first page 0x20 read, and reads page 0x20 once more after the first
window; the target of the 400-line window (16 907, then 16 971: the
position read just before); offsets 54 and 58 of the windows after that
step (§9). **[confirmed]** Each scan here also has another frame than the
capture of 2026-11-17 (offset 14 = 2 043, 560 pixels, offset 26 = 938,
offset 18 = 870).

The cold preview of that capture (first page 0x20 read with the power-on
values) differs from `preview-sequence-cold.json` (without its page 0x28
read) in two ways only **[confirmed]**:

- the page 0x20 read after `F0 00 00 01 01 01` gave 25 675, and FlexColor
  then sent the window with target 25 000, as in the warm sequence; the
  cold capture of 2026-11-16 had read 14 219 there and gone on with the
  window with target 9 000;
- its calibration windows have ratio 32 000 000 and offsets 54 / 58 =
  454 612 / 856 631 (seven: the six that the capture of 2026-11-16 sent
  with 16 000 000 and 354 583 / 576 354, and the inserted window with
  target 25 000).

In all 11 sessions captured with that read, the window with target 25 000
follows a position above 25 000 (25 675 to 25 995) and is missing after
24 523 and 14 219. **[confirmed]** So FlexColor sends it only when the
carriage is beyond 25 000; the cold/warm choice of the first page 0x20
read does not decide it. **[hypothesis]**, strongly supported. The two
cold captures diverge before that read, at the first window after the
first page 0x20 read: the windows already sent differ (ratio 16 000 000
and offsets 54 / 58 = 354 583 / 576 354 on 2026-11-16; 32 000 000 and
454 612 / 856 631 here). **[confirmed]** That these windows set where the
carriage stops: **[hypothesis]**. Our cold sequence sends the windows of
2026-11-16: with them that read gave 14 219 and 14 027 in FlexColor's two
captures, 14 219 in our real preview of 2026-11-16 and 14 027 or 14 155 in
those of 2026-11-18, never above 25 000 **[confirmed]**. It is not
expected to meet this capture's case, which came from FlexColor's own
windows **[hypothesis]**, strongly supported; if that read ever gave such
a value, the runner would stop there (tolerance 256 around 14 219),
before the window with target 9 000 **[confirmed]** (script). The cold sequence of 2026-11-16 stays the
only one (user's decision, 2026-11-18).

**2026-11-25, after the recalibration** (journal): our cold sequence's
read gave 13 579 (−640 against 14 219: the runner stopped there, before
SCAN) and, after a power cycle, 13 963 (−256, accepted) **[confirmed]**;
the first page 0x20 read was 8 203 both times **[confirmed]**. That
this read moved down with the recalibration and varies between cold
starts: **[hypothesis]** (hypotheses.md, Calibration).

**First session of a FlexColor run** (2026-11-18 afternoon, ten runs,
`tests/fixtures/scan-windows-2026-11-18.json`). Its calibration windows,
before the holder code is read (§13), take a ratio and offsets 54 / 58 that
depend on what came before **[confirmed]**:

| Run | Before it | Ratio | 54 / 58 |
|---|---|---|---|
| J1, J2, J3, J7 | previews with the 6×7, 6×6 / 6×4.5, 6×6×2, 6×9 | 32 000 000 | 454 612 / 856 631 |
| J4, J6 | preview of the 24×36×4, 24×36×6 | 63 000 000 | 242 623 / 993 545 |
| J5 | preview and scan with the 4×5 | 20 400 000 | 425 883 / 697 258 |
| I | X1 idle for hours (cold-type start) | 20 000 000 | 421 597 / 688 465 |
| K | X1 switched off and on | 35 410 000 | 442 213 / 882 622 |
| J3-2 | X1 idle for 15 minutes (cold-type start) | 26 560 000 | 458 459 / 799 225 |

After a warm run, the ratio is 10 000 × *M* of the holder used last (3 200,
6 300, 2 040; §9) and 54 / 58 are that holder's preview values in six of
the seven runs; after the 24×36×6 (preview 243 623 / 994 545) the run
started with 242 623 / 993 545, 1 000 less. **[confirmed]** In the three
runs with a cold-type start (two windows with no width, the first with
target 10 000, first position 8 203, as in
`preview-sequence-cold.json`), the values are neither: 2 000, 3 541 and
2 656 × 10 000, with 54 / 58 on the 6×7 lens model of §9 (3 541: 1 000
below). **[confirmed]** Where FlexColor takes them from is unknown; the
cold capture of 2026-11-16 (16 000 000) and that of the morning of
2026-11-18 (32 000 000) are two more of them. **[hypothesis]**: a value
FlexColor keeps between runs, not the X1. Our cold sequence always sends
the windows of 2026-11-16, whatever FlexColor would have chosen.

**Scans without calibration** (part H, 2026-11-19, essai-L). Of the eight
scans of one FlexColor run, four (sessions 6, 8, 9, 10) have no
calibration at the scan resolution and no white and black references:
only the image window, the 400-line step and the image. **[confirmed]**
They came 1.7 to 6.3 minutes after the last calibrated scan of the same
resolution and holder (sessions 6, 8, 9, 10: 2.6, 1.7, 5.0, 6.3 min);
session 7 calibrated again 4.1 minutes after session 4, in the same range.
**[confirmed]** So time alone does not decide it; what does is unknown.
**[hypothesis]**

**A scan cancelled during the 400-line step** (essai-L session 5). After
`1b 00 08 06 01 00` and one line read, FlexColor read no more lines; it
kept polling 0xDF, which stayed `00 06` for about 10 s, then `00 00`; then
it sent `DB` and `CF 00 02 80`, and nothing else outside the 0xDF / 0xD3
polling. **[confirmed]** (one case) This is how FlexColor stops in that
step; whether it is the same in other steps is unknown. FlexColor waits
for `00 00` **before** `DB`; our emergency stop sends `DB` first, then
waits (docs/decisions.md). **[confirmed]** A fact to keep in mind; the
rule is not changed.

## 13. Holder detection (FlexColor 4.8.13)

Capture of 2026-11-18 (`tests/fixtures/holders/`): X1 warm, eight
previews in one FlexColor run, one per holder, FlexColor's Format menu
never touched. FlexColor showed by itself, in order: 6×6 / 6×4.5, 6×6×2,
24×36 / 36×24, 4×5, 24×36×6, 6×9, 24×36×4, 6×6 / 6×4.5 again.

**The holder code.** From the second preview of the run on, each session
starts with: a window whose target is the position just read (6 155,
once 4 331), 5 lines, binning 4, ratio 5 100 000 to 15 750 000, `E4`,
`F0 00 00 02 00 01`, 0xE1, page 0x20, then **one** calibration-type line
read (`28 00 01 00 01 01 00 2e f8 00`, 2 004 pixels). That line shows
bright bars of equal width at a regular pitch across the CCD
(**[confirmed]**, decoded from the raw data): a code on the holder's
leading edge. Counting positions in pitches from the first bar, slots 0-3,
5, 6 and 16 are bright on every holder, and slots 7-15 carry the code:

| Holder (as FlexColor named it) | Bright slots 7-15 |
|---|---|
| 24×36 / 36×24 | 15 |
| 4×5 | 14 |
| 6×6×2 | 13 |
| 6×6 / 6×4.5 | 12, 14 |
| 6×9 | 7, 15 |
| 24×36×4 | 7, 13, 14, 15 |
| 24×36×6 | 7, 12, 13 |
| 6×7 (captures of the afternoon, below; its code line, at full CCD width, is the eighth kept) | 14, 15 |

**[confirmed]** for the eight holders read, decoded from the raw image
data of the capture (the fixtures keep only the first 64 bytes of each
read, except the eight code lines below) (the pitch and bar width scale
with the ratio of that window: about 50 / 26 pixels at 8 000 000). That
window takes offsets 54 / 58 of the previous session's preview window, and
its ratio is 3 times that preview's in sessions 2 to 5 and 7, not in 6
and 8. **[confirmed]** Read as
a binary number with slot 15 = 1, 24×36, 4×5, 6×7 and 6×6×2 give 1, 2, 3
and 4, the last digits of the references of those formats in
`holders.json` (50200401 to 50200404; the references of the holders used
were not noted); the others do not follow that rule (6×6 / 6×4.5 gives
10, its reference is 50200428). Meaning of the bits: **[hypothesis]**; a lookup table of the
observed codes is enough to recognise these eight holders.
`X1Image.HolderCode` decodes such a line (frame slots 0-3, 5, 6, 16 bright
and 4 dark, code slots 7-15); `HolderCodeTests` checks it on the eight
code lines kept in `tests/fixtures/holders/holder-code-lines.json` (raw
pixels of those one-line reads only), and on changed copies of them (an
edge pixel, a hot pixel, slot 4 bright, a frame slot dark, a wider bar, a
bar off the grid).

**The first session of a run reads the code too** (correction of
2026-11-18, afternoon): its first one-line read (`28 00 01 00 01 01 00 bb
50 00`, 7 992 pixels) is bright across the CCD with no code, as written
before, but it is followed by the same window / `E4` /
`F0 00 00 02 00 01` / 0xE1 / page 0x20 / one-line read as above, at full
CCD width (`28 00 01 00 01 01 00 bb e0 00`, 8 016 pixels), and that line
carries the code: 6×6 / 6×4.5 in the first session of the morning
capture, and every holder of the afternoon. **[confirmed]** The pitch is
about 6.3 pixels per 1 000 000 of that window's ratio there (126 to 394
pixels).

**First preview per holder, FlexColor launched each time** (2026-11-18
afternoon, docs/test-session.md part G, steps 15-22;
`tests/fixtures/scan-windows-2026-11-18.json`). Every holder read the
code of the table, FlexColor named it as in the morning, and its preview
window (ratio, lines, binning, 54 / 58) is the one of the morning run
for that holder, whatever holder came before. **[confirmed]** (eight
holders, the 24×36×4 twice). The low-resolution passes occur for the
same holders (6×6 / 6×4.5, 6×6×2, 24×36), at full CCD width since each is
the first session of its run. At step 17 the 24×36×4 was first put in by
mistake (the 24×36 / 36×24, with two openings, is labelled "24x35 / 35x24", FlexColor
shows "24x36 / 36x24"): FlexColor read 7, 13, 14, 15 and made the 24×36×4
preview; the step was made again with the 24×36 (code 15). The X1 and
FlexColor did not report any holder as unknown, Hasselblad's or not.

**Low-resolution passes.** In the 6×6 / 6×4.5 (both times), 6×6×2 and
24×36 previews, FlexColor then makes two passes before the preview:
window (ratio 565 169 to 822 255, 34 to 49 ppi by the formula of §9; 77
to 169 lines; offset 18 = 9 to 231), `F0 00 00 05 00 01`,
`1b 00 01 01 01 00`, one-line reads, `DB`; twice. **[confirmed]** In the
first session of the run (6×6 / 6×4.5) the passes are at full CCD width
(7 992 pixels, binning 1, target 8 971, reads of 7 992 pixels); in the
others at 1 998 pixels, binning 4, target 6 155. Not in
the 4×5, 24×36×6, 6×9 and 24×36×4 previews, nor in any capture with the
6×7 holder. These are the holders with two formats or two frames: the
passes may find the film, the mask or the frames. **[hypothesis]**

**Preview window per holder** (offset 10, by the formula of §9 the
resolution, and offset 26):

| Holder | Ratio | ppi | Lines |
|---|---|---|---|
| 6×7 (earlier captures) | 2 666 666 | 160 | 823 |
| 6×6 / 6×4.5 | 2 666 666 | 160 | 1 201 |
| 6×6×2 | 2 666 666 | 160 | 1 327 |
| 6×9 | 2 666 666 | 160 | 1 033 |
| 24×36 / 36×24 | 4 166 666 | 250 | 1 398 |
| 4×5 | 1 700 000 | 102 | 847 |
| 24×36×6 | 2 956 081 | 177.4 | 2 704 |
| 24×36×4 | 4 422 297 | 265.3 | 2 702 |

**[confirmed]** The two strips reach about 2 700 lines, and the other
resolutions fall as the opening gets wider (opening width × ppi about 9 000
to 9 600 in mm·ppi for 4×5, 6×n and 36×24): FlexColor seems to fit the
opening in a fixed preview size. **[hypothesis]** The lines are roughly
5/3 × ppi × opening length plus 50 to 110 lines for 6×7, 6×9, 4×5 and the
two strips, not for 6×6 / 6×4.5 and 24×36. **[hypothesis]**

**0xD3** during the run: mostly `00 0e` and `00 00`, with isolated other
values (`00 04`, `00 8f`, `00 c6`, `00 71`, `00 da`, …) in every session,
with no value tied to a holder. **[confirmed]**

**Part I (2026-11-19, essai-M1 to M9): one first preview per holder, each
run after one with a 6×7-type holder.** Every holder's code matches the
table above, the two 6×7 runs that followed a 4×5 and a 24×36×6 included
(read at another pitch). **[confirmed]** (nine captures) From
`CF 00 01 80` on, outside 0xDF / 0xD3 / 0xEE polling (the reads before it
come in another order), the commands and data sent up to the code read
are identical to `preview-sequence.json` for the 6×7, 6×9, 6×6 / 6×4.5,
6×6×2, 4×5, 24×36×6 and 24×36 runs (different, as expected, for the two
reset runs). **[confirmed]** In the same sense, the 6×7
run is identical to `preview-sequence.json` to the end; the 6×6 / 6×4.5
and 6×6×2 runs, with another original than on 2026-11-18 (as asked by
the guide; not checked on the images), are identical to the captures of
2026-11-18 to the end, low-resolution passes included. **[confirmed]** So
those passes did not depend on the original here. **[hypothesis]** (two
holders, two originals each) The 24×36 passes differ slightly from those
of 2026-11-18 (ratios 558 445 / 563 603 against 558 443 / 563 653, same
offsets 18 and lines); the run of 2026-11-18 (essai-J3-2) had a cold-type
start (table of §12).
**[confirmed]** The preview windows (ratio, lines, 54 / 58) are the same
as on 2026-11-18 for every holder. **[confirmed]** With the 24×36×4 runs
of 2026-11-18, there is now, for each of the eight holders read, a warm
first preview whose commands up to the code read are those of our warm
sequence. **[confirmed]**

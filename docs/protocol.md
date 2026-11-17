# Flextight X1 protocol

Status of each statement:
**[confirmed]** observed on a real X1 (captures of 2026-11-12, FlexColor 4.8.13
Mac on macOS 10.14 Mojave) or reproduced with our own tools;
**[hypothesis]** plausible interpretation, not yet proven.

Multi-byte values: CDB fields are big-endian (SCSI convention). Data
**inside vendor pages and parameter blocks is little-endian**, unless noted.

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
| `00 01` | seen once right after `1b 00 00 01 01 00`; FlexColor starts reading image lines on this value **[confirmed]** |
| `00 06` | seen once right after `1b 00 08 06 01 00` (the 400-line step of a scan, §12), after `08 06` / `08 02` / `08 01`; FlexColor starts its one-line reads on this value. After that step's `DB`, a single `00 00`, then the next window. **[confirmed]** (three scans) |

Our own preview of 2026-11-16 on the real X1 (sequence right after
power-on, journal) saw the same busy states, `08 01`, `08 02`, `08 03`,
`08 06`, `08 07` and `08 40`, then `00 00`, with every status 0x00
**[confirmed]**.

`08 xx` = busy is **[confirmed]** for the six values above only: FlexColor
went on polling until `00 00` (or `00 01` after SCAN) each time. The
meaning of the low byte is unknown.

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
| 62 | 2 | 15 500 | 15 500 | ? |

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
  27 156 (15 500 elsewhere); origin unknown.
- Offsets 54 and 58: in the 400-line window 10 000 more than in the windows
  before it; in the image window, 850, 700 and 900 less than before the
  400-line step. **[confirmed]** Values computed by FlexColor from the frame
  and from measurements, not constants. **[hypothesis]**

## 10. READ(10) and image data

CDB `28 00 01 00 NN FF LL LL LL 00`:
NN = number of lines, FF = 01 for calibration reads and 00 for image reads,
LL = byte count (BE24) = NN × bytes per line. **[confirmed]**

Data format **[confirmed]**:
- **RGB interleaved, 16-bit little-endian**, full 16-bit range (up to ~58 000
  on an empty holder).
- Preview: 2 004 pixels per line (1 998 requested + 6), 12 024 bytes per line.
  Full CCD width for calibration: 7 992 pixels.
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
- Calibration: the first windows have ratio 62 500 instead of 125 000 and
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
  ratio 62 500). **[confirmed]**
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
  every other warm session gave 25 739-25 867. FlexColor then read page
  0x20 again and did **not** send the window with target 25 000: it went
  on with the window with target 9 000. **[confirmed]** So the warm
  sequence also depends on that measurement. **[hypothesis]**: 24 523 is a
  state left by an earlier session. That preview was the first session of
  its FlexColor run; the run before it (B, a preview) ended about 15
  minutes earlier, and the first page 0x20 read of the session showed the
  usual 6 155 / 824, so nothing confirms it yet. To check at the next
  capture session. Our runner checks that read (tolerance 256) and stops before
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
  commands (full-CCD windows with ratio 125 000, `E4`, `F0`, page 0x20,
  two READs…) are replaced by a single window found in neither fixture
  (ratio 31 250, 1 998 pixels); one READ is replaced by a one-line READ of
  12 024 bytes, also in neither fixture (`28 00 01 00 01 01 00 2e f8 00`);
  3 commands are left out (the full-CCD window with ratio 31 250, an `E4`,
  `F0 00 01 01 01`). 183 − 13 + 1 − 3 = 168. It also measures a position
  (6 059) that no fixture has. **[confirmed]** FlexColor keeps part of the
  calibration of the first preview. **[hypothesis]**
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
0x20 read in the others, and starts with a window at 600 ppi (ratio
10 000 000, binning 3). **[confirmed]** What decides the order is unknown.

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


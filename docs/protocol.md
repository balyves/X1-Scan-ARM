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
| 0x5A | MODE SENSE(10) | in | 12-100 | Vendor pages 0x20, 0x21, 0x23, 0x25, 0x26, 0x27, 0x28 and 0x29 (the only ones seen), CDB `5a 00 PP 01 00 00 00 LL LL 00`. See §5. **[confirmed]** |
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
| 0x1B | SCAN | in | 2 | `1b 00 00 01 01 00`, returns `00 00`. Starts the acquisition. **[confirmed]** |
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
| 0x27 | 9 | Unknown. |
| 0x28 | 18 | Read once (30 bytes requested), only in the capture right after power-on (2026-11-16), just before the session start: `15 00 00 00 00 00 00 00 28 12 00 58 02 00 00`, 14 × `ff`, `00`. **[confirmed]** Meaning unknown; what makes FlexColor read it is unknown. Not in `CommandPolicy.readOnly`. |
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
| `08 02`, `08 03`, `08 06`, `08 07` | busy; seen only right after power-on (2026-11-16): after the first `F0` FlexColor read `08 07`, `08 06`, `08 02`, `08 06`, `08 40`, then `00 00`; `08 03` after the first `F0 01 01 01 01` |
| `00 01` | seen once right after SCAN; FlexColor starts reading image lines on this value **[confirmed]** |

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
What triggers the page 0x28 read and the other calibration is unknown: one
capture of each kind. Two **[hypothesis]**: the uncalibrated state seen on
page 0x20 (2 048 × 3), or the holder being inserted while FlexColor waited
(the 0xD3 activity, §4, surrounds that read).

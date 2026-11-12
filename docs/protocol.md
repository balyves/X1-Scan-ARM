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
| 0x5A | MODE SENSE(10) | in | 12-100 | Vendor pages 0x20-0x29, CDB `5a 00 PP 01 00 00 00 LL LL 00`. See §5. **[confirmed]** |
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
| 0x29 | 1 | Unknown (`07`). |

**Page 0x20 (scan status)** **[confirmed unless noted]**
Offsets from the start of the 34-byte response.
- bytes 19-24: three LE16 values around 1 900, one per channel? Lamp or
  temperature readings. **[hypothesis]**
- bytes 27-28 (LE16): a **measured position**.
  FlexColor writes a target position into the scan window (§9, offset 50),
  the scanner reports the position reached (e.g. target 25 000 → 24 971,
  target 9 000 → 8 971), and FlexColor may send the measured value back in
  the next window. Focus or optics positioning. **[hypothesis]**
- bytes 31-32 (LE16): **number of lines acquired** since SCAN. Increases
  during the scan up to the total number of lines. FlexColor reads 20 lines
  each time at least 20 are available.

## 6. Log page 0x30 (usage counters)

Seven LE32 values after the 4-byte header. One of them increases by exactly 1
per preview (about 6 950 on our unit): **total scan count**. Two others
increase with time (operating or lamp hours?). **[hypothesis]**

## 7. Scanner state (0xDF)

| Value | Meaning |
|---|---|
| `00 00` | ready |
| `08 01` | busy (after F0, SCAN, stop): mechanical movement **[hypothesis]** |
| `08 40` | busy, other phase, often follows `08 01` |
| `00 01` | seen once right after SCAN |

FlexColor polls 0xDF after every action and waits for `00 00` before the next
step. **[confirmed]**

## 8. Mode command 0xF0

Four flags A B C D in the CDB. Sequence seen during a preview:
`00 00 01 01`, `00 01 01 01`, `00 00 00 01`, `00 02 00 01`, `01 01 01 01`,
`01 01 00 01`, `01 00 00 01`. White calibration lines are read after
`01 01 00 01`, dark lines after `01 00 00 01`: **C = 0** seems to close the
light path (shutter or lamp). **[hypothesis]**

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
| 50 | 2 | 0, 25 000, 9 000, 8 971 | 0, 6 250 | Target position (see page 0x20). |
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
   across it.

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
6. Loop: page 0x20 (lines available) → READ 20 lines, until all lines are
   read (41 reads for 819 lines).
7. `DB` stop, wait `DF = 00 00`, `CF 00 02 80`.

With and without film in the holder, the sequence and the windows are
identical.

# X1 protocol notes

Work in progress. Items marked *unverified* must be confirmed by a capture
before being used on real hardware.

## Transport

SCSI over SBP-2 (FireWire). Accessed on macOS via SCSITaskUserClient.
Vendor identification string: `Imacon`.

## CDB layout

- Groups 0 and 6: 6 bytes `[op, p1>>16, p1>>8, p1, len, 0]`
- Other groups: 10 bytes `[op, lun, p1 (BE32), len (BE24), 0]`

## Read-only commands (safe for first contact)

| Opcode | Purpose |
|---|---|
| 0x12 | INQUIRY |
| 0x00 | TEST UNIT READY |
| 0x03 | REQUEST SENSE |
| 0xDF | Scanner status |
| 0xD3 | Scan button |
| 0x3C | READ BUFFER (0xD8000037: serial number, 10 bytes; 0xD8000000: identity) |

## Commands that move hardware or change state (do not use yet)

0xE0 (motor), 0xF0 (scan mode), 0xD0 (firmware start), 0xDB (stop),
0x24 (SET WINDOW), 0x3B (WRITE BUFFER), 0x55 (MODE SELECT), 0xE4 (*unverified*).

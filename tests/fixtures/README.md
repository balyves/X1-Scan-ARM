# Test fixtures

Recorded from a real Flextight X1 driven by FlexColor 4.8.13 (Mac, Mojave),
2026-11-12, with `tools/capture/cap3.py`. The scanner serial number is
anonymised (`FX1xxxxxxx`). No image data from the scan is included.

## preview-sequence.json

Every SCSI exchange of one preview, in order (766 exchanges): initialisation,
calibration, positioning loop, SCAN, image reads, stop.

Fields per exchange:
- `seq`: order in the capture
- `cdb`: command descriptor block (hex)
- `direction`: `in` (scanner → host), `out` (host → scanner) or `none`
- `length`: transfer length requested
- `data_out`: data sent to the scanner (first 128 bytes, hex), if any
- `status`: SCSI status (0 = GOOD); `null` for asynchronous image reads
- `transferred`: bytes actually transferred
- `response`: complete response (hex), when known
- `response_head`: first 64 bytes of a longer response
- `async`: issued asynchronously by FlexColor (image reads)

Uses:
- **Simulator**: a virtual X1 answers each command with the recorded
  response. Polled values (0xDF state, page 0x20 line counter, registers)
  change over time: replay them in order rather than by lookup.
- **Conformance test**: our own preview sequence, run against the
  simulator, must send the same CDBs and the same `data_out` bytes, in the
  same order, apart from the number of polling commands.

Note: some "static-looking" pages change over time (page 0x25 byte 21 went
from 0x1b to 0x1c between two reads a few minutes apart).

## preview-calibration-profile.json

Per-column white and dark reference levels (2004 px × RGB, 16-bit) from the
calibration of the same preview. A simulator can synthesise image data from
these levels (dark + transmission × (white − dark)).

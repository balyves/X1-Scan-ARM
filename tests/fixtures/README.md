# Test fixtures

Recorded from a real Flextight X1 driven by FlexColor 4.8.13 (Mac, Mojave),
2026-11-12, with `tools/capture/cap3.py`. The scanner serial number is
anonymised (`FX1xxxxxxx`). Of the image data, only the first 64 bytes of
each read are kept (`response_head`): mostly dark margin pixels, a few
pixels of the frame at most. One exception: the eight holder code lines of
`holders/holder-code-lines.json` (below; docs/decisions.md).

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
- `time` (captures from 2026-11-18 on, when `cap3.py` prints it):
  wall-clock time of the command, `HH:MM:SS.mmm`

Uses:
- **Simulator**: a virtual X1 answers each command with the recorded
  response. Polled values (0xDF state, page 0x20 line counter, registers)
  change over time: replay them in order rather than by lookup.
- **Conformance test**: our own preview sequence, run against the
  simulator, must send the same CDBs and the same `data_out` bytes, in the
  same order, apart from the number of polling commands.

Note: some "static-looking" pages change over time (page 0x25 byte 21 went
from 0x1b to 0x1c between two reads a few minutes apart).

## preview-sequence-cold.json

The same preview right after the X1 was switched on (cold lamp, 6×7 holder
50200403), 2026-11-16, 821 exchanges, same fields. Converted from the
cap3.py log with `tools/capture/cap3_to_fixture.py`. cap3.py prints at most
64 bytes of a response: the 11 longer ones (INQUIRY, 96 bytes; page 0x21,
100 bytes) were completed from `preview-sequence.json`, whose complete
responses were read with `tools/x1probe`; their first 64 bytes are
identical. Those exchanges carry `"completed_from"`. This is the only
sequence sent to the real X1 (docs/decisions.md).

## preview-sequence-warm-2.json

A second warm preview, 2026-11-17: FlexColor restarted with the X1 still
warm from earlier previews (6×7 holder 50200403), 766 exchanges, converted
like the cold fixture (11 long responses completed from
`preview-sequence.json`). Its commands outside polling (CDB, data_out,
length) are identical to `preview-sequence.json`; its responses differ,
notably the first measured position (25 739 instead of 25 867), which shows
how much the scanner's measurements vary between sessions.

## scan-sequence-1000ppi.json, scan-sequence-2000ppi.json, scan-sequence-3200ppi.json

Three FlexColor runs of 2026-11-17, X1 warm, 6×7 holder 50200403: one
preview, then one scan of a small frame (0.8 to 1 cm a side, RGB 16-bit)
at 1 000, 2 000 and 3 200 ppi (1 655, 1 778 and 1 938 exchanges).
Converted like the cold fixture (14 long responses completed from
`preview-sequence.json`). They document the scan sequence (docs/protocol.md
§12). MODE SENSE page 0x24, read once per scan, is in
`CommandPolicy.readOnly` since 2026-11-17. `scan-sequence-2000ppi.json` is
copied into the app: the virtual X1 replays its scan session, and the real
X1's scan guard is built from it; the other two are not copied.

## scan-sequence-2000ppi-twice.json

2026-11-18, X1 switched on just before: a cold preview, then two 2 000 ppi
scans of the same frame without a preview between them (three sessions,
2 629 exchanges; docs/protocol.md §12). Converted like the cold fixture.
Not copied into the app.

## scan-windows-2026-11-18.json

Not a sequence of exchanges: from the ten FlexColor captures of
2026-11-18 afternoon (docs/test-session.md, part G: `essai-I`, `essai-J1`
to `-J7`, `essai-J3-2`, `essai-K`), per capture and session, in order, the
SET WINDOW data (68 bytes, hex), the page 0x20 positions (bytes 27-28) and
the E4, F0, 1B and DB commands. For scans, FlexColor's resolution, TIFF
size and the frame asked; per capture, the holder FlexColor showed and the
code slots read (docs/protocol.md §13). Read by `ScanWindowRulesTests`
(protocol.md §9, "Window rules").

## preview-sequence-warm-3.json, -4, -5

Three warm previews of 2026-11-18, FlexColor restarted before each (794,
762 and 756 exchanges). Their commands outside polling are identical to
`preview-sequence.json`; the position read before the window with target
25 000 is 25 931, 25 995 and 25 931 (docs/protocol.md §11).

## holders/

One FlexColor run of 2026-11-18, X1 warm: eight previews, one per holder,
FlexColor's Format menu never touched (docs/protocol.md §13). The capture
(7 203 exchanges) is split per session, to stay under the 2 MiB limit of
`tools/git-hooks/x1-check`: `holder-preview-1-6x6-6x45.json` (with
FlexColor's initialisation), `-2-6x6x2`, `-3-24x36`, `-4-4x5`,
`-5-24x36x6`, `-6-6x9`, `-7-24x36x4`, `-8-6x6-6x45-again`, named after the
format FlexColor showed. The file names and `seq` numbers keep the order of
the run. Converted like the cold fixture (53 long responses completed).

`holders/holder-code-lines.json`: the raw pixels of the first one-line
read of sessions 2-8 of the morning capture (`essai-H`, 2 004 pixels), and
of the full-width code read of the 6×7 in the afternoon capture `essai-K`
(8 016 pixels; `capture` and `session` identify each line), which show the
holder code on the leading edge (docs/protocol.md §13). The user agreed on
2026-11-18 to keep these eight code lines, and no other image data
(docs/decisions.md). Base64 of
little-endian UInt16 RGB, extracted from the raw data with the RAW offsets
of the cap3.py log.

## preview-calibration-profile.json

Per-column white and dark reference levels (2004 px × RGB, 16-bit) from the
calibration of the same preview. A simulator can synthesise image data from
these levels (dark + transmission × (white − dark)).

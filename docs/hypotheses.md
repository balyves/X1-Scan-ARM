# Open hypotheses

One line per open **[hypothesis]**: the statement, the evidence that is
missing, and the capture (or test) that would settle it. Remove a line
when it is confirmed or refuted (and say so in `docs/journal.md`). First
version (2026-11-19): the hypotheses of the work since 2026-11-17; the
older ones in `docs/protocol.md` §1-§11 are still to be added.

## Scan windows (protocol.md §9)

- Offset 62 is computed from FlexColor's own frame coordinates. Missing:
  those coordinates. Settle: frames typed numerically, if FlexColor allows
  it, scanned at several resolutions.
- At coarse resolutions FlexColor moves the frame to its output pixel
  grid (−48 at 600 ppi). Against it: the moved frame's −63. Settle: one frame
  at 600 and 300 ppi at several sub-pixel positions (zoom 100 %).
- One unit of offset 62 is 1/28 800 inch (0.88 µm). Missing: an
  independent length. Settle: a target of known size scanned with frames
  at known distances.
- Offsets 54 / 58 move the CCD and the lens (thin-lens model in the
  optical resolution O). Missing: values for other holders. Settle: scans
  at several resolutions with one other holder.
- *M* (highest optical resolution) is 3 200 for the 6×7, 6 300 for the
  35 mm strips, 2 040 for the 4×5. Missing: scans near those limits.
  Settle: scans at 3 300, 4 100, 6 300 ppi with each holder.
- The 400-line step sweeps the focus and FlexColor keeps the sharpest
  line. Missing: FlexColor's sharpness measure. Settle: frames on targets
  of known focus behaviour.
- Calibration and references are skipped for some scans by a rule not
  known. Settle: the same scan repeated at timed intervals.
- 32 units of offset 62 (0.028 mm) do not change the focus found.
  Settle: on the real X1, the same frame with offset 62 shifted: a window
  never captured, so only with the user's explicit approval and a change
  of CLAUDE.md rule 4 (decision of 2026-11-19: simulator only until then).

- A scan cancelled in another step stops the same way as during the
  400-line step (§12). Settle: a FlexColor scan cancelled during the image.
- Byte 49 is the horizontal binning; offset 18 is the start of the frame
  along the drum (§9). Settle: already strongly supported; a frame typed
  at a known position would confirm offset 18.

## Holders (protocol.md §13)

- The low-resolution passes of the 6×6 / 6×4.5, 6×6×2 and 24×36 do not
  depend on the original (two originals each). Missing: very different
  originals. Settle: a first preview with an empty holder and with a dense
  film.
- The low-resolution passes find the film, the mask or the frames.
  Settle: those holders with and without film.
- The meaning of the bits of the holder code. Settle: holders not read
  yet.
- The preview window of each holder is fixed by FlexColor (rule not
  found). Settle: a holder not captured yet.
- Stopping right after the holder code read (other holder than the 6×7)
  leaves the X1 in a harmless state. Settle: the first such stop on the
  real X1, then a preview (the stop is decided, not implemented yet).
- Session start values after a cold-type start come from FlexColor, not
  the X1. Settle: two cold starts with FlexColor's preferences reset.

## Calibration

- Values that come from the X1's calibration (positions, 54 / 58, page
  contents) may change after the recalibration of 2026-11-20 (every
  capture up to 2026-11-19 was made with the original one: the user's
  statement). Settle: docs/test-session.md part J.

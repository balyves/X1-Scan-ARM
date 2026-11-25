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
- Our sharpness measures (gradient energy, Laplacian variance,
  normalised gradient energy; `X1Image.FocusSweep`) pick a line close
  enough to FlexColor's *i* for the image (today 0 to 31 lines apart on
  the 29 6×7 scans at 1 000-3 200 ppi, mean 6.6 to 7.1). Missing: what a
  difference of n lines does to the sharpness of the image. Settle: one
  frame of a fine target scanned with FlexColor, then the same 400 lines
  read by our measure, and scans at *i* and *i* ± 5, 10, 20, 30 lines
  (computed windows: only after CLAUDE.md rule 4 is changed).
- The manual focus correction (in lines of the sweep, 50 units each)
  moves the plane of best focus in proportion, the same way at every
  resolution. Missing: any scan with a correction. Settle: the same scan
  with corrections −10, 0, +10 on a fine target (same condition).
- One line of the sweep is 50 units of 54 / 58 and line 0 is base +
  10 000 (protocol.md §9). The 31 scans only show multiples of 50 from
  base + 10 000: they do not tell a sweep of 50 per line from FlexColor
  rounding a continuous focus value to 50, or another start. Settle: a
  target with a known depth step (or tilted) read by the 400-line step,
  where the sharpest line must move by a predictable amount.
- At 600 ppi offset 62 predicted by option A is 43 to 53 units above
  FlexColor's (family 2, three predictions; 600 ppi left out of the
  menu). Likely the same cause as the 600 ppi move to the output pixel
  grid above. Settle: the same frame at 600 and 300 ppi at several
  sub-pixel positions (zoom 100 %).
- Option A (offset 62, decisions.md "Offset 62 of the 400-line window")
  counts the middle of the frame from offset 18: offset 18 + (offset 26 −
  2 × gap − 2) ÷ 2 lines: offset 18 is taken as the first image line (the
  2 × gap + 2 extra lines of offset 26 do not move it) and the image as
  offset 26 without those extra lines. Missing:
  the drum position of the image lines (option A is within −6 to +24 units
  of FlexColor's value, which does not separate this from other
  conventions). Settle: a target with a mark at a known position along the
  drum, scanned with frames typed so that their middle is on the mark;
  the mark must appear in the 400 lines of the focus step.
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
  contents) may change after a recalibration (every capture up to
  2026-11-19 was made with the original one: the user's statement; the
  recalibration planned for 2026-11-20 had not been made on 2026-11-25:
  the user's statement). Settle: docs/test-session.md part J.
- With the X1's original calibration (no recalibration: the user's
  statement of 2026-11-25), the page 0x20 read after
  `F0 00 00 01 01 01` in our cold sequence (the first checked position,
  expected 14 219 ± 256) spreads more than that window accepts: 384 on
  the same day, 640 from 13 579 to 14 219: 13 579 (−640, the preview stopped there, before
  SCAN) then 13 963 (−256, accepted) on 2026-11-25, against 14 027 to
  14 219 from 2026-11-16 to 18; the first page 0x20 read was 8 203 (the
  power-on value) both times. Its range and the cause of the spread are
  unknown (cold start itself, temperature, holder present or not, holder
  type at power-on: possible causes, none checked); the expected value comes from the capture of 2026-11-16 only. Settle: several cold
  starts (X1 switched off and on each time) captured with FlexColor on
  the reference Mac, and the same read logged by X1 Scan's real cold
  previews (FlexColor's own windows may differ from ours: protocol.md §12).

## Application (lot 1)

- Preview columns 0-4, whose white reference is at the dark level, are
  masked or unlit CCD pixels (the preview's part of the width margin,
  protocol.md §10), not image. The fixtures' image reads already hold
  these columns (at most about 300-480), but the holder's edge is dark
  there too, so they do not settle it. Settle: a preview whose image is
  bright at its left edge (clear film or an empty holder at that edge),
  in part J. If confirmed, the exposure measure leaves them out (user's
  decision of 2026-11-20, not coded yet).

- The exposure indicator's thresholds, clipping at 64 000 and noise floor
  at 1 024 on the 16-bit raw samples (decisions.md, "Lot 1: exposure
  indicator"), are round guesses. Missing: measured levels. Settle: dark
  frames (lamp off or an opaque holder) for the noise floor, an
  over-exposed frame (empty holder, about 58 000) for the clipping level.

## Installation check (assistant, lot 1)

- On macOS 26 Tahoe, a DriverKit driver attached to the IEEE 1394
  controller (`IOUserClass` or `IOUserServerName` on an entry under it) is
  ASFireWire, active (`FireWireController.hasDriverKitDriver`). Missing:
  the registry of a Mac with the adapter, ASFireWire and the X1 (class and
  bundle names). Settle: `ioreg -l -w0` on that Mac, X1 on and connected,
  read only and kept outside the repository (user's decision of
  2026-11-25); only class names are taken from it.
- The adapter's controller has PCI class code 0x0C0010 (IEEE 1394 OHCI)
  and is seen as an `IOPCIDevice` through Thunderbolt on Apple Silicon.
  Missing: the same listing. Settle: the same `ioreg`.

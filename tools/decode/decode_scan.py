#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Decode a Flextight X1 scan captured with tools/capture/cap3.py.

Usage: decode_scan.py capture.txt capture.raw out.png [--gap N] [--compare flexcolor.tif] [--export DIR]

- capture.txt : lldb log written by cap3.py (commands, window data, READ offsets)
- capture.raw : data appended by cap3.py (every READ, in order)

The last session of the log must hold one scan (docs/protocol.md §10, §12):
the window sent just before `1b 00 00 01 01 00` gives the first column
(offset 14), the width (offset 22) and the binning (byte 49).

Steps:
1. White and dark per column from the full-width calibration read of the
   session (CDB byte 5 = 01): its bright lines are the white, the others the
   dark. Image column i is white column margin + offset14 + i.
2. Image lines: the one-line reads after the SCAN are the priming lines
   (2 × gap + 1); with the 20-line blocks they form the image. The first
   `margin` columns (dark in the image lines, 24 / binning, docs/protocol.md
   §10) are dropped.
3. Flat field (raw - dark) / (white - dark), then R and B realigned on G by
   `gap` lines (R taken `gap` lines later, B `gap` lines earlier, as in
   decode_preview.py). By default gap = (priming lines - 1) / 2, the
   relation seen in the captures of 2026-11-17 (20 at 2 000 and 3 200 ppi,
   7 at 1 000 ppi, also measured by correlation); --gap overrides it.
4. Lines are 5/3 times denser than columns: resampled by 3/5 (linear) to
   floor(aligned lines × 3/5) lines. Output line j is taken at input line
   5/3 × j + 0.25 (PHASE): the phase that matched FlexColor's TIFF best at
   2 000 ppi (0 to 0.33 differ by less than 0.001 in correlation).
5. Gamma 2.2 for display, 8-bit PNG. No colour profile is applied.

--export writes, in DIR, what the Swift decoder's optional test reads
(X1Kit ScanDecodeTests, X1_SCAN_CHECK_DIR): calibration.bin and image.bin
(the READ data as captured), geometry.txt ("first_column width binning
priming calibration_width") and expected.f32 (the linear output before
gamma, float32). Keep DIR outside the repository: it holds image data.

--compare reads FlexColor's TIFF of the same scan (needs the tifffile
package) and prints the correlation of log values per channel: FlexColor
applies its own tone curve and profile, so values differ, geometry does not.
"""
import re
import sys
import numpy as np
from PIL import Image

BYTES_PER_PIXEL = 6  # RGB, 16-bit little-endian, interleaved
LINE_RATIO = 5 / 3   # lines read per output line (protocol.md §10)
PHASE = 0.25         # input line of output line 0 (see step 4)


def parse(log_path):
    """Commands of the last session: windows, SCANs and READs with raw offsets."""
    events, cdb, current = [], None, None
    for line in open(log_path, errors="replace"):
        line = line.strip()
        m = re.match(r"^\d+ CDB (.*)$", line)
        if m:
            cdb = m.group(1).split()
            current = {"cdb": cdb}
            if cdb[:4] == ["cf", "00", "01", "80"]:
                events = []
            events.append(current)
            continue
        m = re.match(r"^ENV (.*)$", line)
        if m and current is not None:
            current["out"] = bytes.fromhex(m.group(1))
        m = re.match(r"^RAW offset=(\d+) taille=(\d+)", line)
        if m and current is not None and cdb[0] == "28":
            current.update(off=int(m.group(1)), size=int(m.group(2)),
                           lines=int(cdb[4], 16), calibration=cdb[5] != "00")
        if line.startswith("RAW skipped"):
            sys.exit("the capture skipped image reads (X1CAP_SCAN_MB): incomplete scan")
    return events


def le(b, offset, size):
    return int.from_bytes(b[offset:offset + size], "little")


def main():
    args = sys.argv[1:]
    if len(args) < 3 or any(a.startswith("--") for a in args[:3]):
        sys.exit(__doc__.strip().splitlines()[2])
    try:
        compare = args[args.index("--compare") + 1] if "--compare" in args else None
        gap_option = int(args[args.index("--gap") + 1]) if "--gap" in args else None
        export = args[args.index("--export") + 1] if "--export" in args else None
    except (IndexError, ValueError):
        sys.exit("--gap needs a whole number of lines, --compare a TIFF file, --export a folder")
    log_path, raw_path, out_path = args[:3]
    raw = np.memmap(raw_path, dtype="<u2", mode="r")
    events = parse(log_path)

    scans = [i for i, e in enumerate(events) if e["cdb"][:6] == "1b 00 00 01 01 00".split()]
    if not scans:
        sys.exit("no scan (1b 00 00 01 01 00) in the last session of the log")
    scan_index = scans[-1]
    if not any(e["cdb"][:6] == "1b 00 08 06 01 00".split() for e in events):
        sys.exit("the last session is a preview, not a scan (no 1b 00 08 06 01 00): use decode_preview.py")
    window = next((e.get("out") for e in reversed(events[:scan_index]) if e["cdb"][0] == "24"), None)
    if window is None or len(window) < 68:
        sys.exit("no window data before the scan")
    first_column, width, binning = le(window, 14, 2), le(window, 22, 2), window[49]
    margin = 24 // binning

    def block(e, columns):
        a = np.asarray(raw[e["off"] // 2:(e["off"] + e["size"]) // 2], dtype=np.float64)
        return a.reshape(e["lines"], columns, 3)

    calibration = [e for e in events if "off" in e and e["calibration"]]
    if not calibration:
        sys.exit("no full-width calibration read in the scan session")
    full = calibration[0]["size"] // calibration[0]["lines"] // BYTES_PER_PIXEL
    cal = np.concatenate([block(e, full) for e in calibration])
    level = cal[..., 1].mean(axis=1)
    bright = level > (level.max() + level.min()) / 2
    columns = slice(margin + first_column, margin + first_column + width)
    white, dark = cal[bright].mean(0)[columns], cal[~bright].mean(0)[columns]

    image_reads = [e for e in events[scan_index:] if "off" in e and not e["calibration"]]
    priming = 0
    while priming < len(image_reads) and image_reads[priming]["lines"] == 1:
        priming += 1
    gap = gap_option if gap_option is not None else (priming - 1) // 2
    img = np.concatenate([block(e, width + margin) for e in image_reads])[:, margin:]
    ff = np.clip((img - dark) / np.maximum(white - dark, 1), 1e-4, 1)
    n = len(ff)
    aligned = np.stack([ff[2 * gap:, :, 0], ff[gap:n - gap, :, 1], ff[:n - 2 * gap, :, 2]], axis=2)

    lines = int(len(aligned) / LINE_RATIO)
    pos = LINE_RATIO * np.arange(lines) + PHASE
    i0 = np.floor(pos).astype(int)
    f = (pos - i0)[:, None, None]
    out = aligned[i0] * (1 - f) + aligned[np.minimum(i0 + 1, len(aligned) - 1)] * f
    print(f"window: first column {first_column}, width {width}, binning {binning}, margin {margin}; "
          f"{priming} priming lines (gap {gap}); {n - priming} image lines read -> {lines} lines")

    Image.fromarray((out ** (1 / 2.2) * 255).astype(np.uint8)).save(out_path, format="PNG")

    if export:
        import os
        os.makedirs(export, exist_ok=True)
        data = np.asarray(raw).view(np.uint8)
        with open(os.path.join(export, "calibration.bin"), "wb") as f:
            for e in calibration:
                f.write(data[e["off"]:e["off"] + e["size"]].tobytes())
        with open(os.path.join(export, "image.bin"), "wb") as f:
            for e in image_reads:
                f.write(data[e["off"]:e["off"] + e["size"]].tobytes())
        with open(os.path.join(export, "geometry.txt"), "w") as f:
            f.write(f"{first_column} {width} {binning} {priming} {full}\n")
        out.astype("<f4").tofile(os.path.join(export, "expected.f32"))

    if compare:
        import tifffile
        ref = tifffile.imread(compare).astype(np.float64) / 65535
        if ref.shape != out.shape:
            sys.exit(f"size differs: decoded {out.shape}, FlexColor {ref.shape}")
        for ch, name in enumerate("RGB"):
            a = np.log(out[..., ch]).ravel()
            b = np.log(np.clip(ref[..., ch], 1e-4, None)).ravel()
            print(f"{name}: correlation of log values {np.corrcoef(a, b)[0, 1]:.4f}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Decode a Flextight X1 preview captured with tools/capture/cap3.py.

Usage: decode_preview.py capture.txt capture.raw out.png [--aspect 3] [--gap 1]

- capture.txt : lldb log written by cap3.py (gives the offset of every READ)
- capture.raw : image data appended by cap3.py
Steps: split calibration / image reads, flat-field correction
(raw - dark) / (white - dark) per column, R/B line-gap realignment,
aspect correction, gamma 2.2 for display. No colour profile is applied.
"""
import re
import sys
import numpy as np
from PIL import Image

BYTES_PER_PIXEL = 6  # RGB, 16-bit little-endian, interleaved


def parse(log_path):
    reads, scan_started, cdb = [], False, None
    for line in open(log_path, errors="replace"):
        line = line.strip()
        m = re.match(r"^\d{4} CDB (.*)$", line)
        if m:
            cdb = m.group(1).split()
            if cdb[0] == "1b":
                scan_started = True
            continue
        m = re.match(r"^RAW offset=(\d+) taille=(\d+)", line)
        if m and cdb and cdb[0] == "28":
            reads.append({"off": int(m.group(1)), "size": int(m.group(2)),
                          "lines": int(cdb[4], 16), "scan": scan_started})
    return reads


def main():
    args = sys.argv[1:]
    aspect = float(args[args.index("--aspect") + 1]) if "--aspect" in args else 3.0
    gap = int(args[args.index("--gap") + 1]) if "--gap" in args else 1
    log_path, raw_path, out_path = args[:3]
    raw = open(raw_path, "rb").read()
    reads = parse(log_path)

    image_reads = [r for r in reads if r["scan"] and r["lines"] > 1]
    width = image_reads[0]["size"] // image_reads[0]["lines"] // BYTES_PER_PIXEL

    def block(r):
        a = np.frombuffer(raw[r["off"]:r["off"] + r["size"]], dtype="<u2")
        return a.astype(np.float64).reshape(-1, width, 3)

    cal = [block(r) for r in reads
           if not r["scan"] and r["size"] == r["lines"] * width * BYTES_PER_PIXEL and r["lines"] > 1]
    if not cal:
        sys.exit("no calibration blocks found")
    levels = [c.mean() for c in cal]
    split = (max(levels) + min(levels)) / 2
    white = np.concatenate([c for c, l in zip(cal, levels) if l > split]).mean(0)
    dark = np.concatenate([c for c, l in zip(cal, levels) if l <= split]).mean(0)

    img = np.concatenate([block(r) for r in image_reads])
    ff = np.clip((img - dark) / np.maximum(white - dark, 1), 0, 1)
    out = ff.copy()
    if gap:
        out[:-gap, :, 0] = ff[gap:, :, 0]
        out[gap:, :, 2] = ff[:-gap, :, 2]
        out = out[gap:-gap]
    disp = (out ** (1 / 2.2) * 255).astype(np.uint8)
    im = Image.fromarray(disp)
    if aspect != 1:
        im = im.resize((round(im.width / aspect), im.height), Image.LANCZOS)
    im.save(out_path)
    print(f"{len(image_reads)} image reads, {img.shape[0]} lines x {width} px, "
          f"white {white.reshape(-1, 3).mean(0).round()}, dark {dark.reshape(-1, 3).mean(0).round()} -> {out_path}")


if __name__ == "__main__":
    main()

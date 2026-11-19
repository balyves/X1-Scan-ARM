#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Export the 400-line focus step of every scan in FlexColor captures.

Usage: export_focus.py OUT_DIR capture.txt [capture.txt ...]

Each capture.txt is an lldb log written by tools/capture/cap3.py, with its
capture.raw next to it. For every scan session (one with `1b 00 08 06 01 00`,
docs/protocol.md §12), OUT_DIR/<capture>-<session>/ receives:

- focus.bin: the 400 one-line reads after `1b 00 08 06 01 00`, as captured
  (RGB, 16-bit little-endian, margin + width pixels per line);
- calibration.bin: the full-width calibration read (CDB byte 5 = 01, margin
  + 7 992 ÷ binning pixels) of the session, or else of the last earlier
  session of the capture with that width (a scan without calibration,
  docs/protocol.md §12, or a binned scan after a preview at that binning);
- focus.txt: one line of "key=value" fields: column (offset 14), width, binning, margin (24 ÷
  binning), full (calibration pixels per line, margin included), lines (one-line reads), base54,
  base58 (the window before the 400-line window), image54, image58 (the
  image window sent before `1b 00 00 01 01 00`; absent if the scan was
  cancelled), ratio, ppi (offset 10 × 3 ÷ 50 000, rounded; for the 6×7, whose holder
  factor is 1).

FlexColor's line *i* is then (base + 10 000 − image) ÷ 50 (docs/protocol.md
§9, [hypothesis]); X1Kit's FocusSweepReportTests read OUT_DIR when
X1_FOCUS_CHECK_DIR is set. Keep OUT_DIR outside the repository: it holds
image data.
"""
import os
import re
import sys

BYTES_PER_PIXEL = 6


def sessions(log_path):
    """Commands of each session (a session starts with `cf 00 01 80`), from
    session 1; the commands before the first one are session 0."""
    result, events, current = [], [], None
    for line in open(log_path, errors="replace"):
        line = line.strip()
        m = re.match(r"^\d+ CDB (.*?)(?:\s+t=\S+)?$", line)
        if m:
            cdb = m.group(1).split()
            current = {"cdb": cdb}
            if cdb[:4] == ["cf", "00", "01", "80"]:
                result.append(events)
                events = []
            events.append(current)
            continue
        m = re.match(r"^ENV (.*)$", line)
        if m and current is not None:
            current["out"] = bytes.fromhex(m.group(1))
        m = re.match(r"^RAW offset=(\d+) taille=(\d+)", line)
        if m and current is not None and current["cdb"][0] == "28":
            current.update(off=int(m.group(1)), size=int(m.group(2)),
                           lines=int(current["cdb"][4], 16), calibration=current["cdb"][5] != "00")
        if line.startswith("RAW skipped") and current is not None:
            current["skipped"] = True
    result.append(events)
    return result


def le(b, offset, size):
    return int.from_bytes(b[offset:offset + size], "little")


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__.strip().splitlines()[2])
    out_dir = sys.argv[1]
    for log_path in sys.argv[2:]:
        raw_path = log_path[:-4] + ".raw"
        name = os.path.basename(log_path)[:-4]
        data = open(raw_path, "rb").read()
        last_calibration = {}
        for number, events in enumerate(sessions(log_path)):
            calibration = [e for e in events if "off" in e and e["calibration"]]
            if calibration:
                full = calibration[0]["size"] // calibration[0]["lines"] // BYTES_PER_PIXEL
                last_calibration[full] = calibration
            steps = [i for i, e in enumerate(events) if e["cdb"][:6] == "1b 00 08 06 01 00".split()]
            if not steps:
                continue
            step = steps[0]
            windows = [i for i, e in enumerate(events[:step]) if e["cdb"][0] == "24" and "out" in e]
            if len(windows) < 2:
                print(f"{name} {number}: fewer than two windows before the step, skipped")
                continue
            focus, base = events[windows[-1]]["out"], events[windows[-2]]["out"]
            if le(focus, 10, 4) != 21_674_665:
                print(f"{name} {number}: window before the step is not the 400-line window, skipped")
                continue
            reads = []
            for e in events[step + 1:]:
                if e["cdb"][0] == "db":
                    break
                if e["cdb"][0] == "28":
                    reads.append(e)
            if any(e.get("skipped") or "off" not in e for e in reads):
                print(f"{name} {number}: focus reads not captured, skipped")
                continue
            if len(reads) != 400:
                print(f"{name} {number}: {len(reads)} focus lines (cancelled scan?), skipped")
                continue
            width, binning = le(focus, 22, 2), focus[49]
            margin = 24 // binning
            cal = last_calibration.get(7_992 // binning + margin)
            fields = {
                "column": le(focus, 14, 2), "width": width, "binning": binning, "margin": margin, "lines": len(reads),
                "base54": le(base, 54, 4), "base58": le(base, 58, 4),
                "ratio": le(focus, 10, 4), "ppi": (le(base, 10, 4) * 3 + 25_000) // 50_000,
            }
            image = None
            for i, e in enumerate(events[step:], start=step):
                if e["cdb"][:6] == "1b 00 00 01 01 00".split():
                    image = next(x["out"] for x in reversed(events[:i]) if x["cdb"][0] == "24" and "out" in x)
                    break
            if image is not None:
                fields.update(image54=le(image, 54, 4), image58=le(image, 58, 4), ppi=(le(image, 10, 4) * 3 + 25_000) // 50_000)
            if cal is not None:
                fields["full"] = cal[0]["size"] // cal[0]["lines"] // BYTES_PER_PIXEL
            directory = os.path.join(out_dir, f"{name}-{number}")
            os.makedirs(directory, exist_ok=True)
            with open(os.path.join(directory, "focus.bin"), "wb") as f:
                for e in reads:
                    f.write(data[e["off"]:e["off"] + e["size"]])
            if cal is not None:
                with open(os.path.join(directory, "calibration.bin"), "wb") as f:
                    for e in cal:
                        f.write(data[e["off"]:e["off"] + e["size"]])
            with open(os.path.join(directory, "focus.txt"), "w") as f:
                f.write(" ".join(f"{k}={v}" for k, v in fields.items()) + "\n")
            print(f"{name} {number}: {fields}{'' if cal is not None else ' (no calibration)'}")


if __name__ == "__main__":
    main()

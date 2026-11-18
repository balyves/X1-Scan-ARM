#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Turns a cap3.py capture log into a fixture (tests/fixtures/README.md format).

    python3 -I tools/capture/cap3_to_fixture.py CAPTURE.txt OUTPUT.json "description" [COMPLETE.json]

The serial number is anonymised (FX1xxxxxxx, in text and in hex); image data
is not included (only the first 64 bytes of a READ 0x28, as the capture
prints them). cap3.py prints at most 64 bytes of a response: longer ones are
kept as `response_head`. With COMPLETE.json (an existing fixture), such a
response gets a complete `response` taken from that fixture, only when that
fixture has exactly one complete response to the same CDB and its first 64
bytes are identical; the exchange is then marked `"completed_from"`.
"""
import json
import re
import sys

# "0001 CDB 12 00 00 00 60 00", optionally followed by "  t=HH:MM:SS.mmm" (cap3.py
# since 2026-11-18); more than 4 digits after 9 999 commands.
CDB = re.compile(r"^(\d{4,}) CDB ((?:[0-9a-f]{2} ?)+?)(?:\s+t=(\d\d:\d\d:\d\d\.\d{3}))?$")
DIR = re.compile(r"^\s+(<-X1|->X1|--) (\d+) octets$")
FIN = re.compile(r"^\s+FIN statut=0x([0-9a-f]{2}) recus=(\d+)$")
SERIAL_TEXT = re.compile(r"FX1[0-9A-Za-z]{7}")
SERIAL_HEX = re.compile(r"46 58 31( [0-9a-f]{2}){7}")
ANON_HEX = "46 58 31" + " 78" * 7


def anonymise(text):
    return SERIAL_HEX.sub(ANON_HEX, SERIAL_TEXT.sub("FX1xxxxxxx", text))


def parse(lines):
    exchanges = []
    current = None
    for raw in lines:
        line = raw.rstrip("\n").rstrip()
        m = CDB.match(line)
        if not m and re.match(r"^\d+ CDB ", line):
            # cap3.py could not read the CDB ("CDB ?"), or a malformed time: its FIN and
            # REP lines would go to the previous exchange.
            raise SystemExit(f"unreadable CDB line: {line!r}")
        if m:
            current = {"seq": int(m.group(1)), "cdb": m.group(2).strip(), "direction": None,
                       "length": None, "data_out": None, "status": None, "transferred": None,
                       "response": None, "response_head": None, "async": False}
            if m.group(3):
                current["time"] = m.group(3)
            exchanges.append(current)
            continue
        if current is None:
            continue
        m = DIR.match(line)
        if m:
            current["direction"] = {"<-X1": "in", "->X1": "out", "--": "none"}[m.group(1)]
            current["length"] = int(m.group(2))
            continue
        m = FIN.match(line)
        if m:
            current["status"] = int(m.group(1), 16)
            current["transferred"] = int(m.group(2))
            continue
        stripped = line.strip()
        if stripped.startswith("ENV "):
            current["data_out"] = stripped[4:]
        elif stripped.startswith("REP "):
            data = stripped[4:]
            if current["cdb"].startswith("28 ") or (current["length"] or 0) > 64:
                current["response_head"] = data
            else:
                current["response"] = data
    for e in exchanges:
        if e["direction"] is None or e["length"] is None:
            raise SystemExit(f"exchange {e['seq']}: no direction")
        if e["direction"] == "out" and len((e["data_out"] or "").split()) != e["length"]:
            # cap3.py prints at most 128 bytes of data out.
            raise SystemExit(f"exchange {e['seq']}: data out incomplete")
        # A READ without FIN was issued asynchronously (status not captured).
        if e["status"] is None and not e["cdb"].startswith("28 "):
            raise SystemExit(f"exchange {e['seq']}: no status, and not a READ")
        e["async"] = e["status"] is None
    return exchanges


def complete(exchanges, path):
    known = {}
    with open(path, encoding="utf-8") as f:
        for e in json.load(f)["exchanges"]:
            r = e.get("response")
            if r and len(r.split()) > 64:
                known.setdefault(e["cdb"], set()).add(r)
    count = 0
    for e in exchanges:
        head = e.get("response_head")
        if e["response"] is not None or head is None or e["cdb"].startswith("28 "):
            continue
        candidates = known.get(e["cdb"], set())
        if len(candidates) != 1:
            continue
        (full,) = candidates
        if full.split()[:64] == head.split() and len(full.split()) == e["length"]:
            e["response"] = full
            e["completed_from"] = path.rsplit("/", 1)[-1]
            count += 1
    return count


def main():
    source, output, description = sys.argv[1:4]
    with open(source, encoding="utf-8", errors="replace") as f:
        exchanges = parse(f)
    completed = complete(exchanges, sys.argv[4]) if len(sys.argv) > 4 else 0
    fixture = {
        "description": description,
        "notes": [
            "response = complete response (up to 64 bytes); response_head = first 64 bytes only",
            "direction: in = scanner to host, out = host to scanner",
            "image data (READ 0x28) is not included",
            "async = issued asynchronously by FlexColor (image reads); status not captured for these",
        ] + (["time: wall-clock time of the command (HH:MM:SS.mmm), from cap3.py"]
             if any("time" in e for e in exchanges) else []) + ([f"completed_from: response longer than 64 bytes completed from that fixture "
              f"(identical first 64 bytes; complete responses read with tools/x1probe)"] if completed else []),
        "exchanges": exchanges,
    }
    text = anonymise(json.dumps(fixture, indent=1, ensure_ascii=False))
    if SERIAL_TEXT.search(text.replace("FX1xxxxxxx", "")) or SERIAL_HEX.sub("", text.replace(ANON_HEX, "")) != text.replace(ANON_HEX, ""):
        raise SystemExit("serial number still present")
    with open(output, "w", encoding="utf-8") as f:
        f.write(text + "\n")
    print(f"{len(exchanges)} exchanges, {completed} responses completed")


if __name__ == "__main__":
    main()

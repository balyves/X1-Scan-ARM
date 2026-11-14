# CLAUDE.md

Instructions for Claude Code working in this repository.

## Project

X1-Scan-ARM: open-source software to drive a **Hasselblad Flextight X1** film
scanner from modern macOS (Apple Silicon). FlexColor 4.8.13, the original
software, is 32-bit and stopped working after macOS 10.14 Mojave.

The protocol is being decoded from captures of FlexColor on a real X1. Read
`docs/journal.md` first, then `docs/protocol.md`. Every statement in the docs
is marked **[confirmed]** or **[hypothesis]**: keep that discipline, and
never present a hypothesis as fact.

Scope: **Flextight X1 only**. Other Flextight / Imacon models are out of scope.

## Language

- Talk to the user in **French**.
- Code, comments, commit messages and documentation in **English**.

## Hard rules

1. **No Hasselblad material in the repository**: no FlexColor binary,
   firmware, FPGA bitstream, film profile, setup file or excerpt of their code.
   Describing behaviour observed in captures or static analysis is fine.
2. **No personal data**: no scanner serial number (use `FX1xxxxxxx`), no
   client or studio names, no IPTC credits from scan files, no capture logs or
   raw image files. Check before every commit.
3. **Licence**: the project is MIT. Do not copy code from GPL projects
   (notably eigenshell/flextight-shenanigans). Their documentation can be
   read as a reference; the code must be our own.
4. **Scanner safety**:
   - Read-only commands may be used freely. They are exactly those allowed
     by `CommandPolicy.readOnly`
     (`X1Kit/Sources/X1Transport/CommandPolicy.swift`): each CDB must match
     byte for byte, with its length, one captured from FlexColor or sent by
     `tools/x1probe` to a real X1 (TEST UNIT READY, REQUEST SENSE).
     - 0x00 TEST UNIT READY `00 00 00 00 00 00` (no data);
     - 0x03 REQUEST SENSE `03 00 00 00 12 00` (18);
     - 0x12 INQUIRY `12 00 00 00 60 00` (96);
     - 0x4D LOG SENSE, page 0x30 only: `4d 00 30 00 00 00 00 00 34 00` (52);
     - 0x5A MODE SENSE `5a 00 PP 01 00 00 00 LL LL 00`, only the captured
       pages and lengths: 0x20 (34), 0x21 (12, 100), 0x23 (12, 60),
       0x25 (24), 0x26 (56), 0x27 (20), 0x29 (14);
     - 0xD3 status / sensors `d3 00 00 00 02 00` (2);
     - 0xDF scanner state `df 00 00 00 02 00` (2);
     - 0xEE register, bank 1, addresses 0x04-0x19 only:
       `ee 00 00 00 01 AA 00 00 01 00` (1).

     Any other page, length, register or CDB byte counts as a command not
     seen in a capture (next point). See `docs/decisions.md`, "Read-only
     guard".

     `tools/x1probe` sends a subset of these reads (no 0xDF, no page 0x20,
     only the longest read of pages 0x21 and 0x23).
   - **Any command that moves the scanner or changes its state** (0x24, 0xF0,
     0xE4, 0x1B, 0xDB, 0xCF, 0xD2, 0xE0, 0x55, 0x3B, or anything not seen in a
     capture) requires the user's **explicit approval before running**, must
     reproduce byte for byte a sequence captured from FlexColor, and must
     stop at the first unexpected status or response.
   - Never guess parameter values for positions, motors or exposure.
5. **Instructions involving the scanner**: at every step, state explicitly
   the required state of the **X1 (on / off)** and of **FlexColor
   (open / closed)**. Only one program can open the scanner at a time.
6. **Git**: show `git status` and a summary of the diff, and wait for the
   user's approval before `git push`. Never force-push.
7. **Review before every commit**: run the `x1-reviewer` subagent
   (`.claude/agents/x1-reviewer.md`) on the changes, and show the user its
   full report together with `git status` and the diff summary. Fix or
   discuss every "Bloquant" item before committing. The pre-commit hook
   (`tools/git-hooks`, install with `git config core.hooksPath
   tools/git-hooks`) and the X1Kit CI workflow are additional checks, not a
   substitute.

## Machines

- A reference Mac on **macOS 10.14 Mojave** with FlexColor 4.8.13 and the X1,
  used for captures (`tools/capture/cap3.py`, lldb, i386).
- Current Macs on **macOS 26 Tahoe** (Apple Silicon) for development and
  production. Apple removed FireWire in Tahoe; the X1 would need the
  ASFireWire DriverKit driver (beta, not yet tested with the X1).

Details about the user's machines are kept in `CLAUDE.local.md`, which is
not committed.

The user is not always next to the scanner. Do not assume hardware is
available; ask.

## Repository layout

- `docs/`: protocol, hardware chain, FlexColor internals, 3F format, journal.
- `tools/x1probe/`: read-only probe (C, IOKit SCSITaskUserClient).
- `tools/capture/`: lldb capture script for FlexColor on Mojave.
- `tools/decode/`: preview decoder (Python, numpy, Pillow).
- `X1Kit/`: Swift package (transport, protocol, preview sequence, image);
  `swift test` runs against the simulator, never against a real scanner.
- `app/`: macOS application. `X1Scan.xcodeproj` and `X1Scan/` (AppKit
  shell, SwiftUI palettes, String Catalog), `X1ScanCore/` (models and view
  models, `swift test`). The preview only runs on the virtual X1; the real X1
  is only read.
- `tools/git-hooks/`: `x1-check` (serial numbers, scan and firmware files, size,
  commit messages), run by the pre-commit and commit-msg hooks and by the CI.
- `.claude/agents/x1-reviewer.md`: pre-commit review subagent.
- `.github/workflows/x1kit.yml`: CI, runs `x1-check` on every pushed commit, builds
  X1Kit and runs its tests, tests X1ScanCore and builds the app.

Captures and raw files stay outside the repository (see `.gitignore`).

## When something new is learned

Update `docs/protocol.md` (with [confirmed] / [hypothesis]) and add a dated
entry to `docs/journal.md`.

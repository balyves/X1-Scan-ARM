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
       0x24 (32), 0x25 (24), 0x26 (56), 0x27 (20), 0x29 (14);
     - 0xD3 status / sensors `d3 00 00 00 02 00` (2);
     - 0xDF scanner state `df 00 00 00 02 00` (2);
     - 0xEE register, bank 1, addresses 0x04-0x19 only:
       `ee 00 00 00 01 AA 00 00 01 00` (1).

     Any other page, length, register or CDB byte counts as a command not
     seen in a capture (next point). See `docs/decisions.md`, "Read-only
     guard".

     `tools/x1probe` sends a subset of these reads (no 0xDF, no page 0x20, no page 0x24,
     only the longest read of pages 0x21 and 0x23).
   - **Any command that moves the scanner or changes its state** (0x24, 0xF0,
     0xE4, 0x1B, 0xDB, 0xCF, 0xD2, 0xE0, 0x55, 0x3B, or anything not seen in a
     capture) requires the user's **explicit approval before running**, must
     reproduce byte for byte a sequence captured from FlexColor, and must
     stop at the first unexpected status or response. In the app, the only
     path for such commands is `IOKitTransport(capturedSequence:)`, created
     in `AppModel.swift`.
   - **One exception to "byte for byte", for the scan only** (user's
     decision of 2026-11-17, docs/decisions.md, "Real X1: scan"): the
     target position (bytes 50-51) of the window right before `1b 00 08 06
     01 00` carries the position read on page 0x20 just before, as FlexColor
     does, only if it is within the position tolerance (256) of the captured
     one; otherwise the scan stops before that window. Every other byte of
     every command stays the captured one, and the guard
     (`CapturedSequenceGuard.scan`) accepts no other difference. The 0xDF
     state `00 06` is accepted only as the wait after that command, in the
     scan script.
   - Never guess parameter values for positions, motors or exposure.
5. **Instructions involving the scanner**: at every step, state explicitly
   the required state of the **X1 (on / off)** and of **FlexColor
   (open / closed)**. Only one program can open the scanner at a time.
6. **Git**: show `git status` and a summary of the diff, and wait for the
   user's approval before `git push`. Never force-push.
7. **Review before every commit**: run the `x1-reviewer` subagent
   (`.claude/agents/x1-reviewer.md`) on the changes, and show the user its
   full report together with `git status` and the diff summary. Fix or
   discuss every "Bloquant" item before committing. For interface changes,
   run the `x1-ui` subagent as well and show its opinion. The pre-commit hook
   (`tools/git-hooks`, install with `git config core.hooksPath
   tools/git-hooks`) and the X1Kit CI workflow are additional checks, not a
   substitute.

## Machines

- A reference Mac on **macOS 10.14 Mojave** with FlexColor 4.8.13 and the X1,
  used for captures (`tools/capture/cap3.py`, lldb, i386).
- Current Macs on **macOS 26 Tahoe** (Apple Silicon) for development and
  production. Apple removed FireWire in Tahoe; the X1 works there through
  the ASFireWire DriverKit driver (beta; complete preview with 0.6.0 on
  2026-11-16).

Details about the user's machines are kept in `CLAUDE.local.md`, which is
not committed.

The user is not always next to the scanner. Do not assume hardware is
available; ask.

## Repository layout

- `docs/`: protocol, hardware chain, FlexColor internals, 3F format, journal.
- `tools/x1probe/`: read-only probe (C, IOKit SCSITaskUserClient).
- `tools/capture/`: lldb capture script for FlexColor on Mojave, and its
  converter to fixtures.
- `tests/fixtures/`: FlexColor captures (anonymised; of image data, only the first
  64 bytes of each read).
  `preview-sequence.json` (warm, after earlier previews) is replayed by the
  virtual X1; `preview-sequence-cold.json` (right after power-on, without
  its page 0x28 read) and `preview-sequence.json` are the two sequences
  sent to the real X1; `preview-sequence-warm-2.json` is a
  second warm preview; `scan-sequence-1000ppi.json`, `-2000ppi`, `-3200ppi`
  are a preview then a scan each (docs/protocol.md §12), replayed only by
  the simulator in tests. See `tests/fixtures/README.md`.
- `tools/decode/`: preview and scan decoders (Python, numpy, Pillow;
  `decode_scan.py --compare` also needs tifffile).
- `X1Kit/`: Swift package (transport, protocol, preview sequence, image,
  scan decoding in `X1Image/ScanDecoding.swift`); `swift test` runs against
  the simulator, never against a real scanner.
- `app/`: macOS application. `X1Scan.xcodeproj` and `X1Scan/` (AppKit
  shell, SwiftUI settings panel and tool column, String Catalog), `X1ScanCore/` (models and view
  models, plus the reusable views of the compact settings panel in `UI/`,
  `swift test`). The preview runs on the virtual X1; on the real X1,
  only FlexColor's captured preview (cold or warm, chosen by the first page
  0x20 read), behind the hidden setting `EnableRealPreview`, a confirmation
  before every run and `CapturedSequenceGuard` built from both captures
  (docs/decisions.md, step 4 and "Real X1: cold or warm sequence").
  Otherwise the real X1 is only read.
- `tools/git-hooks/`: `x1-check` (serial numbers, scan and firmware files, size,
  commit messages), run by the pre-commit and commit-msg hooks and by the CI.
- `.claude/agents/x1-reviewer.md`: pre-commit review subagent.
- `.claude/agents/x1-ui.md`: read-only review of interface changes against
  `.claude/skills/compact-settings-panel/SKILL.md` (settings panel conventions).
- `.github/workflows/x1kit.yml`: CI, runs `x1-check` on every pushed commit, builds
  X1Kit and runs its tests, tests X1ScanCore and builds the app.

Captures and raw files stay outside the repository (see `.gitignore`).

## When something new is learned

Update `docs/protocol.md` (with [confirmed] / [hypothesis]) and add a dated
entry to `docs/journal.md`.

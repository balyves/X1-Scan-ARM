# Project decisions

Recorded on 2026-11-12. Change this file when a decision changes, and say
why.

## Platform

- **macOS 26 Tahoe only.**
- **Swift 6** (language mode 6, strict concurrency), **Xcode 26 or later**.

## Application

- **SwiftUI inside an AppKit shell.** Planned for later:
  - palettes docked on the right, collapsible to an icon bar, detachable as
    floating windows;
  - tool bar on the left;
  - full screen;
  - light and dark modes, Liquid Glass;
  - display colour managed by ColorSync.
- **Bilingual interface, English and French**, following the system
  language (String Catalog).

## Distribution

- **Not sandboxed.** The application opens the scanner through IOKit
  (SCSITaskUserClient).
- Distributed directly, **outside the Mac App Store**. Signed and notarised
  later.

## Scope of version 1

- Scan and **export a raw 16-bit TIFF**: linear RGB, with only the
  corrections needed to form the image (flat field from the white and dark
  references, R/B line-gap realignment). No colour profile, no curves.
- The architecture is ready for **non-destructive processing modules**
  working on linear data, added in this order: basic adjustments, then full
  FlexColor-style corrections.

## X1Kit (step 1, no user interface)

Swift package in `X1Kit/`:

| Module | Role |
|---|---|
| `X1Transport` | `SCSITransport` protocol; `IOKitTransport` (real scanner, through a small C layer `CX1IOKit` adapted from tools/x1probe); `SimulatedX1` (replays tests/fixtures). |
| `X1Protocol` | CDB construction and response parsing: INQUIRY, pages 0x20 and 0x26, 0xDF state, log page 0x30. |
| `X1Preview` | FlexColor 4.8.13's preview sequence and the runner that executes it. |
| `X1Image` | Flat field, line gap, 16-bit TIFF writer. |

## Scanner safety

### Read-only guard

`IOKitTransport` checks every command before any IOKit call. By default
(`CommandPolicy.readOnly`) only these reads are allowed, each with its
direction and a maximum length; the CDB length field must also match the
transfer length:

| Opcode | Command | Direction | Max bytes |
|---|---|---|---|
| 0x00 | TEST UNIT READY | none | 0 |
| 0x03 | REQUEST SENSE | in | 18 |
| 0x12 | INQUIRY | in | 96 |
| 0x4D | LOG SENSE | in | 52 |
| 0x5A | MODE SENSE(10) | in | 100 |
| 0xD3 | status / sensors | in | 2 |
| 0xDF | scanner state (`df 00 00 00 02 00`) | in | 2 |
| 0xEE | read register | in | 1 |

Everything else is refused unless `CommandPolicy.unrestricted` is chosen
explicitly. It is only for runs the user has approved (CLAUDE.md, rule 4).

### Preview sequence

- **Captured values, no invented rules.** Windows, modes, exposure data,
  read sizes and FlexColor's redundant page re-reads are sent byte for byte
  as captured.
- **Measured position (page 0x20, bytes 27-28).** FlexColor's rule for
  feeding the measurement back into the next window is not understood: it
  sometimes sends the measured value (8 971), sometimes another one (6 443
  measured, 6 250 sent). We send the captured values. On a real scanner, the
  preview stops if a measurement differs from the captured one by more than
  **100**. Two captures differed by 64 on the first measurement (25 803 /
  25 867); the others were identical. **Threshold to revise.**
- **Waits on 0xDF.** We poll 0xDF after exactly the commands where FlexColor
  polled it, until the state FlexColor last saw there: `00 00`, or `00 01`
  after SCAN. Only `08 01` and `08 40` are accepted meanwhile.
- **Stop at the first unexpected response**:
  - a status other than GOOD;
  - a wrong number of bytes;
  - an INQUIRY other than `Imacon` / `Flextight X1`;
  - a SCAN response other than `00 00`;
  - a measured position out of tolerance;
  - a line counter going back after SCAN;
  - an unknown 0xDF state, or a timeout.
- **Anomaly after SCAN (0x1B)**: send only `DB 00 00 00 00 00`, wait for
  0xDF to return `00 00`, and send nothing else. **Anomaly before SCAN**:
  send nothing more.

### Tests

- `SimulatedX1` replays tests/fixtures/preview-sequence.json:
  - commands must arrive in the captured order;
  - polled values are replayed in order;
  - image data is synthesised from preview-calibration-profile.json.
- **Conformance**: against the simulator, our preview sends the same CDB,
  direction, transfer length and data_out as FlexColor, in the same order,
  apart from polling commands, and waits on 0xDF at the same points.
- **Nothing in the test suite talks to a real scanner.** `IOKitTransport` is
  only tested unopened.

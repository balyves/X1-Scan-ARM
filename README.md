# X1-Scan-ARM

**Open-source scanning software for the Hasselblad Flextight X1 on modern macOS (Apple Silicon).**

> **Status: research.** The X1 protocol is being decoded from captures of
> FlexColor. Our tools can identify the scanner and decode a captured preview,
> but cannot drive a scan yet. Do not use anything in this repository on a real
> scanner unless a tool explicitly says it is read-only.

## Why

The Flextight X1 is still an excellent film scanner, but its only software,
FlexColor 4.8.13 for Mac, is a 32-bit Carbon/QuickTime application. It stopped
working with macOS 10.15 Catalina, and Hasselblad has ended support. Owners are
left with old Intel Macs running Mojave, or Windows machines with FireWire cards.

X1-Scan-ARM aims to let the X1 scan again from a current Mac.

## How it works (what we know so far)

- The X1 connects over **FireWire 800** and presents itself as a generic
  **SCSI device over SBP-2**. No proprietary kernel driver is involved.
- On macOS it can be reached through Apple's public **SCSITaskUserClient** API
  (IOSCSIArchitectureModelFamily).
- On Apple Silicon the hardware chain is: Thunderbolt 3 → Thunderbolt 2 adapter
  (A1790) → Thunderbolt → FireWire 800 adapter (A1463) → X1.
- **macOS 15 Sequoia** still includes Apple's FireWire stack.
  **macOS 26 Tahoe** removed it; the open-source
  [ASFireWire](https://github.com/mrmidi/ASFireWire) DriverKit driver is
  expected to provide the same SCSI device there (to be validated with the X1).
- Unlike older SCSI Flextights, the X1 **boots on firmware stored in its own
  flash memory**: no firmware upload is needed from the host for a preview.
  No Hasselblad firmware is distributed here.

See [`docs/`](docs/) for the protocol, the hardware chain and the project
journal, and [`tools/`](tools/) for the probe, capture and decode tools.

## Scope

- **Flextight X1 only.** Other Flextight / Imacon models are out of scope.
- Scanning first; image processing (3F files, film profiles) builds on existing
  open-source work where possible.

## Roadmap

1. ~~Read-only first contact: enumerate the device, INQUIRY, TEST UNIT READY,
   status and serial number.~~ Done (2026-11-12).
2. ~~Capture the real command sequence from FlexColor on a Mojave Mac.~~
   Initialisation and preview done (2026-11-12).
3. ~~Decode preview image data.~~ Done (2026-11-12).
4. Read-only calibration backup: read and save everything the scanner
   reports about itself with the read-only commands (vendor mode pages 0x20,
   0x21, 0x23, 0x25-0x27 and 0x29, those seen in the captures; log page 0x30;
   0xEE registers) before any command that changes its state. Whether EEPROM or flash contents can be read on the X1 is
   unknown; any command outside `CommandPolicy.readOnly` needs a capture and
   explicit approval. The backup will contain the scanner's serial number and
   stays outside the repository.
5. Capture a full-resolution scan.
6. Preview driven by our own code.
7. Full scan, 3F/TIFF output.
8. Colour: input profile from an IT8 target, film rendering.

Future ideas, not scheduled. Each depends on sequences captured from
FlexColor:

- Holder detection.
- HDR: a second, long-exposure pass.
- Multi-pass averaging.
- Scan all openings of a holder.
- Guided calibration.
- Image Capture and Photoshop integration.

## Related projects

- [eigenshell/flextight-shenanigans](https://github.com/eigenshell/flextight-shenanigans):
  protocol work on the SCSI Flextight Precision II.
- [rohanpandula/flexcolor-tool](https://github.com/rohanpandula/flexcolor-tool):
  FlexColor film profiles and 3F reader.
- [firenzemc/imaconfilm](https://github.com/firenzemc/imaconfilm):
  negative developer for .fff files.
- [wehw93/FlexColor-Next](https://github.com/wehw93/FlexColor-Next):
  3F editor for Apple Silicon (no scanner control).
- [mrmidi/ASFireWire](https://github.com/mrmidi/ASFireWire):
  FireWire on macOS 26 via DriverKit.
- [20More](https://20more.dk): commercial, closed-source software for
  Flextight scanners, including the X1, on macOS 10.13 to 15, with a web
  interface served by the scanner Mac, according to its website (checked
  2026-11-14). No public code or protocol documentation. X1-Scan-ARM
  targets macOS 26 Tahoe natively and stays open source.

## What this repository never contains

No Hasselblad software, firmware, FPGA bitstreams or film profiles. No scan
files. Contributions including such material will be refused.

## Disclaimer

This is an independent, non-commercial project. It is not affiliated with,
endorsed by, or supported by Hasselblad or Imacon. "Hasselblad", "Flextight",
"Imacon" and "FlexColor" are trademarks of their respective owners and are used
here only to describe compatibility.

Driving scanner motors with incorrect parameters can damage the hardware. Use at
your own risk.

## License

[MIT](LICENSE)

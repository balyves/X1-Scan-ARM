# X1-Scan-ARM

**Open-source scanning software for the Hasselblad Flextight X1 on modern macOS (Apple Silicon).**

> **Status: early research.** Nothing here can drive a scanner yet. Do not use
> anything in this repository on a real scanner unless a tool explicitly says it
> is read-only.

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
- The scanner needs its firmware uploaded at every power-up. **This firmware is
  Hasselblad property and is not distributed here.** The software will read it
  from the user's own FlexColor installation.

See [`docs/`](docs/) for protocol and file-format notes.

## Scope

- **Flextight X1 only.** Other Flextight / Imacon models are out of scope.
- Scanning first; image processing (3F files, film profiles) builds on existing
  open-source work where possible.

## Roadmap

1. Read-only first contact: enumerate the device, INQUIRY, TEST UNIT READY,
   status and serial number.
2. Capture the real command sequence from FlexColor on a Mojave Mac.
3. Firmware upload, calibration, preview.
4. Full scan, 3F/TIFF output.
5. Positive rendering matching FlexColor (film curves, highlight/shadow).

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

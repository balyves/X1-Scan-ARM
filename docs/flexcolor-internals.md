# FlexColor 4.8.13 for Mac: what static analysis shows

Written from analysis of the user's own installation, for interoperability.
No Hasselblad code or file is reproduced in this repository.

- Universal Mach-O binary, PowerPC + i386 only (no x86_64). Carbon
  application built in 2011 against the 10.4 SDK, C++, linked with Carbon,
  QuickTime, IOKit and Accelerate. This is why it stopped working with
  macOS 10.15: 32-bit, Carbon and QuickTime are all gone.
- No kernel extension and no driver in the bundle or the installer.
- Hardware access goes through a transport class built on Apple's public
  SCSITaskUserClient API, matching devices whose vendor identification is
  `Imacon` (also `Hasselbl`, `ColrCrsp`, `LEICA` for other products).
- The scanner logic is a large SCSI scanner class with methods for set
  window, read data, vendor mode pages (around 45 typed pages: drum, focus,
  CCD, motors, calibration, scanner status, EEPROM…), calibration (dark,
  white, light, focus, positions) and firmware/FPGA download. On the X1, the
  firmware download path is not used during a normal preview (see
  protocol.md §2).
- A model table selects the protocol variant per model. The X1 shares its
  family with the 848 and 646.
- The binary also contains a simulated scanner, used by Hasselblad for
  development without hardware.

## How the captures were made

`tools/capture/cap3.py` is an lldb script. FlexColor is started under lldb on
the Mojave Mac; breakpoints in Apple's SCSITaskLib (not in FlexColor) log
every CDB, the outgoing data, the SCSI status and the first bytes of every
response, and append image data to a file. FlexColor drives the scanner
normally; nothing is injected.

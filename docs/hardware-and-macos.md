# Hardware chain and macOS support

## Connecting an X1 to a current Mac

The X1 has a FireWire 800 (9-pin) port. On Macs without FireWire:

1. Apple Thunderbolt 3 (USB-C) to Thunderbolt 2 adapter (A1790).
2. Apple Thunderbolt to FireWire 800 adapter (A1463). It contains an OHCI
   controller (Agere/LSI FW643).
3. FireWire 800 cable, 9-pin to 9-pin.

Both adapters are discontinued (second-hand market). USB to FireWire adapters
do not work.

After the FireWire cable has been moved from one Mac to another, switch the
X1 off and on again: on 2026-11-16 the new Mac did not detect it otherwise
(observed once).

## macOS versions

- **Up to macOS 15 Sequoia**: Apple's FireWire stack (IOFireWireFamily,
  IOFireWireSBP2) is present, including on Apple Silicon through the adapter
  chain above. The X1 appears as a SCSI device.
- **macOS 26 Tahoe**: Apple removed the whole FireWire stack.
  [ASFireWire](https://github.com/mrmidi/ASFireWire) (DriverKit, Apache-2.0,
  beta) reimplements an OHCI host including SBP-2 through
  SCSIControllerDriverKit; Nikon Coolscan scanners are reported working.
  **Works with the X1** **[confirmed]**: identity reads, then a complete
  preview with ASFireWire 0.6.0 on 2026-11-16, large READs (up to 240 480
  bytes) included (docs/journal.md).

X1-Scan-ARM only depends on the SCSITaskUserClient layer
(IOSCSIArchitectureModelFamily), which still exists on Tahoe. The same
application code should therefore work with Apple's stack and with
ASFireWire.

## Reference setup used for captures

Intel Mac running macOS 10.14 Mojave with FlexColor 4.8.13, X1 connected
through the Thunderbolt to FireWire adapter. FlexColor is a 32-bit
Carbon/QuickTime application: it cannot run on macOS 10.15 or later.

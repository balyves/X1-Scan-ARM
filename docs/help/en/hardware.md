# Hardware and connection

This page describes the chain that connects the X1 to a recent Mac, and the driver needed on macOS 26 Tahoe.

## The connection chain {#chain}

X1: **off** while connecting.

The X1 has a FireWire 800 port (9-pin). A recent Mac has neither FireWire nor Thunderbolt 2. In order, from the Mac:

1. Apple Thunderbolt 3 (USB-C) to Thunderbolt 2 Adapter: model A1790, part number MMEL2.
2. Apple Thunderbolt to FireWire 800 Adapter: model A1463, part number MD464.
3. FireWire 800 cable, 9-pin at both ends, to the X1.

- These two Apple adapters are no longer sold new. They can be found second-hand.
- USB to FireWire adapters do not work.
- If the cable comes from another Mac, switch the X1 off and on again after connecting it.

## The ASFireWire driver {#asfirewire}

- macOS 26 Tahoe no longer has a FireWire driver.
- ASFireWire restores FireWire on macOS 26 Tahoe, with DriverKit.
- It is a **third-party project**, independent of X1 Scan, in **beta**.
- Repository: [github.com/mrmidi/ASFireWire](https://github.com/mrmidi/ASFireWire).
- Website, with the installation guide: [www.asfw.net](https://www.asfw.net/).
- Install it by following the guide on its website.

## Checking the installation {#installation}

X1: **either** (nothing is sent to the scanner). FlexColor: **either**.

- Choose Help › Check Installation….
- One line per element: macOS, the Thunderbolt to FireWire adapter, the ASFireWire driver, the X1.
- ✓: the element is in place. ⚠: it is missing, or to be checked. Each line has a link to its help.
- The window updates by itself every 2 seconds: plug in the adapter or switch the X1 on, and the line changes.
- X1 Scan only reads the list of the Mac’s devices. It does not open the scanner.
- While the driver is not active, its line gives ASFireWire’s links.
- At launch, and on leaving discovery mode, the window opens by itself if the adapter or the driver is missing.
- It cannot tell an X1 switched off from a cable unplugged. A driver installed but not allowed yet may not show.

## Checking the connection {#check}

X1: **on**. FlexColor: **closed**.

- Choose Scanner › Scanner Information (⌘I), then “Read Identity”.
- If the X1 is not found, see [No X1 found](troubleshooting.md#no-scanner).

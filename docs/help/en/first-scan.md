# Your first scan, step by step

This page follows the whole path, from connecting the scanner to the saved file.
Every step that involves the scanner gives the state the X1 must be in.

> On the real X1, preview and scan are being validated. Today you can follow this whole path in [discovery mode](discovery.md), without a scanner.

## 1. Connect the X1 {#connect}

X1: **off**.

- The X1 has a FireWire 800 port.
- On a Mac without FireWire, you need two Apple adapters: Thunderbolt 3 (USB-C) to Thunderbolt 2, then Thunderbolt to FireWire 800.
- USB to FireWire adapters do not work.
- If the cable comes from another Mac, switch the X1 off and on after connecting it.

## 2. Install ASFireWire {#asfirewire}

X1: **either**.

- macOS 26 Tahoe no longer has a FireWire driver.
- The ASFireWire driver (DriverKit) replaces it.
- Install it as its instructions say, then allow it in System Settings.
- X1 Scan needs macOS 26 Tahoe.

## 3. Switch the X1 on and check {#check}

X1: **on**. FlexColor must be **closed**: only one program can open the scanner.

- Choose Scanner › Scanner Information (⌘I).
- Click “Read Identity”.
- The model and firmware appear. Only reads are sent.
- If a message appears, see [Troubleshooting](troubleshooting.md).

## 4. Put the film in the holder {#holder}

X1: **on**. FlexColor: **closed**.

- Put the film in the holder, and the holder in the X1.
- In the panel, Prepare tab, choose the [film and the holder](prepare.md#original).

## 5. Run a preview {#preview}

X1: **on**, holder in place. FlexColor: **closed**.

- Click “Preview” at the bottom of the panel, or choose Scanner › Preview (⌘R).
- The image builds up line by line.
- “Stop” (⌘. or Esc) stops the preview at any time.
- After the preview, the [exposure](information.md#exposure) is measured.

## 6. Frame the image {#framing}

X1: **either** (nothing is sent to the scanner).

- Turn the image if needed: [Orientation](prepare.md#orientation).
- Draw the frame with the [Crop](tool-crop.md) tool.
- Straighten with the [Straightening Rule](tool-rule.md).

## 7. Scan {#scan}

X1: **on**, nothing moved since the preview. FlexColor: **closed**.

- First choose an [export folder](output.md#folder): the scan is saved there.
- Click “Scan” at the bottom of the panel.
- The bottom bar shows the focusing, then the image lines.

## 8. Save {#save}

X1: **either**.

- At the end, the scan is saved as it is in the export folder, with its recipe.
- Choose File › Export… (⇧⌘E) to write a turned, straightened and cropped version: see [Output](output.md).

# Discovery mode

Discovery mode lets you try X1 Scan without a scanner.

## Entering the mode {#enter}

- Choose File › Try Without a Scanner.
- At launch, if the source is the real X1 and no X1 is found, the “No X1 found” message also offers “Try Without a Scanner”.
- X1: **either**. Discovery mode never uses the scanner, even when it is connected and on.

## What works {#features}

- A banner above the image reminds you: “Discovery mode — no scanner connected”.
- The [preview](first-scan.md#preview), [framing](prepare.md#framing), the tools and the [scan](scan.md#scan-button) work as with a scanner.
- The image comes from a simulated X1: a test pattern. The preview also has one patch too bright and one too dark, to try the [exposure zones](tool-exposure-zones.md).

## Sample files {#files}

- A file exported or scanned in discovery mode has the suffix “_sample” in its name.
- Its TIFF description and its recipe mark it as a sample. It is not a scan.

## Leaving the mode {#leave}

- Click “Leave Discovery Mode” in the banner, or choose File › Leave Discovery Mode.
- X1 Scan goes back to the source used before. If it is the real X1, it looks for it again.
- If it is not found, the “No X1 found” message appears again, with “Try Without a Scanner”.
- While in discovery mode, the source cannot be changed in Settings › Scanner.

# Output

The Output tab (⌥⌘3) sets the exported file.

## Format {#format}

- RGB 16-bit linear, RGB 8-bit sRGB, Grey 16-bit linear or Grey 8-bit sRGB.
- 8-bit uses a provisional sRGB curve and profile. It has fewer levels than 16-bit linear.

## Compression {#compression}

- None, LZW or ZIP. All of them are lossless.

## File name {#name}

- A name template, with parts such as {roll}, {frame}, the date or a number.
- The name of the next file is shown below it.
- The button on the right opens Settings › Export to edit the templates.

## Folder {#folder}

- “Choose…” chooses the folder where Export and the scan save the files.
- Also in File › Choose Export Folder…
- “Show in Finder” shows the last exported file.

## Export {#export}

- File › Export… (⇧⌘E) writes the image shown, turned, straightened and cropped.
- A recipe (`.x1recipe.json`) is written next to it.
- A saved scan is never replaced: its versions are named _v1, _v2…
- An existing file is never overwritten.

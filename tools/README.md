# tools

All tools run on macOS. Quit FlexColor first: only one program can open the
scanner at a time.

## git-hooks/

`pre-commit` blocks a commit whose staged files contain a serial number
(`FX1` + 7 digits, as text or as hex bytes on one line), scan / raw /
firmware files (`.fff`, `.3f`, `.raw`, `.bit`, `MICROCOD*`, `oscode*`), or a
file larger than 2 MiB. It does not detect hex bytes split across two lines
or UTF-16 text, and it also blocks decimal byte lists that look like the
hex form (`46, 58, 31, ...`). Submodules are skipped. If a check cannot run, the commit is blocked. Install it
once per clone, from the repository root:

    git config core.hooksPath tools/git-hooks

## x1probe/ (read-only)

`diag.sh` reports how macOS sees the scanner (FireWire, IOKit, drivers)
without sending it anything.

`x1probe.c` opens the X1 through SCSITaskUserClient and sends only the read
commands FlexColor itself sends at start-up (INQUIRY, TEST UNIT READY,
REQUEST SENSE, vendor mode pages, log page 0x30, registers, 0xD3). A strict
whitelist blocks anything else.

    clang -o x1probe x1probe.c -framework IOKit -framework CoreFoundation
    ./x1probe | tee x1probe.txt

Its output contains your serial number: remove it before sharing.

## capture/ (observation)

`cap3.py` logs every SCSI command FlexColor sends, the responses, and the
image data, using lldb breakpoints in Apple's SCSITaskLib. Mojave Mac only
(FlexColor is 32-bit). Image data goes to `~/Desktop/x1-apercu.raw`.

    lldb --arch i386 -o "command script import /path/to/cap3.py" -o run \
      "/Applications/FlexColor 4.8.13/FlexColor.app/Contents/MacOS/FlexColor" \
      2>&1 | tee capture.txt

## decode/

`decode_preview.py` turns a capture into a PNG (Python 3, numpy, Pillow).

    python3 decode_preview.py capture.txt x1-apercu.raw preview.png

Captures and raw files are not committed (see `.gitignore`).

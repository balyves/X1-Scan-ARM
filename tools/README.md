# tools

All tools run on macOS. Quit FlexColor first: only one program can open the
scanner at a time.

## git-hooks/

`x1-check` blocks:

- a scanner serial number (`FX1` + 7 digits, any case), as text or as hex
  bytes on one line, in file contents, file names and commit messages;
- scan, image, raw or Hasselblad files, in any case: `.fff`, `.3f`, `.3fr`,
  `.raw`, `.tif`, `.tiff`, `.bit`, `.dtp`, `.a3`, `MICROCOD*`, `oscode*`,
  `osloader*`;
- files larger than 2 MiB.

Limits:

- not detected: hex bytes split across two lines, UTF-16 text, hex glued
  to a preceding letter or digit;
- known false positive: decimal byte lists that look like the hex form
  (`46, 58, 31, ...`);
- submodules are skipped;
- the `commit-msg` hook also reads git's editor template (not the diff of
  `git commit -v`), so committing the removal of a file whose name holds a
  serial number is blocked: use `git commit -m` for that commit;
- the `commit-msg` hook ignores what follows git's scissors line and its
  "Do not modify or remove the line above." warning (the diff added by
  `git commit -v`). A message that copies both lines by hand gets past the
  hook, but not past the CI, which checks recorded messages in full.

If a check cannot run, the result is a failure.

It runs in three places:

- the `pre-commit` hook, on staged files;
- the `commit-msg` hook, on the message;
- the CI (`.github/workflows/x1kit.yml`), on every commit of a push to
  `main` or of a pull request. The CI cannot be bypassed with
  `--no-verify`, and it also catches a file added in one commit and removed
  in the next.

Install the hooks once per clone, from the repository root:

    git config core.hooksPath tools/git-hooks

Check by hand: `tools/git-hooks/x1-check --staged`, `--commit SHA` or
`--range BASE HEAD`.

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

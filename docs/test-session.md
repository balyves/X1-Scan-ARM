# Next session at the scanner: test procedure

A step-by-step procedure to follow on site. Every step states the machine,
the required state of the **X1** (on / off) and of **FlexColor** (open /
closed), as CLAUDE.md rule 5 requires. **Only one program can open the X1
at a time**, and the X1 is connected to **one Mac at a time**.

Machines (details in `CLAUDE.local.md`, not committed):

- **Development Mac**: Apple silicon, macOS 26 Tahoe. X1 Scan, `x1probe`,
  ASFireWire. FlexColor does not run on it.
- **Reference Mac**: Intel, macOS 10.14 Mojave. FlexColor 4.8.13, lldb,
  `cap3.py`.

Safety, for the whole session:

- On the development Mac, **our tools send only reads** (CLAUDE.md rule 4):
  the X1 Scan app checks every command against `CommandPolicy.readOnly`,
  and `x1probe` has its own whitelist. Preview is disabled on the real X1.
  What **ASFireWire itself** sends to the X1 when it enumerates it is
  outside our control **[hypothesis: SBP-2 login, then standard SCSI
  commands such as INQUIRY]**.
- On the reference Mac, **FlexColor drives the scanner** as it always did;
  `cap3.py` only observes (lldb breakpoints in Apple's SCSITaskLib), it
  injects nothing.
- Stop at the first unexpected behaviour (noise, error, a scanner that does
  not answer): X1 off, note what happened, do not retry blindly.
- Captures and logs contain the **serial number**: they never go into the
  repository (part D).

## Part A: preparation

A1 to A3 and A5 are done at home; A4 is done on site, before part C.

### A1. Time Machine backup

- Machine: development Mac. X1: not connected. FlexColor: not on this Mac.
- Run a full Time Machine backup and let it finish before installing a
  system extension.

### A2. Install ASFireWire

- Machine: development Mac. X1: not connected. FlexColor: not on this Mac.
- Source: the official site, <https://www.asfw.net/install/> (linked from
  the project's README, <https://github.com/mrmidi/ASFireWire>). On
  2026-11-14 the site offered **ASFW 0.6.0, build 33**, a signed and
  notarised DMG, with its SHA-256; Apple silicon, macOS 26 or later; SIP
  stays enabled. Follow the site if it now says otherwise.
- Compare the download with the SHA-256 shown on the site:

      shasum -a 256 ~/Downloads/ASFW-*.dmg

- Copy `ASFW.app` to `/Applications`, open it, click **Install**, then
  approve the extension in **System Settings > General > Login Items &
  Extensions**.
- Check that it is active:

      systemextensionsctl list | grep -i asfw

  Expected: `net.asfw.driver` marked `[activated enabled]`. ASFireWire's
  wiki says that activation alone does not prove the driver started: also
  look at the driver status in the ASFW app.
- To uninstall (if anything goes wrong, or after the session): remove the
  extension with the ASFW app. If that is not possible:

      systemextensionsctl uninstall F6YA6B56LR net.asfw.driver

  If the command refuses, use the app; **never disable SIP** for this.
  Check that `systemextensionsctl list` no longer lists it, and only then
  delete `ASFW.app`. Deleting the app alone does **not** remove the
  extension. Do not delete anything in `/Library/SystemExtensions` by hand.
- ASFireWire is beta and **has not been tested with the X1** (only Nikon
  Coolscan scanners are reported working over SBP-2).

### A3. Tools on the development Mac

- Machine: development Mac. X1: not connected. FlexColor: not on this Mac.
- Create the session folder (outside any repository); every later command
  on this Mac uses `$S`:

      S=~/X1-captures/$(date +%F); mkdir -p "$S"; echo "$S"

  In a new Terminal window, set `S` again to the same folder.
- Build `x1probe`:

      cd ~/Developer/X1-Scan-ARM/tools/x1probe
      clang -o x1probe x1probe.c -framework IOKit -framework CoreFoundation

- `diag.sh` needs no build; check it runs (it only reads the system's
  view, it sends nothing to a scanner):

      zsh ~/Developer/X1-Scan-ARM/tools/x1probe/diag.sh

- Build and start the app; check that it launches, that a preview runs on
  the **virtual X1**, and that Scanner > Real X1 shows "Real X1 · Not read":

      cd ~/Developer/X1-Scan-ARM/app && xcodebuild -project X1Scan.xcodeproj \
        -scheme X1Scan -configuration Debug \
        -derivedDataPath ~/Library/Developer/Xcode/DerivedData/X1Scan-cli build
      open ~/Library/Developer/Xcode/DerivedData/X1Scan-cli/Build/Products/Debug/"X1 Scan.app"

  Switch back to Scanner > Virtual X1 and quit the app.
- Copy `tools/capture/cap3.py` to a USB stick (it is needed on the
  reference Mac in A4; it gained the `X1CAP_RAW` and `X1CAP_SCAN_MB`
  options).

### A4. Tools on the reference Mac (on site, before part C)

- Machine: reference Mac (Mojave). X1: off, or not connected. FlexColor:
  closed.
- Copy `cap3.py` from the USB stick to `~/X1-tools/cap3.py`.
- Create the session folder and check the free space (allow several GB):

      S=~/X1-captures/$(date +%F); mkdir -p "$S"; df -h "$S"

### A5. Things to take

- Machine: none. X1: not concerned. FlexColor: not concerned.
- Apple Thunderbolt 3 (USB-C) to Thunderbolt 2 adapter.
- Apple Thunderbolt to FireWire 800 adapter.
- FireWire 800 cable, 9-pin to 9-pin.
- The USB stick with `cap3.py`.
- The IT8.7/1 target (transparency) and a holder that takes it.
- A notebook (or a text file) for the notes asked for below.

## Part B: ASFireWire test, on the development Mac, read-only

Whether `x1probe` and the app can see the X1 at all depends on ASFireWire
publishing it as a SCSI device that SCSITaskUserClient can open
**[hypothesis]**. If it does not, "no Imacon / Hasselblad scanner found"
is the expected outcome: it says nothing about the scanner. Note the
`diag.sh` report then.

### B1. Connect

- Machine: development Mac. **X1: off.** FlexColor: not on this Mac.
  X1 Scan: closed.
- Connect in this order: Thunderbolt 3 to Thunderbolt 2 adapter on the
  Mac, Thunderbolt to FireWire 800 adapter, FireWire 800 cable, X1.
- Then switch the **X1 on** and wait until it is idle (about a minute).

### B2. diag.sh

- Machine: development Mac. **X1: on.** FlexColor: not on this Mac.
  X1 Scan: closed.

      zsh ~/Developer/X1-Scan-ARM/tools/x1probe/diag.sh

- The report is written on the Desktop; move it to `$S`. Look for
  `Imacon` / `Flextight X1` and for an `IOSCSIPeripheralDeviceNub` of
  type 6.

### B3. x1probe

- Machine: development Mac. **X1: on.** FlexColor: not on this Mac.
  **X1 Scan: closed** (only one program can open the X1).
- It sends only the reads of its whitelist (INQUIRY, TEST UNIT READY,
  REQUEST SENSE, vendor mode pages, log page 0x30, registers, 0xD3), with
  the CDBs FlexColor sends:

      cd ~/Developer/X1-Scan-ARM/tools/x1probe
      ./x1probe | tee "$S/x1probe-tahoe.txt"

### B4. Read Identity in the app

- Machine: development Mac. **X1: on.** FlexColor: not on this Mac.
  `x1probe`: finished.
- Open X1 Scan, choose **Scanner > Real X1**, then **Scanner > Read
  Identity**. It sends INQUIRY, MODE SENSE page 0x26, LOG SENSE 0x30 and
  0xDF, then closes the device. The Scanner Information window opens and
  shows the result.

### B5. Expected results

- Machine: development Mac. X1: on. FlexColor: not on this Mac.
- INQUIRY: vendor `Imacon`, product `Flextight X1`, revision `R185`.
- Mode page 0x26: the serial number (`FX1` followed by digits; shown
  masked in the app unless Settings > General says otherwise).
- Bottom bar: "Real X1 · Identity read". The counters of log page 0x30 are
  in the Scanner Information window.

### B6. Notes to take

- Machine: development Mac. X1: on. FlexColor: not on this Mac.
- Results of B2 to B4: what appeared, what did not, the exact error texts
  (the app's message, `x1probe`'s output).
- `systemextensionsctl list | grep -i asfw` and the driver status shown by
  the ASFW app.
- macOS and ASFW versions (`sw_vers`, the app's About).

### B7. If the X1 does not appear

- Machine: development Mac. X1: on. FlexColor: not on this Mac.
  X1 Scan: closed.
- Check the extension: `systemextensionsctl list | grep -i asfw`.
- Collect the system log of the last minutes, for ASFireWire and SCSI:

      log show --last 10m --predicate 'subsystem CONTAINS[c] "asfw" OR process CONTAINS[c] "asfw"' \
        > "$S/asfw-log.txt"
      log show --last 10m --predicate 'eventMessage CONTAINS[c] "SCSI" OR eventMessage CONTAINS[c] "SBP"' \
        > "$S/scsi-log.txt"

- Try once more: X1 off, wait 10 seconds, X1 on, repeat B2. Do not try
  anything else on the scanner; part C does not depend on part B.

### B8. Disconnect

- Machine: development Mac. **X1: on, then off.** FlexColor: not on this
  Mac. X1 Scan and `x1probe`: closed.
- Switch the **X1 off first**, then unplug the FireWire cable.
- If ASFireWire is not kept, uninstall it (A2) at home.

## Part C: capture of a real scan, on the reference Mac (Mojave)

### C1. Connect

- Machine: reference Mac. **X1: off.** FlexColor: closed.
- Connect the X1 to the reference Mac (as for the captures of 2026-11-12),
  then switch the **X1 on** and wait until it is idle.

### C2. One lldb session per capture

- Machine: reference Mac. **X1: on.** **FlexColor: closed** (lldb starts
  it).
- Each capture is one run: lldb starts FlexColor, you do one thing, you
  quit FlexColor, lldb ends. Set `N` to the capture's name **before every
  run**: `cap3.py` deletes its `.raw` file when it starts, and `tee`
  overwrites the log, so reusing a name destroys the previous capture.
  Check with `ls` that the name is new.
- `X1CAP_SCAN_MB` limits the image data written after each SCAN (0x1B) to
  a contiguous start of the scan; calibration reads are never skipped.
  With 64 MiB the whole preview is kept, and a usable start of a
  high-resolution scan.

      cd "$S"; ls
      N=01-preview
      X1CAP_RAW="$S/$N.raw" X1CAP_SCAN_MB=64 \
        lldb --arch i386 -o "command script import ~/X1-tools/cap3.py" -o run \
        "/Applications/FlexColor 4.8.13/FlexColor.app/Contents/MacOS/FlexColor" \
        2>&1 | tee "$S/$N.txt"

- Before using FlexColor, check that lldb printed the two `cap3.py :`
  lines (breakpoints set, and the `X1CAP_SCAN_MB` limit). If not, quit
  FlexColor and start again.

### C3. The captures

All with **X1: on**, **FlexColor: open under lldb** (started by the command
of C2, with the `N` given here), on the reference Mac.

1. `N=01-preview`: insert the IT8.7/1 target in its holder, run one
   **preview**, quit FlexColor.
2. `N=02-scan-a`: preview, then select a **small area** of the target (a
   few patches) and run a **high-resolution scan** of it. Quit FlexColor.
3. `N=03-scan-b` and `N=04-scan-c`: the **same area** at **two other
   resolutions**. Quit FlexColor after each.

For every capture, note:

- the **holder** used: type and **reference number** (the number
  written on it, e.g. 50200403), and the frame position; the reference may
  show up in the scanner's responses (docs/protocol.md §4);
- FlexColor's settings: resolution (ppi), output size, scan area, film type
  (positive / negative, 16-bit), sharpening, gradation, colour settings,
  and anything else changed from the defaults;
- **screenshots** of FlexColor's settings windows and of the selected area
  (check that no client name or serial number is visible on them);
- the number of `RAW skipped` lines in the log (`grep -c "RAW skipped"
  "$S/$N.txt"`): if most of the scan was skipped, a smaller area keeps
  more of it;
- anything unexpected (noise, warnings, time taken).

### C4. Finish

- Machine: reference Mac. **X1: on, then off.** FlexColor: closed (lldb has
  ended).
- Switch the **X1 off**, then unplug the FireWire cable if needed.

## Part D: after the session

### D1. What stays outside the repository

- Capture logs (`*.txt` from lldb), image data (`*.raw`), `x1probe`
  output, `diag.sh` reports, system logs and screenshots: they contain the
  scanner's **serial number** (page 0x26 responses) and possibly other
  personal data.
- Keep them in the session folders (`~/X1-captures/<date>/` on both Macs)
  and in their backups, never under `~/Developer/X1-Scan-ARM/`. The
  pre-commit hook blocks `.raw` files and serial numbers, but it is a last
  check, not the plan.

### D2. What to pass on for the analysis

- The capture logs of part C (`01-preview.txt` … `04-scan-c.txt`), with
  the serial number replaced by `FX1xxxxxxx` (search for `FX1`, and for the
  hex bytes `46 58 31` in the `REP` lines of mode page 0x26).
- An extract of the image data: the `.raw` files written with
  `X1CAP_SCAN_MB`.
- The notes and screenshots of the FlexColor settings for each capture.
- The notes of part B (results, versions, error texts, logs).

Before decoding captures 02 to 04: `tools/decode/decode_preview.py` treats
every read after the first SCAN as image data, so the calibration of a
scan that follows a preview would be taken for image lines. It needs
adapting first.

What is learned then goes into `docs/protocol.md` (marked [confirmed] or
[hypothesis]) and a dated entry of `docs/journal.md`.

# Next session at the scanner: test procedure

A step-by-step procedure to follow on site. Every step states the machine,
the required state of the **X1** (on / off) and of **FlexColor** (open /
closed), as CLAUDE.md rule 5 requires. **Only one program can open the X1
at a time**, and the X1 is connected to **one Mac at a time**. **After
moving the FireWire cable from one Mac to the other, switch the X1 off and
on again**: on 2026-11-16 the new Mac did not detect it otherwise
(observed once).

Machines (details in `CLAUDE.local.md`, not committed):

- **Development Mac**: Apple silicon, macOS 26 Tahoe. X1 Scan, `x1probe`,
  ASFireWire. FlexColor does not run on it.
- **Reference Mac**: Intel, macOS 10.14 Mojave. FlexColor 4.8.13, lldb,
  `cap3.py`.

Safety, for the whole session:

- On the development Mac, **our tools send only reads** (CLAUDE.md rule 4):
  the X1 Scan app checks every command against `CommandPolicy.readOnly`,
  and `x1probe` has its own whitelist. Preview is disabled on the real X1
  unless the hidden setting `EnableRealPreview` is set (part E).
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
- ASFireWire is beta. With the X1, version 0.6.0 ran identity reads, then a
  complete preview on 2026-11-16 (E8).

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
  the **virtual X1**, and that with Settings > Scanner > Source: Real X1 the
  bottom bar shows "Real X1 · Not read":

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
  Starting from "X1: off" also covers a cable just moved from the other Mac,
  which needs the X1 switched off and on again.

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
- Open X1 Scan, choose **Settings > Scanner > Source: Real X1**, then
  **Scanner > Scanner Information… (⌘I)** and its **Read Identity** button.
  It sends INQUIRY, MODE SENSE page 0x26, LOG SENSE 0x30 and 0xDF, then
  closes the device. The window shows the result.

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

- Try once more: X1 off, wait 10 seconds, X1 on, repeat B2 (this is also
  what a cable just moved from the other Mac needs). Do not try anything
  else on the scanner; part C does not depend on part B.

### B8. Disconnect

- Machine: development Mac. **X1: on, then off.** FlexColor: not on this
  Mac. X1 Scan and `x1probe`: closed.
- Switch the **X1 off first**, then unplug the FireWire cable.
- If ASFireWire is not kept, uninstall it (A2) at home.

## Part C: capture of a real scan, on the reference Mac (Mojave)

### C1. Connect

- Machine: reference Mac. **X1: off.** FlexColor: closed.
- Connect the X1 to the reference Mac (as for the captures of 2026-11-12),
  then switch the **X1 on** and wait until it is idle. Starting from
  "X1: off" also covers a cable just moved from the development Mac, which
  needs the X1 switched off and on again.

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

## Part E: first preview on the real X1, on the development Mac

Step 4 of the application: FlexColor's captured preview replayed on the
real X1 (docs/decisions.md, "Application, step 4"). Since 2026-11-16 the
app sends only the sequence FlexColor sends **right after power-on**: the
X1 must be switched on just before each preview (docs/decisions.md, "Real
X1: the sequence right after power-on only"). It is the first time
our code sends commands that move the scanner. Parts A to B must have
passed: ASFireWire active, Read Identity working. "FlexColor: closed"
below means: FlexColor does not run on the development Mac, and the
reference Mac is not connected to the X1.

Known risks, as written before the first run:

- Before the run of 2026-11-16, no large READ had gone through ASFireWire
  (Read Identity only reads a few bytes). The first READ of 47 952 bytes
  comes during calibration, the first of 120 240 bytes with the references,
  those of 240 480 bytes during the scan. All of them went through in the
  complete preview of 2026-11-16 (E8).
- A READ cannot be interrupted while it waits: **Stop can take up to 30 s**
  to act during the scan. After a READ that times out (30 s), the run stops
  with the stop command.

### E1. Build and enable

- Machine: development Mac. **X1: off.** **FlexColor: closed.** X1 Scan:
  closed.
- Build the app at the step 4 commit (A3), then turn the hidden setting on:

      defaults write org.x1scanarm.X1Scan EnableRealPreview -bool YES

- Create the session folder if needed: `S=~/X1-captures/$(date +%F); mkdir -p "$S"`.
  The app writes its logs there by itself.

### E2. Connect and check with reads only

- Machine: development Mac. **X1: off.** **FlexColor: closed.** X1 Scan:
  closed.
- Connect as in B1 (X1 off first, also when the cable was just moved from
  the other Mac), then switch the **X1 on** and wait until it is idle.
  Do nothing else with the scanner from now on except Read Identity
  below (reads only): the preview needs the state of a freshly switched-on
  X1. If anything else ran, switch the X1 off and on again.
- Machine: development Mac. **X1: on.** **FlexColor: closed.**
- Open X1 Scan, Settings > Scanner > Source: **Real X1**. Scanner > Scanner
  Information… (⌘I), button **Read Identity**: expect `Imacon` / `Flextight X1` / `R185`. If this fails, stop
  here (part B7).

### E3. The original

- Machine: development Mac. **X1: on** (just switched on, only Read
  Identity since). **FlexColor: closed.** X1 Scan: open, source Real X1.
- As in the capture right after power-on, where the user inserted the
  holder after FlexColor was opened, just before the preview: only now,
  after Read Identity and just before E4, put the IT8.7/1 target in **the
  6×7 holder, reference 50200403** (the one of the captures of 2026-11-12
  and 2026-11-16) and insert it. Wait until the X1 has drawn it in and is
  quiet.
- In the panel, choose this holder (Original > Holder; tick it first in
  Settings > Holders if needed).
- Difference with the capture: FlexColor read the scanner's identity and
  pages when it opened, before the holder was inserted; X1 Scan sends the
  same reads when the preview starts, after it. Only reads differ in
  timing, not in content. **[hypothesis]**: no effect.

### E4. The preview

- Machine: development Mac. **X1: on.** **FlexColor: closed.** X1 Scan:
  open, source Real X1, nothing else open on the scanner (`x1probe`
  finished).
- Click **Preview** in the panel (or ⌘R). Tick the four checks (X1 on,
  holder in place, FlexColor closed, X1 switched off and on since the last
  real preview; for the first run of the day, the X1 switched on in E2
  counts), then click **Start Preview** (Return does not start it).
- Watch the scanner. The bottom bar shows the phases (initialising,
  calibrating, references, scanning, finishing). **Stop** (⌘. or Esc)
  stays available: before SCAN nothing more is sent, after SCAN only the
  stop command, then the app waits for the scanner to be ready. During the
  scan, wait up to 30 s for Stop to act.
- If something sounds or looks wrong and Stop has not acted after 30 s,
  switch the X1 off, then quit X1 Scan (it may wait up to 2 minutes for a
  ready state that will not come; force quit if needed).

### E5. What can happen

- **Preview complete** (X1: on). The image appears; note the duration.
  Then E6.
- **Not just switched on** (X1: on, then off). The alert says the preview
  only runs right after the scanner is switched on, and gives bytes 19-24
  of page 0x20 in its text. Only reads, D2 and the session start were sent
  (no window, mode, exposure, image read or SCAN). Switch the X1 off, wait 10 seconds, on again, and go
  back to E2.
- **Stopped before SCAN**, by an anomaly or by Stop (X1: on, then off).
  The alert gives the reason (for a position beyond the tolerance of 100,
  the measured and the captured value) and says to switch the X1 off and on
  again: **switch the X1 off, wait 10 seconds, on again** before anything
  else. Do not retry until the log has been looked at.
- **Stopped after SCAN**, by an anomaly, a READ timeout (30 s) or Stop
  (X1: on, then off). The alert gives the outcome of the stop sequence.
  - The scanner reported ready: switch it off and on again before another
    preview (the end of session is not sent on the stop path).
  - It did not report ready: **switch the X1 off**. This can be a false
    alarm (a state that is not one of the observed busy states, protocol.md
    §7, or no `00 00` within 120 s), but the scanner's state is then unknown.
- **Refused by the guard** (alert or log line `ERREUR … refused by
  policy`): nothing was sent for that command; same as stopped before or
  after SCAN, depending on where it happened.

### E6. After the run

- Machine: development Mac. **X1: on, then off.** **FlexColor: closed.**
- The alert and the log give the files:
  `~/X1-captures/<date>/x1scan-apercu-<time>.txt` and `.raw`.
- Turn the hidden setting off, set the source back to Virtual X1:

      defaults delete org.x1scanarm.X1Scan EnableRealPreview

- Switch the **X1 off**, then disconnect (B8).

### E7. Comparing with the FlexColor capture

- Machine: any, X1 not used. **FlexColor: closed.** The commands, polls
  left out, should be the same as in the FlexColor capture right after
  power-on (`flexcolor-froid.txt`, 2026-11-16):

      cmds() { grep -E '^[0-9]{4} CDB' "$1" | cut -c10- | grep -vE '^(ee|d3|df) '; }
      diff <(cmds flexcolor-froid.txt) <(cmds x1scan-apercu-<time>.txt)

  An empty diff (or one that ends where the run stopped) is what the guard
  enforces. Each CDB line of our log is written before the command is sent;
  a command the guard refused has an `ERREUR … refused by policy` line under
  it and was not sent. Compare also the `REP` lines of page 0x20 (measured
  positions) and the 0xDF states.
- Pass on the log with the serial number replaced by `FX1xxxxxxx` (part
  D2), the `.raw` file, the holder reference and the duration.

### E8. Result of 2026-11-16, 15:14: success

- Development Mac, macOS 26 Tahoe, ASFireWire 0.6.0, sequence right after
  power-on.
- Complete preview. The 208 commands outside polling were identical, byte
  for byte, to `flexcolor-froid.txt` (E7: empty diff); 380 statuses, all
  0x00; 0xDF states `08 01`, `08 02`, `08 03`, `08 06`, `08 07`, `08 40`,
  then `00 00`; end with `DB` and `CF 00 02 80`.
- Decoded image correct: mean white about 54 148 / 52 342 / 44 168, dark
  about 314 / 288 / 305 (R/G/B).
- The log stays outside the repository (part D1). Details in
  docs/journal.md.

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
real X1 (docs/decisions.md, "Application, step 4"). Since 2026-11-17 the
app sends FlexColor's sequence **right after power-on** or its sequence
**after earlier use**, chosen by the scanner's first status read; any
other state stops the preview before any window, mode, exposure or image
read; only reads, the startup command and the session start come before
it (docs/decisions.md,
"Real X1: cold or warm sequence"). Switching the X1 on just before the
first preview of the day remains the simplest start. It was the first time
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
- Click **Preview** in the panel (or ⌘R). Tick the checks (X1 on, holder
  in place, FlexColor closed; after a real preview that did not complete, a
  fourth one: the X1 was switched off and on since), then click **Start
  Preview** (Return does not start it). The app only knows about its own
  runs on this Mac: if a preview was interrupted on the other Mac, or in
  FlexColor, switch the X1 off and on first. The log says which sequence was
  chosen, and notes every position that differs from the capture.
- Watch the scanner. The bottom bar shows the phases (initialising,
  calibrating, reading references, then "Preview: n of m lines" while the
  image is read, finishing). **Stop** (⌘. or Esc)
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

## Part F: first scan on the real X1, on the development Mac

FlexColor's captured 2 000 ppi scan replayed on the real X1
(docs/decisions.md, "Real X1: scan"). Done on 2026-11-18 (F4). The scan
needs a complete real preview first (part E) and the
**same holder as the capture** (6×7, reference 50200403), with the film
left in place.

### F1. Enable

- Machine: development Mac. **X1: off.** **FlexColor: closed** (it does not
  run on Tahoe; the reference Mac must not be connected to the X1). X1
  Scan: closed.
- Turn the hidden setting on, in addition to `EnableRealPreview`:

      defaults write org.x1scanarm.X1Scan EnableRealScan -bool YES

### F2. Preview, then scan

- Machine: development Mac. **X1: on.** **FlexColor: closed.** X1 Scan:
  open, source Real X1.
- Run a complete real preview (part E4). Scan stays disabled until one has
  completed, and again after every scan: one complete preview before each
  scan, as in the captures. An export folder must be chosen.
- Do not move the holder. Click **Scan**, tick both boxes (same holder,
  nothing moved; the capture's frame and resolution: 609 × 614 pixels at
  2 000 ppi), then **Start Scan**.
- The bottom bar shows the phases: calibration, "Focusing: n of 400
  lines", "White and black references", "Image: n of 1 064 lines".
  Stop (⌘. or Esc) as for the preview.
- At the end the image replaces the preview and the TIFF is saved in the
  export folder; the bottom bar gives its name.

### F3. After the scan

- Machine: development Mac. **X1: on.** **FlexColor: closed.**
- Keep the log `~/X1-captures/<date>/x1scan-scan-<HHmmss>.txt` and `.raw`
  (outside the repository; it holds the serial number). Check the
  "position:" lines, and decode it if needed:
  `tools/decode/decode_scan.py <log>.txt <log>.raw out.png`.
- If the scan stopped: switch the X1 off and on; the next preview asks for
  it, and Scan needs a new complete preview.

### F4. Result of 2026-11-18, 08:39: success

- macOS 26 Tahoe, cold preview, then the scan. Log
  `x1scan-scan-083930.txt` (outside the repository): 746 exchanges, no
  error status. Focus step: measured position 16 779, 128 above the
  captured 16 651, substituted within the tolerance (256).
- TIFF 609 × 614 pixels, RGB 16-bit, 2 000 ppi; image correct, checked
  outside the app.
- Three corrections were needed that morning, each after a stopped run
  (docs/journal.md):
  1. 0xDF `08 00` right after the final `DB` of a preview: accepted after
     a final or emergency `DB`;
  2. 0xDF `08 00` after `08 01` in a wait of the cold preview (step 81):
     accepted in every wait right after an accepted `08 xx`;
  3. page 0x20 line counter going from 11 to 10 during the scan's white
     and black references (step 458): checked in the image phase only.
- In the app the scanned image was shown stretched vertically (the
  preview's pixel aspect ratio of 3 applied to the scan); fixed, scan
  pixels are shown square.
- `EnableRealPreview` and `EnableRealScan` were turned off afterwards.


## Part G: captures for the window calculator and the holder previews

FlexColor captures on the reference Mac (Mojave), one log per FlexColor
launch, kept outside the repository (they hold the serial number). Purpose: the rules behind the scan windows (docs/protocol.md §9,
§12) and one first preview per holder (§13). Nothing is sent by X1 Scan.

**Guided**: `tools/capture/guided-session.sh` (copy the `tools/capture/`
folder to the reference Mac) walks through steps 1-22 (part H: steps
23-32, `--part H`; part I: steps 33-41, `--part I`; part K: steps 42-50,
`--part K`). It starts each
FlexColor run under lldb with `cap3.py` and a new name (`essai-I`,
`essai-J1`…, `-2` added if the name exists), waits for FlexColor to be
quit, shows each step in French with the state of the X1 and FlexColor,
notes the time of each step in `essai-notes.txt`, takes screenshots (the
whole screen and every FlexColor window), and puts everything in `~/Desktop/captures-<date>/`.
`--from N` resumes at step N (a new FlexColor run, with a preview first
if N is in the middle of essai-I; on another day, give the first day's
folder with `X1GUIDE_DIR`); `--list` lists the steps;
`X1GUIDE_DRY_RUN=1` tries it without FlexColor, in a separate folder. It
sends nothing to the X1: only FlexColor talks to the scanner. It checks
that `cap3.py` set its breakpoints and its image limit, tells when
FlexColor or lldb ended abnormally, and a Ctrl-C stops the guide only
(lldb runs in its own process group). If it stops, check that FlexColor
has been quit before resuming. Unlike the manual C2, lldb runs in batch
mode: if FlexColor stopped on a signal, lldb would quit (and end
FlexColor) instead of waiting for `continue`; none of the captures so far
had such a stop. Not yet tried on the reference Mac.

Before starting:

- Machine: reference Mac (Mojave). Connect as in C1: **X1: off**, cable
  on the reference Mac, then **X1: on**. **FlexColor: closed.**
- Every "launch FlexColor" below means: FlexColor **open under lldb with
  `cap3.py`** as in C2, with a new name `N` each time (`N=essai-I`,
  `N=essai-J1`… : a name used again overwrites its log and its `.raw`),
  and `X1CAP_SCAN_MB` set for the scans. Quitting FlexColor ends that
  capture.
- The X1 must have made at least one preview since it was switched on;
  otherwise the preview of step 1 is a cold one (first page 0x20 read
  2 048 × 3): it is still useful, note it.
- For every scan, keep FlexColor's TIFF and note the frame FlexColor shows
  (X, Y, width, height) and the resolution; a screenshot is enough. TIFFs
  and screenshots stay outside the repository; check that no serial number
  or client name shows on the screenshots (C3).
- Note the reference printed on each holder.
- Never touch FlexColor's Format menu.
- At the end: as in C4 (FlexColor closed, X1 off).

### G1. Window calculator: 6×7 holder, same film, one capture ("essai-I")

**X1: on.** FlexColor: launched once at step 1, closed at step 14. The
scans follow each other without a new preview (as in
`scan-sequence-2000ppi-twice.json`).

1. Launch FlexColor, make a preview.
2. Frame 1.0 × 1.0 cm **at the centre** of the opening: scan at 600 ppi.
3. Same frame: 1 000 ppi.
4. Same frame: 1 500 ppi.
5. Same frame: 2 000 ppi.
6. Same frame: 2 500 ppi.
7. Same frame: 3 200 ppi.
8. 1.0 × 1.0 cm at 2 000 ppi, frame about 5 mm from the **left edge** of
   the opening.
9. The same, about 5 mm from the **right edge**.
10. The same, about 5 mm from the **top**.
11. The same, about 5 mm from the **bottom**.
12. Centred frame of **3.0 × 1.0 cm** (wide) at 2 000 ppi.
13. Centred frame of **1.0 × 3.0 cm** (tall) at 2 000 ppi.
14. Quit FlexColor.

### G2. One first preview per holder (FlexColor launched each time)

**X1: on** throughout. For each step: FlexColor **closed**, change the
holder, launch FlexColor, make a preview, quit FlexColor. Note the format
FlexColor shows. The 6×7 is already captured
(`preview-sequence-warm-3.json` to `-5`).

15. 6×6 / 6×4.5 → essai-J1 (already a first preview in
    `holders/holder-preview-1-6x6-6x45.json`, after another holder; here
    after the 6×7).
16. 6×6×2 → essai-J2.
17. 24×36 → essai-J3; before quitting, **also** a scan of a centred
    1.0 × 1.0 cm frame at 1 000 ppi.
18. 4×5 → essai-J4; before quitting, **also** the same scan at 1 000 ppi.
19. 24×36×6 → essai-J5.
20. 6×9 → essai-J6.
21. 24×36×4 → essai-J7.

The scans of steps 17 and 18, against step 3 (1 000 ppi, 6×7), show how
offsets 54 / 58 depend on the holder.

### G3. Optional: cold start

22. FlexColor **closed**, **X1: off**. Switch the X1 on, launch FlexColor,
    make a preview with the 6×7 holder → essai-K. Note which holder was
    used last in FlexColor. It shows which cold calibration windows
    FlexColor sends: ratio 16 000 000 and offsets 54 / 58 = 354 583 /
    576 354 (as on 2026-11-16), or 32 000 000 and 454 612 / 856 631 (as on
    2026-11-18, protocol.md §12).

### G4. Result of 2026-11-18, 14:11-15:48

Steps 1-22 done with the guided script, no error or stop. Step 1 was a
cold-type preview. Step 6 was scanned at 3 000 ppi, step 12 kept a
1.0 × 1.0 cm frame (so no wide frame was captured), step 17 was first
made with the 24×36×4 by mistake and made again with the 24×36
(`essai-J3-2`). Analysis: docs/protocol.md §9 ("Window rules"), §12, §13;
`tests/fixtures/scan-windows-2026-11-18.json`.

## Part H: offset 62 of the focus window (one capture, "essai-L")

Purpose: offset 62 of the 400-line window follows 15 500 + 28 800 × the
middle of the frame's image lines in inches, within −6 to +21
(docs/protocol.md §9). The residual looks like rounding: one line is 8.6
units at 2 000 ppi, 28.8 at 600 ppi, 5.4 at 3 200 ppi (line pitch = ratio
÷ 10 000 lines per inch, §9). The windows give the frame only in whole
lines. So the key scans are one frame left untouched at three line
pitches: if offset 62 stays the same, FlexColor computes it from the frame
itself; if it follows the rounded lines, from the window. Then a few more
positions and heights, each with another (unknown) fraction of a line.
Same set-up as part G (reference Mac, cap3.py, the guide), **X1: on**,
FlexColor launched by the guide, 6×7 holder with the IT8 target, the
Format menu not touched. `tools/capture/guided-session.sh --part H` (or
`--from 23`) walks through the steps; a run of part G never goes on into
part H.

23. Launch FlexColor (essai-L), make a preview.
24. Check that FlexColor's Zoom is 100 % (it scans at PPP × zoom). Frame
    0.50 × 0.50 cm at the centre of the opening (frame P0): scan at
    2 000 ppi.
25. The same frame, **untouched**: 600 ppi.
26. The same frame, **untouched**: 3 200 ppi.
27. The same frame moved down by the smallest step FlexColor allows (the
    down arrow if FlexColor moves the frame with the keyboard, otherwise
    the shortest drag; probably more than one line): 2 000 ppi.
28. One more step down: 2 000 ppi.
29. One more step down: 2 000 ppi.
30. Without moving it, height 0.51 cm (width 0.50): 2 000 ppi.
31. Without moving it, height 0.52 cm: 2 000 ppi.
32. Quit FlexColor.

At every scan, note the width and height FlexColor shows (all decimals);
the screenshots keep them too. If FlexColor stops in the middle, the guide
starts a new run with a preview and a new frame P0 (resuming at step 25
or 26, it has step 24 made again first, so that the new frame has its
2 000 ppi scan). The guide notes the size typed at each scan in
`essai-notes.txt`. Keep FlexColor's TIFFs
and the screenshots outside the repository. At 600 ppi the frame is about
200 lines, fewer than the 400 of the focus step: a possible limit case
(part G's 1.0 cm frame at 600 ppi, about 400 lines, followed the rule).
About 15 minutes.

### H1. Result of 2026-11-19, 08:21-08:44

Done with the guide, still with the original calibration. FlexColor's
zoom was at 160 %: the scans were made at 3 200 ppi ("2 000") and 960
ppi ("600"), and FlexColor offered no more than 2 000 ppi at step 26. At
step 27 a scan was started by mistake and cancelled during the 400-line
step (essai-L session 5). At steps 30 and 31, the heights typed (0.53,
0.52) were not taken: FlexColor showed 0.50 again and the windows did not
change. Analysis: docs/protocol.md §9 (offset 62), §12;
`tests/fixtures/scan-windows-2026-11-19.json`. The steps of 27-29 moved
the frame by 17, then 33 and 33 lines (offset 18: 7 828, 7 845, 7 878,
7 911): about 1/160 in, one pixel of the 160 ppi preview (33.3 lines at
5 333 lines per inch), the step FlexColor's keyboard or mouse gave.

What the heights show: a change of up to 0.03 cm of output height (0.19
mm on the film at that zoom, about two preview lines) left the frame
exactly as it was. Either FlexColor's step for that field is coarser, or
the value was not taken (validation, linked width and height, or the
zoom). These captures cannot tell which. To find out: zoom 100 %, type
0.60 then Tab, and note what FlexColor shows.

## Part I: first preview of the holders still missing (captures "essai-M1" to "M9")

Purpose: a first preview of each holder whose run starts exactly like our
warm sequence (`preview-sequence.json`) up to the holder code read, so
that X1 Scan can later go on with that holder's captured preview
(docs/decisions.md, "Holder detection"). FlexColor starts a run with the
settings of the holder of the previous run: a run follows one with a 6×7,
6×6 / 6×4.5, 6×6×2 or 6×9 holder, and the 6×7 runs of steps 38 and 40 only
reset that. The 6×6 and 6×6×2 come again with another original, to see
whether the second low-resolution pass depends on it (protocol.md §13).
Same set-up as part G, **X1: on** throughout, FlexColor **closed** before
each step and launched by the guide; one preview per run, then quit; the
Format menu not touched. `tools/capture/guided-session.sh --part I` (or
`--from 33`); resuming at 34-37, 39 or 41 asks whether the previous
FlexColor run had a 6×7-type holder, and otherwise sends back to the
previous 6×7 step.

33. 6×7 → essai-M1.
34. 6×9 → essai-M2.
35. 6×6 / 6×4.5, another film (or the same placed differently) → essai-M3.
36. 6×6×2, another film → essai-M4.
37. 4×5 → essai-M5.
38. 6×7 (reset) → essai-M6.
39. 24×36×6 → essai-M7.
40. 6×7 (reset) → essai-M8.
41. 24×36 / 36×24 (two openings, one horizontal and one vertical;
    labelled "24x35 / 35x24") → essai-M9.

At each step the guide asks for the reference printed on the holder and
the format FlexColor shows, and notes both. Starting at step 33, it also
asks which holder the previous FlexColor run had and notes it. About 25
minutes.

### I1. Result of 2026-11-19, 08:45-09:12

Done with the guide. The references typed were not the numbers (the
question was unclear; the guide now asks for the number). Codes,
sequences and preview windows: docs/protocol.md §13.

## Part J: check after the X1 is recalibrated (no real preview or scan by X1 Scan before J3's verdict; J1 reads only)

Context: on 2026-11-20 another program recalibrates the X1 and writes the
new calibration into the scanner. Every capture and real run up to
2026-11-19 was made with the original calibration. X1 Scan replays
FlexColor's sequences byte for byte and checks positions read on page
0x20 (tolerance 256): if the recalibration changed what the X1 answers,
a real run would stop at the first unexpected response (the intended
safe behaviour). This part checks first, with reads and FlexColor only.

### J1. Reads only, development Mac

- **X1: off**, FlexColor closed on the other Mac, cable on the
  development Mac (B1), then **X1: on**, idle. X1 Scan: Source Real X1.
- Scanner > Scanner Information… (⌘I), Read Identity. Keep a screenshot
  (serial masked by the app) in `~/X1-captures/<date>/`.
- Optionally `tools/x1probe` (B3), output saved in the same folder.
- `EnableRealPreview` and `EnableRealScan` stay **off**.
- **X1: off** before moving the cable.

### J2. FlexColor captures, reference Mac

- **X1: off**, cable on the reference Mac (C1), **FlexColor: closed**.
- Cold preview: `guided-session.sh --from 22` (X1 off then on, 6×7, essai-K).
- Warm previews: `guided-session.sh --part I` (all holders) or at least
  its step 33 (6×7), then part H if there is time.
- **FlexColor: closed**, **X1: off** at the end (C4). Pass on the folder
  for analysis.

### J3. Comparison (analysis, nothing sent)

The new captures are compared with `preview-sequence-cold.json`,
`preview-sequence.json` and the part G and I captures of 2026-11-18/19:
commands and data sent, the first page 0x20 read (2 048 × 3 cold), the
positions read before each window (cold: 14 219 ± 256 after
`F0 00 00 01 01 01`), pages 0x21-0x29, the windows' offsets 54 / 58 and
the holder codes. Result:

- the same within the tolerances: J4 may be run;
- different: no real run of X1 Scan; new fixtures and the user's decision
  first.

### J4. Only after J3 says so: X1 Scan on the real X1

- **X1: on**, cable on the development Mac (B1; X1 off while moving it),
  **FlexColor: closed** (on the reference Mac).
- As parts E (cold preview) and F (preview then scan), with the hidden
  settings turned on for the run only and a confirmation before each run.
- A stop on an unexpected response is the expected safe behaviour: keep
  the `x1scan-*` logs and pass them on; do not retry with other settings.
- Turn `EnableRealPreview` and `EnableRealScan` off again afterwards.
  **X1: off** at the end.

## Part K: offset 62 again, zoom 100 % (one capture, "essai-N")

Purpose: part H was made with FlexColor's zoom at 160 % (docs/protocol.md
§9): its untouched frame was read at 3 200 and 960 ppi only, and FlexColor
may have moved the frame to its output pixel grid at each resolution.
Here, zoom 100 %: one frame at four resolutions, untouched, to tell
whether offset 62 follows FlexColor's own frame coordinates (then the
four values are equal) or the window's rounded lines (then they follow
the window); then two moves of one preview pixel (about 1/160 in) and the
last position again at 600 ppi. Same set-up as part H (reference Mac,
cap3.py, the guide), **X1: on**, FlexColor launched by the guide, 6×7
holder with the IT8 target, the Format menu not touched.
`tools/capture/guided-session.sh --part K` (or `--from 42`).

42. Launch FlexColor (essai-N), set the Zoom to **100 %**, make a preview
    (the guide notes the zoom shown).
43. Frame 0.50 × 0.50 cm at the centre (frame P0): scan at 3 200 ppi.
44. The same frame, **untouched**: 2 000 ppi.
45. The same frame, **untouched**: 1 000 ppi.
46. The same frame, **untouched**: 600 ppi.
47. Down by one preview pixel (one press of the down arrow): 3 200 ppi.
48. Down by one more preview pixel: 3 200 ppi.
49. That frame, **untouched**: 600 ppi.
50. Quit FlexColor.

Before each scan the guide asks for the zoom FlexColor shows and does
not go on until it is 100 (FlexColor might change it when a size is
typed). If FlexColor stops in the middle, the guide starts a new run with
a preview and a new frame P0, and has step 43 made again first. The guide
notes the size typed at each scan. **Keep FlexColor's TIFFs**, outside the
repository: their sizes show FlexColor's output pixel grid at each
resolution. FlexColor shows no frame position (only width, height, zoom,
size and PPP): the screenshots are the only record of where the frame is.
About 15 minutes.

What will be conclusive: four values equal (±1) at steps 43-46 mean that
FlexColor computes offset 62 from its own frame coordinates. Different
values do not by themselves mean that it follows the window's lines: a
frame moved to the output pixel grid at each resolution also changes it.
To tell those apart, per resolution: offset 18 and the lines of the
window, the TIFF size, and the size shown. Expected size of the effect:
at 600 ppi a window line is 28.8 units (1 000 lines per inch), so if
offset 62 follows the window it may differ from the 3 200 ppi value by up
to about 14 units. To be made before the X1 is recalibrated (2026-11-20), like
parts H and I.

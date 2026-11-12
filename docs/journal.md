# Project journal

## 2026-11-12: first contact with a real X1

Setup: Flextight X1, Intel Mac Pro on macOS 10.14 Mojave, FlexColor 4.8.13.

1. **Enumeration**: the X1 appears in IOKit as a standard SBP-2 SCSI scanner
   (type 6), `Imacon` / `Flextight X1` / `R185`, open to SCSITaskUserClient.
2. **First commands from our own code** (`tools/x1probe`): INQUIRY,
   TEST UNIT READY and REQUEST SENSE answer correctly, cold, without
   FlexColor ever having run.
3. **Initialisation captured** (lldb): FlexColor only reads (INQUIRY, vendor
   mode pages, log page, registers). No firmware download: the X1 runs from
   flash.
4. **Our tool replays these reads**: the serial number is in vendor mode page
   0x26.
5. **Preview captured** with the scanner's responses: full sequence
   (calibration, positioning loop, SCAN, line counter, READ, stop) and wait
   rule on 0xDF.
6. **Preview decoded without FlexColor** (`tools/decode`): RGB 16-bit LE
   interleaved, flat field from the calibration lines, one-line R/B gap, 3:1
   aspect. Geometry identical to FlexColor's preview of an IT8.7/1 target.

Lesson: FlexColor's alert "Impossible de terminer votre requête à cause de ."
means another program already has the scanner open.

Next: capture a full-resolution scan; replay a preview from our own code.

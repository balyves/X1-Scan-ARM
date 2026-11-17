// SPDX-License-Identifier: MIT
import X1Protocol
import X1Transport

/// FlexColor 4.8.13's scan session at 2 000 ppi, as captured on 2026-11-17
/// (tests/fixtures/scan-sequence-2000ppi.json, second session, seq 834-1760;
/// docs/protocol.md §12). Seq numbers in comments.
///
/// Every value is the captured one, except one: the target position of the
/// window of the 400-line step (offset 50), which FlexColor set to the
/// position read just before, and which the runner sets the same way, within
/// the tolerance of the captured 16 651 (`.positionWindow`; docs/decisions.md,
/// "Real X1: scan"). The frame (offsets 14, 22, 26 of the image window) and
/// the resolution are those of the capture: 609 × 614 pixels at 2 000 ppi.
///
/// The session must start warm (no scan right after power-on was captured):
/// its first page 0x20 read must show values left by earlier use.
public enum ScanScript {
    /// Pixels per line sent by the scanner: 609 asked + 24 (docs/protocol.md §10).
    public static let pixelsPerLine = 633
    /// Pixels per full-width calibration line: 7 992 + 24.
    public static let calibrationPixelsPerLine = 8016
    /// Position captured just before the 400-line window, and its target there.
    public static let capturedFocusPosition = 16651

    public static let flexColor4813Scan2000ppi: [PreviewStep] = {
        var builder = ScanBuilder()
        builder.build()
        return builder.steps
    }()
}

/// SET WINDOW descriptors of the scan session, exactly as captured.
enum ScanWindow {
    /// The frame: ratio 33 333 333 (2 000 ppi), first pixel 2 005, 609 px,
    /// 1 065 lines, target 0. Seq 862
    static let frame = bytes("""
        00 00 00 00 00 00 00 3c 00 00 55 a0 fc 01 d5 07 00 00 02 03 00 00 61 02 00 00 29 04 00 00 00 00 00 00 \
        00 00 00 00 00 00 00 00 00 00 00 00 00 00 01 01 00 00 00 00 dd 6e 06 00 51 81 0a 00 8c 3c 00 00 00 00
        """)
    /// Full CCD (7 992 px) at 2 000 ppi, target 0. Seq 866, 874
    static let fullWidth = bytes("""
        00 00 00 00 00 00 00 3c 00 00 55 a0 fc 01 00 00 00 00 02 03 00 00 38 1f 00 00 29 04 00 00 00 00 00 00 \
        00 00 00 00 00 00 00 00 00 00 00 00 00 00 01 01 00 00 00 00 dd 6e 06 00 51 81 0a 00 8c 3c 00 00 00 00
        """)
    /// The 400-line step: ratio 21 674 665, 609 px, 401 lines, target 16 651
    /// (replaced at run time by the position just read). Seq 892
    static let focus = bytes("""
        00 00 00 00 00 00 00 3c 00 00 a9 ba 4a 01 d5 07 00 00 00 00 00 00 61 02 00 00 91 01 00 00 00 00 00 00 \
        00 00 00 00 00 00 00 00 00 00 00 00 00 00 01 01 0b 41 00 00 ed 95 06 00 61 a8 0a 00 c0 67 00 00 00 00
        """)
    /// As `fullWidth`, offsets 54 and 58 850 less. Seq 1305
    static let fullWidthAfterFocus = bytes("""
        00 00 00 00 00 00 00 3c 00 00 55 a0 fc 01 00 00 00 00 02 03 00 00 38 1f 00 00 29 04 00 00 00 00 00 00 \
        00 00 00 00 00 00 00 00 00 00 00 00 00 00 01 01 00 00 00 00 8b 6b 06 00 ff 7d 0a 00 8c 3c 00 00 00 00
        """)
    /// As `frame`, offsets 54 and 58 850 less. Seq 1589
    static let frameAfterFocus = bytes("""
        00 00 00 00 00 00 00 3c 00 00 55 a0 fc 01 d5 07 00 00 02 03 00 00 61 02 00 00 29 04 00 00 00 00 00 00 \
        00 00 00 00 00 00 00 00 00 00 00 00 00 00 01 01 00 00 00 00 8b 6b 06 00 ff 7d 0a 00 8c 3c 00 00 00 00
        """)

    private static func bytes(_ hex: String) -> [UInt8] {
        guard let bytes = [UInt8](hex: hex) else { preconditionFailure("invalid captured hex") }
        return bytes
    }
}

struct ScanBuilder {
    private(set) var steps: [PreviewStep] = []

    private mutating func add(_ command: SCSICommand, _ kind: PreviewStep.Kind = .command) {
        steps.append(PreviewStep(command: command, kind: kind))
    }

    private mutating func thenWait(_ state: ScannerState = .ready) {
        steps[steps.count - 1] = steps[steps.count - 1].waiting(for: state)
    }

    private mutating func page(_ page: UInt8, _ length: Int) { add(X1Command.modeSense(page: page, length: length)) }
    private mutating func status(_ captured: Int) {
        add(X1Command.modeSense(page: ScanStatusPage.page, length: ScanStatusPage.length),
            .scanStatus(capturedPosition: captured))
    }
    private mutating func mode(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) { add(X1Command.setMode(a, b, c, d)) }
    private mutating func window(_ descriptor: [UInt8]) { add(X1Command.setWindow(descriptor)) }
    private mutating func exposure() { add(X1Command.exposure(Window.exposure)) }
    private mutating func read(lines: UInt8, calibration: Bool, pixels: Int, _ purpose: PreviewStep.ReadPurpose) {
        add(X1Command.read(lines: lines, calibration: calibration,
                           bytes: Int(lines) * pixels * PreviewScript.bytesPerPixel), .read(purpose))
    }

    /// The page reads FlexColor repeats at the start of a session (seq 837-850).
    private mutating func pageSet() {
        add(X1Command.inquiry(), .inquiry)
        page(0x27, 20)
        for _ in 0..<4 { page(0x25, 24) }
        page(0x21, 12); page(0x21, 100)
        page(0x29, 14)
        page(0x21, 12); page(0x21, 100)
        page(0x23, 12); page(0x23, 60)
        page(0x26, 56)
    }

    mutating func build() {
        // 1. Session start, seq 834-851. The first page 0x20 read must show values left by earlier use.
        add(X1Command.session(.start)); thenWait()
        pageSet()
        add(X1Command.modeSense(page: ScanStatusPage.page, length: ScanStatusPage.length), .startState(.warm))
        thenWait()

        // 2. Calibration at the scan resolution, seq 853-876.
        mode(0, 0, 1, 1); thenWait()
        page(0x27, 20)
        page(0x27, 20); thenWait()
        window(ScanWindow.frame); thenWait()
        window(ScanWindow.fullWidth); thenWait()
        exposure(); thenWait()
        exposure(); thenWait()
        window(ScanWindow.fullWidth); thenWait()
        mode(1, 1, 1, 1); thenWait()

        // 3. The 400-line step (focus, [hypothesis]), seq 887-1302.
        status(ScanScript.capturedFocusPosition); thenWait()
        page(0x24, 32)
        status(ScanScript.capturedFocusPosition); thenWait()
        add(X1Command.setWindow(ScanWindow.focus), .positionWindow(capturedPosition: ScanScript.capturedFocusPosition))
        thenWait()
        add(X1Command.focusSweep(), .scan); thenWait(.afterFocusSweep)
        for _ in 0..<400 { read(lines: 1, calibration: false, pixels: ScanScript.pixelsPerLine, .focusLine) }
        add(X1Command.stop()); thenWait()

        // 4. White (5 × 10 lines) and dark (18 × 10 lines) at full width, seq 1305-1587.
        window(ScanWindow.fullWidthAfterFocus); thenWait()
        mode(1, 1, 0, 1); thenWait()
        for _ in 0..<5 { read(lines: 10, calibration: true, pixels: ScanScript.calibrationPixelsPerLine, .scanReference) }
        thenWait()
        mode(1, 0, 0, 1); thenWait()
        status(ScanScript.capturedFocusPosition)
        for _ in 0..<18 { read(lines: 10, calibration: true, pixels: ScanScript.calibrationPixelsPerLine, .scanReference) }
        status(ScanScript.capturedFocusPosition)

        // 5. The image, seq 1589-1744: 41 priming lines, 51 blocks of 20 lines and one of 3.
        window(ScanWindow.frameAfterFocus); thenWait()
        add(X1Command.scan(), .scan); thenWait(.afterScan)
        for _ in 0..<41 { read(lines: 1, calibration: false, pixels: ScanScript.pixelsPerLine, .leadIn) }
        for _ in 0..<51 {
            status(ScanScript.capturedFocusPosition)
            read(lines: 20, calibration: false, pixels: ScanScript.pixelsPerLine, .image)
        }
        status(ScanScript.capturedFocusPosition)
        read(lines: 3, calibration: false, pixels: ScanScript.pixelsPerLine, .image)

        // 6. Stop and end of session, seq 1745-1760.
        add(X1Command.stop()); thenWait()
        add(X1Command.session(.end)); thenWait()
    }
}

// SPDX-License-Identifier: MIT
import X1Protocol
import X1Transport

/// FlexColor 4.8.13's preview sequence, as captured on 2026-11-12
/// (tests/fixtures/preview-sequence.json, seq numbers in comments).
///
/// Every value is the captured one: windows, modes, exposure data, read
/// sizes and the redundant page re-reads. No rule is inferred. Polling of
/// 0xEE and 0xD3 is left out; 0xDF is polled where FlexColor polled it, until
/// the state FlexColor last saw there.
public enum PreviewScript {
    /// Pixels per preview line (1 998 requested + 6). [confirmed]
    public static let previewPixelsPerLine = 2004
    /// RGB, 16 bits per channel.
    public static let bytesPerPixel = 6

    public static let flexColor4813: [PreviewStep] = {
        var builder = Builder()
        builder.buildFlexColor4813()
        return builder.steps
    }()
}

// MARK: Captured data

/// SET WINDOW descriptors (68 bytes), exactly as captured. Field notes in docs/protocol.md §9.
enum Window {
    /// Full CCD (7 992 px), ratio 32 000 000, field 26 = 3, target 0. seq 252
    static let calibrationA = bytes("""
        00 00 00 00 00 00 00 3c 00 00 00 48 e8 01 00 00 00 00 00 00 00 00 38 1f 00 00 03 00 00 00 00 00 00 00 \
        00 00 00 00 00 00 00 00 00 00 00 00 00 00 01 01 00 00 00 00 d4 ef 06 00 37 12 0d 00 8c 3c 00 00 00 00
        """)
    /// As A with field 26 = 2. seq 257
    static let calibrationB = bytes("""
        00 00 00 00 00 00 00 3c 00 00 00 48 e8 01 00 00 00 00 00 00 00 00 38 1f 00 00 02 00 00 00 00 00 00 00 \
        00 00 00 00 00 00 00 00 00 00 00 00 00 00 01 01 00 00 00 00 d4 ef 06 00 37 12 0d 00 8c 3c 00 00 00 00
        """)
    /// As B with target 25 000. seq 269
    static let target25000 = bytes("""
        00 00 00 00 00 00 00 3c 00 00 00 48 e8 01 00 00 00 00 00 00 00 00 38 1f 00 00 02 00 00 00 00 00 00 00 \
        00 00 00 00 00 00 00 00 00 00 00 00 00 00 01 01 a8 61 00 00 d4 ef 06 00 37 12 0d 00 8c 3c 00 00 00 00
        """)
    /// As A with target 9 000. seq 272
    static let target9000 = bytes("""
        00 00 00 00 00 00 00 3c 00 00 00 48 e8 01 00 00 00 00 00 00 00 00 38 1f 00 00 03 00 00 00 00 00 00 00 \
        00 00 00 00 00 00 00 00 00 00 00 00 00 00 01 01 28 23 00 00 d4 ef 06 00 37 12 0d 00 8c 3c 00 00 00 00
        """)
    /// As A with target 8 971 (the position measured at seq 285). seq 286
    static let target8971 = bytes("""
        00 00 00 00 00 00 00 3c 00 00 00 48 e8 01 00 00 00 00 00 00 00 00 38 1f 00 00 03 00 00 00 00 00 00 00 \
        00 00 00 00 00 00 00 00 00 00 00 00 00 00 01 01 0b 23 00 00 d4 ef 06 00 37 12 0d 00 8c 3c 00 00 00 00
        """)
    /// Full CCD, ratio 8 000 000, field 26 = 2, byte 49 = 4. seq 322
    static let calibrationRatio8M = bytes("""
        00 00 00 00 00 00 00 3c 00 00 00 12 7a 00 00 00 00 00 00 00 00 00 38 1f 00 00 02 00 00 00 00 00 00 00 \
        00 00 00 00 00 00 00 00 00 00 00 00 00 00 01 04 00 00 00 00 d4 ef 06 00 37 12 0d 00 8c 3c 00 00 00 00
        """)
    /// Preview: ratio 2 666 666, 1 998 px, 823 lines, byte 49 = 4, target 0. seq 341, 345, 353, 634
    static let preview = bytes("""
        00 00 00 00 00 00 00 3c 00 00 aa b0 28 00 00 00 00 00 00 00 00 00 ce 07 00 00 37 03 00 00 00 00 00 00 \
        00 00 00 00 00 00 00 00 00 00 00 00 00 00 01 04 00 00 00 00 d4 ef 06 00 37 12 0d 00 8c 3c 00 00 00 00
        """)
    /// Preview with target 6 250 (6 443 had been measured). seq 361, 363
    static let previewTarget6250 = bytes("""
        00 00 00 00 00 00 00 3c 00 00 aa b0 28 00 00 00 00 00 00 00 00 00 ce 07 00 00 37 03 00 00 00 00 00 00 \
        00 00 00 00 00 00 00 00 00 00 00 00 00 00 01 04 6a 18 00 00 d4 ef 06 00 37 12 0d 00 8c 3c 00 00 00 00
        """)

    /// 0xE4 data, identical at every occurrence.
    static let exposure = bytes("05 04 10 00 05 04 20 00 05 04 30 00")

    private static func bytes(_ hex: String) -> [UInt8] {
        guard let bytes = [UInt8](hex: hex) else {
            preconditionFailure("invalid captured hex")
        }
        return bytes
    }
}

// MARK: Sequence

struct Builder {
    private(set) var steps: [PreviewStep] = []

    private mutating func add(_ command: SCSICommand, _ kind: PreviewStep.Kind = .command) {
        steps.append(PreviewStep(command: command, kind: kind))
    }

    /// Poll 0xDF after the last step until `state`.
    private mutating func thenWait(_ state: ScannerState = .ready) {
        steps[steps.count - 1] = steps[steps.count - 1].waiting(for: state)
    }

    private mutating func inquiry() { add(X1Command.inquiry(), .inquiry) }
    private mutating func page(_ page: UInt8, _ length: Int) { add(X1Command.modeSense(page: page, length: length)) }
    private mutating func status(_ captured: Int) {
        add(X1Command.modeSense(page: ScanStatusPage.page, length: ScanStatusPage.length),
            .scanStatus(capturedPosition: captured))
    }
    private mutating func mode(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) { add(X1Command.setMode(a, b, c, d)) }
    private mutating func window(_ descriptor: [UInt8]) { add(X1Command.setWindow(descriptor)) }
    private mutating func exposure() { add(X1Command.exposure(Window.exposure)) }

    private mutating func calibrationLine(pixels: Int) {
        add(X1Command.read(lines: 1, calibration: true, bytes: pixels * PreviewScript.bytesPerPixel),
            .read(.calibrationLine))
    }

    private mutating func reference(_ purpose: PreviewStep.ReadPurpose) {
        let bytes = 10 * PreviewScript.previewPixelsPerLine * PreviewScript.bytesPerPixel
        add(X1Command.read(lines: 10, calibration: true, bytes: bytes), .read(purpose))
    }

    private mutating func imageRead(lines: UInt8, _ purpose: PreviewStep.ReadPurpose) {
        let bytes = Int(lines) * PreviewScript.previewPixelsPerLine * PreviewScript.bytesPerPixel
        add(X1Command.read(lines: lines, calibration: false, bytes: bytes), .read(purpose))
    }

    /// The block of page reads FlexColor repeats (seq 3-16, 227-240, 305-318).
    private mutating func pageSet() {
        inquiry()
        page(0x27, 20)
        for _ in 0..<4 { page(0x25, 24) }
        page(0x21, 12); page(0x21, 100)
        page(0x29, 14)
        page(0x21, 12); page(0x21, 100)
        page(0x23, 12); page(0x23, 60)
        page(0x26, 56)
    }

    mutating func buildFlexColor4813() {
        // 1. Initialisation, seq 1-221: identity, vendor pages, usage log, D2.
        inquiry()
        page(0x26, 56)
        pageSet()
        add(X1Command.startupD2())
        page(0x26, 56)
        add(X1Command.usageLog())
        inquiry()
        page(0x27, 20)
        add(X1Command.usageLog())
        add(X1Command.usageLog())

        // 2. Session start, seq 224-243.
        add(X1Command.session(.start)); thenWait()
        pageSet()
        status(6155); thenWait()

        // 3. Calibration at full CCD width and positioning, seq 245-303.
        mode(0, 0, 1, 1); thenWait()
        page(0x27, 20)
        window(Window.calibrationA); thenWait()
        exposure(); thenWait()
        window(Window.calibrationB); thenWait()
        mode(0, 1, 1, 1); thenWait()
        status(25867)
        window(Window.target25000); thenWait()
        status(24971)
        window(Window.target9000); thenWait()
        calibrationLine(pixels: 7992); thenWait()
        mode(0, 0, 0, 1); thenWait()
        calibrationLine(pixels: 7992)
        status(8971)
        window(Window.target8971); thenWait()
        exposure(); thenWait()
        mode(0, 2, 0, 1); thenWait()
        add(X1Command.readE1())
        status(8971)
        calibrationLine(pixels: 8016)
        page(0x27, 20); thenWait()
        mode(0, 2, 0, 1); thenWait()

        // 4. Preview width, seq 305-366.
        pageSet()
        status(8971)
        page(0x27, 20)
        page(0x27, 20)
        window(Window.calibrationRatio8M); thenWait()
        exposure(); thenWait()
        mode(1, 1, 1, 1); thenWait()
        window(Window.preview); thenWait()
        window(Window.preview); thenWait()
        exposure(); thenWait()
        exposure(); thenWait()
        window(Window.preview); thenWait()
        mode(1, 1, 1, 1); thenWait()
        status(6443)
        window(Window.previewTarget6250); thenWait()
        window(Window.previewTarget6250); thenWait()
        mode(1, 1, 0, 1); thenWait()

        // 5. White reference (5 × 10 lines), then dark reference (18 × 10 lines), seq 369-632.
        for _ in 0..<5 { reference(.whiteReference) }
        thenWait()
        mode(1, 0, 0, 1); thenWait()
        status(6155)
        for _ in 0..<18 { reference(.darkReference) }
        status(6155)

        // 6. Scan, seq 634-728. After SCAN FlexColor goes on as soon as 0xDF reads 00 01.
        window(Window.preview); thenWait()
        add(X1Command.scan(), .scan); thenWait(.afterScan)
        for _ in 0..<3 { imageRead(lines: 1, .leadIn) }
        for _ in 0..<40 {
            status(6155)
            imageRead(lines: 20, .image)
        }
        status(6155)
        imageRead(lines: 19, .image)

        // 7. Stop and end of session, seq 729-748.
        add(X1Command.stop()); thenWait()
        add(X1Command.session(.end)); thenWait()
    }
}

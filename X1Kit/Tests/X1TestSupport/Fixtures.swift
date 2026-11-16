// SPDX-License-Identifier: MIT
import Foundation
import X1Transport

/// Paths to tests/fixtures at the repository root (read in place, not copied).
public enum Fixtures {
    public static let directory: URL = URL(filePath: #filePath)
        .deletingLastPathComponent()  // X1TestSupport
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // X1Kit
        .deletingLastPathComponent()  // repository root
        .appending(path: "tests/fixtures")

    public static let sequenceURL = directory.appending(path: "preview-sequence.json")
    /// Right after power-on (2026-11-16).
    public static let coldSequenceURL = directory.appending(path: "preview-sequence-cold.json")
    public static let calibrationProfileURL = directory.appending(path: "preview-calibration-profile.json")

    public static func sequence() throws -> CaptureFixture {
        try CaptureFixture.load(from: sequenceURL)
    }

    public static func coldSequence() throws -> CaptureFixture {
        try CaptureFixture.load(from: coldSequenceURL)
    }

    public static func coldSimulator() throws -> SimulatedX1 {
        try SimulatedX1(sequenceURL: coldSequenceURL, calibrationProfileURL: calibrationProfileURL)
    }

    public static func calibrationProfile() throws -> CalibrationProfile {
        try CalibrationProfile.load(from: calibrationProfileURL)
    }

    public static func simulator() throws -> SimulatedX1 {
        try SimulatedX1(sequenceURL: sequenceURL, calibrationProfileURL: calibrationProfileURL)
    }

    /// The captured exchanges, without the polling commands (0xEE, 0xD3, 0xDF).
    public static func nonPollingExchanges(cold: Bool = false) throws -> [CaptureExchange] {
        try (cold ? coldSequence() : sequence()).exchanges.filter {
            !SimulatedX1.pollingOpcodes.contains($0.cdbBytes.first ?? 0)
        }
    }
}

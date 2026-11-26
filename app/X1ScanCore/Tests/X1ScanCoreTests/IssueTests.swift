// SPDX-License-Identifier: MIT
import Foundation
import Testing
import X1Preview
import X1Protocol
import X1Transport
@testable import X1ScanCore

/// Lot A, step B: messages that say what to do. Every identifier has its
/// texts in both languages and its Troubleshooting entry; every failure the
/// runner, the guards, the transport and the export report leads to its
/// identifier, and nothing else is decided here.
struct IssueTests {
    // MARK: Texts and help

    /// `issue.<id>.title`, `.cause` and one to three steps, translated, with
    /// a comment, for every identifier.
    @Test func everyIdentifierHasItsMessageInBothLanguages() throws {
        let strings = try Self.catalog()
        for id in IssueID.allCases {
            var keys: [String] = ["issue.\(id.rawValue).title", "issue.\(id.rawValue).cause"]
            let steps: [String] = (1...IssueID.maximumSteps).map { "issue.\(id.rawValue).step\($0)" }.filter { strings[$0] != nil }
            // Stopped on request: its steps depend on where it stopped (the advice added by the window).
            if id != .stoppedByUser { #expect(!steps.isEmpty, "\(id): no step") }
            keys += steps
            for key in keys {
                let entry = try #require(strings[key] as? [String: Any], "\(key) is not in the catalog")
                let comment: String = entry["comment"] as? String ?? ""
                #expect(comment.count > 0, "\(key): no comment")
                let localizations = try #require(entry["localizations"] as? [String: Any], "\(key)")
                for language in ["en", "fr"] {
                    let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                    #expect(unit?["state"] as? String == "translated", "\(key): \(language) not translated")
                    let value: String = unit?["value"] as? String ?? ""
                    #expect(value.count > 0, "\(key): \(language) empty")
                }
            }
        }
        // No step beyond the maximum the application reads.
        let beyond: [String] = strings.keys.filter { $0.hasPrefix("issue.") && $0.hasSuffix(".step\(IssueID.maximumSteps + 1)") }
        #expect(beyond.isEmpty)
    }

    /// The Help button opens troubleshooting.md#<id>: the anchor exists in both languages.
    @Test func everyIdentifierHasItsTroubleshootingEntry() throws {
        for language in HelpLibrary.languages {
            let page = try #require(try HelpTests.library(language).page(IssueID.helpPage))
            let anchors: [String] = HelpMarkdown.anchors(page.markdown)
            for id in IssueID.allCases {
                #expect(anchors.contains(id.helpAnchor), "\(language): no Troubleshooting entry for \(id.rawValue)")
            }
        }
    }

    @Test func identifiersAreStable() {
        // Written in the help and in bug reports: renaming one breaks links.
        let raw: [String] = IssueID.allCases.map(\.rawValue)
        #expect(Set(raw).count == raw.count)
        #expect(IssueID.noScanner.rawValue == "no-scanner" && IssueID.unknown.rawValue == "unknown")
        #expect(raw.allSatisfy { $0.allSatisfy { $0.isLowercase || $0 == "-" || $0.isNumber } })
    }

    // MARK: Classification

    @Test func runnerAnomaliesLeadToTheirIdentifier() {
        let expected: [(PreviewAnomaly, IssueID)] = [
            (.badStatus(status: 2, senseKey: 5), .unexpectedResponse),
            (.wrongLength(expected: 2, received: 0), .unexpectedResponse),
            (.unexpectedIdentity(vendor: "X", product: "Y"), .notAnX1),
            (.unexpectedScanResponse([1, 2]), .unexpectedResponse),
            (.positionOutOfTolerance(expected: 1, measured: 500, tolerance: 256), .positionOutOfTolerance),
            (.positionOutOfRange(measured: 1, allowed: 16_395...17_227), .positionOutOfRange),
            (.positionOutOfColdRange(expected: 14_219, measured: 13_450, allowed: 13_451...14_475), .positionOutOfTolerance),
            (.unexpectedCarriagePosition(captured: 1, measured: 2, tolerance: 0), .carriagePosition),
            (.notJustSwitchedOn(channelValues: [1]), .unexpectedResponse),
            (.unrecognisedStartState(channelValues: [1]), .startStateUnknown),
            (.startStateMismatch(required: .warm, channelValues: [1]), .scanNeedsPreview),
            (.lineCounterWentBack(previous: 2, current: 1), .lineCounter),
            (.unexpectedState(.busy, waitingFor: .ready), .unexpectedState),
            (.stateTimeout(waitingFor: .ready, last: .busy), .stateTimeout),
            (.malformedResponse("x"), .unexpectedResponse),
            (.cancelled, .stoppedByUser),
        ]
        for (anomaly, id) in expected {
            #expect(IssueClassifier.id(for: anomaly) == id, "\(anomaly)")
        }
        let decoding = PreviewFailure(cause: .decoding("x"), stepIndex: nil, emergencyStop: nil, description: "x")
        #expect(IssueClassifier.id(for: decoding) == .decodingFailed)
    }

    /// Transport errors reach the runner as their text (made with
    /// `String(describing:)`): the classification compares it with the
    /// descriptions of `TransportError` itself.
    @Test func transportErrorsAreRecognisedFromTheirText() {
        let opening: [(TransportError, IssueID)] = [
            (.deviceNotFound, .noScanner),
            (.deviceBusy, .scannerBusy),
            (.ioKit(code: -536_870_212, operation: "open"), .scannerReadFailed),
        ]
        for (error, id) in opening {
            #expect(IssueClassifier.id(for: .couldNotOpen(String(describing: error))) == id, "open: \(error)")
        }
        let duringRun: [(TransportError, IssueID)] = [
            (.refusedByPolicy(opcode: 0x24, reason: "not the captured command at step 12"), .guardRefused),
            (.deliveryFailure(.deviceNotPresent), .disconnected),
            (.deliveryFailure(.deviceNotResponding), .disconnected),
            (.deviceNotFound, .disconnected),
            (.deliveryFailure(.taskTimeout), .scannerTimeout),
            (.deliveryFailure(.protocolTimeout), .scannerTimeout),
            (.deliveryFailure(.other(9)), .unknown),
            (.deliveryFailure(.serviceResponse(0)), .unknown),
            (.ioKit(code: -536_870_165, operation: "execute 12 00 00 00 60 00"), .unknown),
            (.notOpen, .unknown),
        ]
        for (error, id) in duringRun {
            #expect(IssueClassifier.id(for: .transport(String(describing: error))) == id, "run: \(error)")
        }
        #expect(IssueClassifier.id(for: .transport("something else")) == .unknown)
        #expect(IssueClassifier.id(for: .couldNotOpen("something else")) == .scannerReadFailed)
    }

    @Test func readsStartsAndExportsLeadToTheirIdentifier() {
        let reads: [(ScannerInspector.Failure, IssueID)] = [
            (.transport(.deviceNotFound), .noScanner),
            (.transport(.deviceBusy), .scannerBusy),
            (.transport(.refusedByPolicy(opcode: 0x1b, reason: "x")), .guardRefused),
            (.transport(.deliveryFailure(.deviceNotPresent)), .disconnected),
            (.transport(.ioKit(code: 1, operation: "x")), .scannerReadFailed),
            (.notAFlextightX1(vendor: "A", product: "B"), .notAnX1),
            (.badStatus(opcode: 0x12, status: 2, senseKey: nil), .scannerReadFailed),
            (.wrongLength(opcode: 0x12, expected: 96, received: 0), .scannerReadFailed),
            (.malformed("x"), .scannerReadFailed),
            (.missingResponse("x"), .scannerReadFailed),
            (.other("x"), .scannerReadFailed),
        ]
        for (failure, id) in reads {
            #expect(IssueClassifier.id(for: failure) == id, "\(failure)")
        }
        #expect(IssueClassifier.id(for: RealPreviewError.notAllowed) == nil, "refused silently, as before")
        #expect(IssueClassifier.id(for: RealPreviewError.noCapturedSequence("x")) == .captureMissing)
        #expect(IssueClassifier.id(for: RealPreviewError.log("x")) == .logFailed)
        #expect(IssueClassifier.id(for: ExportError.noFolder) == .noExportFolder)
        #expect(IssueClassifier.id(for: ExportError.folderMissing("/x")) == .exportFolderMissing)
        #expect(IssueClassifier.id(for: ExportError.write("x")) == .writeFailed)
        #expect(IssueClassifier.id(for: ExportError.noImage) == .unknown)
        #expect(IssueClassifier.stopFailed(nil) == false && IssueClassifier.stopFailed(.stoppedAndReady) == false)
        #expect(IssueClassifier.stopFailed(.stopRefused(status: 2, senseKey: nil)))
    }

    /// The safety checks are the cases a guard stops on purpose.
    /// A power-cycle step left out when the window gives its own is one of the case's steps.
    @Test func powerCycleStepsExist() throws {
        let strings = try Self.catalog()
        for id in IssueID.allCases {
            if let step = id.powerCycleStep {
                #expect(strings["issue.\(id.rawValue).step\(step)"] != nil, "\(id): no step \(step)")
            }
        }
    }

    @Test func safetyStopsAreMarked() {
        let safety: Set<IssueID> = Set(IssueID.allCases.filter(\.isSafetyStop))
        #expect(safety == [.guardRefused, .unexpectedState, .stateTimeout, .positionOutOfTolerance, .positionOutOfRange,
                           .carriagePosition, .startStateUnknown, .scanNeedsPreview, .lineCounter, .unexpectedResponse])
    }

    // MARK: Support

    private static func catalog() throws -> [String: Any] {
        let app: URL = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let url: URL = app.appending(path: "X1Scan/Localization/Localizable.xcstrings")
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return try #require(root?["strings"] as? [String: Any])
    }
}

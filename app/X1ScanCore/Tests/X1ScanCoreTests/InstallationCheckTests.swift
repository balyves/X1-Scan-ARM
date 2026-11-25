// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import X1ScanCore

/// The installation check's detection (assistant, lot 1), on invented
/// registry snapshots: no real registry listing is in the repository.
struct InstallationCheckTests {
    private static let tahoe = InstallationSnapshot.SystemVersion(major: 26, minor: 1, patch: 0)
    /// An invented DriverKit driver: its names are not ASFireWire's (unknown until a listing is read).
    private static let userDriver = Driver(className: "IOUserService", userClass: "ExampleFireWireDriver",
                                           userServerName: "org.example.firewire.driver")
    private static let controllerWithDriver = FireWireController(drivers: [userDriver])
    private static let bareController = FireWireController(drivers: [])

    private func lines(_ controllers: [FireWireController], scanner: String? = nil,
                       system: InstallationSnapshot.SystemVersion = tahoe) -> [InstallationCheck.Line] {
        InstallationCheck.evaluate(InstallationSnapshot(system: system, controllers: controllers, scannerDescription: scanner))
    }

    private func state(_ item: InstallationCheck.Item, in lines: [InstallationCheck.Line]) -> InstallationCheck.State? {
        lines.first { $0.item == item }?.state
    }

    @Test func everythingInPlace() {
        let result = lines([Self.controllerWithDriver], scanner: "Imacon Flextight")
        #expect(result.map(\.item) == [.macOS, .adapter, .driver, .scanner], "the assistant's order")
        #expect(result.allSatisfy { $0.state == .ok })
        #expect(InstallationCheck.launchPresentation(for: result) == .nothing)
    }

    @Test func noAdapter() {
        let result = lines([])
        #expect(state(.adapter, in: result) == .warning(.adapterNotFound))
        #expect(state(.driver, in: result) == .warning(.driverNeedsAdapter), "the driver cannot be checked without it")
        #expect(state(.scanner, in: result) == .warning(.scannerNotFound))
        #expect(InstallationCheck.launchPresentation(for: result) == .assistant, "the assistant, not the alert")
    }

    @Test func adapterWithoutDriver() {
        // A controller with only kernel classes attached (invented names), no DriverKit driver.
        let kernelOnly = FireWireController(drivers: [Driver(className: "ExampleKernelClass")])
        for controller in [Self.bareController, kernelOnly] {
            let result = lines([controller])
            #expect(state(.adapter, in: result) == .ok)
            #expect(state(.driver, in: result) == .warning(.driverNotActive))
            #expect(InstallationCheck.launchPresentation(for: result) == .assistant)
        }
    }

    /// An X1 seen means the chain works, even when the registry does not show
    /// the adapter or the driver as the detection expects (its hypotheses).
    @Test func anX1SeenMeansTheChainWorks() {
        for controllers in [[], [Self.bareController]] as [[FireWireController]] {
            let result = lines(controllers, scanner: "Imacon Flextight")
            #expect(result.allSatisfy { (line: InstallationCheck.Line) -> Bool in line.state == .ok })
            #expect(InstallationCheck.launchPresentation(for: result) == .nothing)
        }
    }

    @Test func x1OffOrNotConnected() {
        // Adapter and driver fine, no X1: the "No X1 found" alert, not the assistant.
        let result = lines([Self.controllerWithDriver], scanner: nil)
        #expect(state(.scanner, in: result) == .warning(.scannerNotFound))
        #expect(InstallationCheck.launchPresentation(for: result) == .noScannerAlert)
    }

    @Test func neverTheAlertAndTheAssistantTogether() {
        // Every combination gives one presentation at most, and the assistant wins.
        let cases: [[FireWireController]] = [[], [Self.bareController], [Self.controllerWithDriver],
                                             [Self.bareController, Self.controllerWithDriver]]
        let scanners: [String?] = [nil, "Imacon Flextight"]
        for controllers in cases {
            for scanner in scanners {
                let result: [InstallationCheck.Line] = lines(controllers, scanner: scanner)
                let presentation: InstallationCheck.LaunchPresentation = InstallationCheck.launchPresentation(for: result)
                let adapterOK: Bool = state(.adapter, in: result)?.isOK ?? false
                let driverOK: Bool = state(.driver, in: result)?.isOK ?? false
                let adapterOrDriverMissing: Bool = !adapterOK || !driverOK
                #expect((presentation == .assistant) == adapterOrDriverMissing)
                if presentation == .noScannerAlert { #expect(!adapterOrDriverMissing && scanner == nil) }
            }
        }
    }

    @Test func driverKitIsToldByItsUserProperties() {
        #expect(Self.userDriver.isDriverKit)
        #expect(Driver(className: "IOUserService", userServerName: "org.example.driver").isDriverKit)
        #expect(!Driver(className: "ExampleKernelClass").isDriverKit)
        // One controller with a driver is enough.
        #expect(state(.driver, in: lines([Self.bareController, Self.controllerWithDriver])) == .ok)
    }

    @Test func olderSystem() {
        let result = lines([Self.controllerWithDriver], scanner: "Imacon Flextight",
                           system: .init(major: 15, minor: 7, patch: 0))
        #expect(state(.macOS, in: result) == .warning(.systemTooOld))
        #expect(InstallationCheck.launchPresentation(for: result) == .nothing, "the system line alone does not open it")
    }

    /// PCI class code, as the registry stores it (little endian): 0x0C0010 is IEEE 1394 OHCI.
    @Test func fireWireClassCode() {
        #expect(FireWireController.isFireWire(classCode: [0x10, 0x00, 0x0C, 0x00]), "OHCI")
        #expect(FireWireController.isFireWire(classCode: [0x00, 0x00, 0x0C, 0x00]), "another 1394 interface")
        #expect(!FireWireController.isFireWire(classCode: [0x30, 0x03, 0x0C, 0x00]), "USB (xHCI)")
        #expect(!FireWireController.isFireWire(classCode: [0x00, 0x02, 0x00, 0x00]), "Ethernet")
        #expect(!FireWireController.isFireWire(classCode: [0x10, 0x00]), "too short")
    }

    /// The registry reader only reads: no device opened, no plug-in, no
    /// transport, no command (checked on the source; no test may touch a scanner).
    @Test func theReaderOnlyReadsTheRegistry() throws {
        let file: URL = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/X1ScanCore/Installation/InstallationRegistry.swift")
        let source: String = try String(contentsOf: file, encoding: .utf8)
        let lines: [Substring] = source.split(separator: "\n")
        let code: String = lines.filter { (line: Substring) -> Bool in
            !line.trimmingCharacters(in: .whitespaces).hasPrefix("///")
        }.joined(separator: "\n")
        let forbidden: [String] = ["IOServiceOpen", "IOCreatePlugInInterfaceForService", "QueryInterface", "IOConnect",
                                   "ObtainExclusiveAccess", "IOKitTransport", "SCSICommand", "CommandPolicy",
                                   "IORegistryEntrySetCFProperty", "IOServiceRequestProbe", "IOServiceAuthorize",
                                   "cx1" + "_"]  // split: the CI refuses that prefix anywhere in app/
        for call in forbidden {
            #expect(!code.contains(call), "\(call) in InstallationRegistry.swift")
        }
    }

    /// Smoke test: this Mac's real registry is read (read only, scanner
    /// presence included) without failing; what it shows depends on the Mac.
    @Test func smokeTestOfTheRealRegistry() {
        let result = InstallationCheck.evaluate(InstallationRegistry.snapshot())
        #expect(result.count == 4)
        #expect(state(.macOS, in: result) == .ok)
    }
}

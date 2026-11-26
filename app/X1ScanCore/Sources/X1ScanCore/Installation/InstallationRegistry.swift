// SPDX-License-Identifier: MIT
import Foundation
import IOKit
import X1Transport

/// Reads the I/O Registry for the installation check, and only reads it:
/// matching, properties and children of registry entries. No device is
/// opened (no `IOServiceOpen`, no plug-in interface), no command is sent:
/// a program that has the scanner open keeps it (`InstallationCheckTests`
/// checks this file's calls).
public enum InstallationRegistry {
    /// The registry now, with the macOS version and the scanner presence.
    public static func snapshot() -> InstallationSnapshot {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return InstallationSnapshot(
            system: .init(major: version.majorVersion, minor: version.minorVersion, patch: version.patchVersion),
            controllers: fireWireControllers(),
            scannerDescription: ScannerPresence.find())
    }

    /// The PCI devices of class IEEE 1394, with the drivers attached to them.
    /// A registry changed during the reading (a device plugged in) invalidates
    /// the iterator: the reading is made again, three times at most, then the
    /// last one is kept as it is (what it found is still there).
    static func fireWireControllers() -> [FireWireController] {
        var last: [FireWireController] = []
        for _ in 0..<3 {
            let reading = readFireWireControllers()
            if reading.complete { return reading.controllers }
            last = reading.controllers
        }
        return last
    }

    /// `complete` is false when the registry changed during the reading.
    private static func readFireWireControllers() -> (controllers: [FireWireController], complete: Bool) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOPCIDevice"), &iterator) == KERN_SUCCESS else {
            return ([], true)
        }
        defer { IOObjectRelease(iterator) }
        var controllers: [FireWireController] = []
        while case let device = IOIteratorNext(iterator), device != 0 {
            defer { IOObjectRelease(device) }
            guard let code = dataProperty("class-code", of: device), FireWireController.isFireWire(classCode: code) else { continue }
            controllers.append(FireWireController(drivers: drivers(under: device, depth: 2)))
        }
        return (controllers, IOIteratorIsValid(iterator) != 0)
    }

    /// The entries attached under `entry` in the service plane, `depth` levels
    /// down: ASFireWire's entries are one level under the controller
    /// ([confirmed] on one setup, 2026-11-26); two levels leave a margin.
    private static func drivers(under entry: io_registry_entry_t, depth: Int) -> [Driver] {
        guard depth > 0 else { return [] }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(entry, kIOServicePlane, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var found: [Driver] = []
        while case let child = IOIteratorNext(iterator), child != 0 {
            defer { IOObjectRelease(child) }
            found.append(Driver(className: className(of: child),
                                userClass: stringProperty("IOUserClass", of: child),
                                userServerName: stringProperty("IOUserServerName", of: child)))
            found += drivers(under: child, depth: depth - 1)
        }
        return found
    }

    private static func className(of entry: io_registry_entry_t) -> String {
        var name = [CChar](repeating: 0, count: 128)  // io_name_t
        guard IOObjectGetClass(entry, &name) == KERN_SUCCESS else { return "" }
        return String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func property(_ key: String, of entry: io_registry_entry_t) -> CFTypeRef? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func dataProperty(_ key: String, of entry: io_registry_entry_t) -> [UInt8]? {
        (property(key, of: entry) as? Data).map { [UInt8]($0) }
    }

    private static func stringProperty(_ key: String, of entry: io_registry_entry_t) -> String? {
        property(key, of: entry) as? String
    }
}

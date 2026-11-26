// SPDX-License-Identifier: MIT

/// The installation check (assistant, lot 1: detection only; user's
/// decisions of 2026-11-25): one line per element of the chain on macOS 26
/// Tahoe, each fine or with a warning. Made from a snapshot of the I/O
/// Registry (`InstallationRegistry`), which is only read: no device is
/// opened, no command reaches any scanner.
///
/// What can be told reliably and what cannot (docs/decisions.md,
/// "Installation check"): a FireWire controller is seen with the adapter
/// plugged in ([confirmed] with an X1 on it, 2026-11-26; with nothing on it,
/// [hypothesis], docs/hypotheses.md), but not whether it is Apple's
/// adapter; after a hot unplug of the FireWire cable the Mac may lose the
/// adapter until it is plugged in again ([hypothesis]); the driver is seen
/// when it is active on that controller, not when it is installed and not
/// allowed yet; an X1 switched off, a missing cable and a broken chain look
/// the same, and an X1 switched off may still be seen for a while
/// ([hypothesis]); an X1 opened by FlexColor is not seen as such.
public enum InstallationCheck {
    /// The first macOS the application runs on (deployment target).
    public static let minimumMajorVersion = 26

    public enum Item: String, Sendable, CaseIterable {
        case macOS
        case adapter
        case driver
        case scanner
    }

    public enum Warning: Sendable, Hashable {
        /// macOS older than `minimumMajorVersion`.
        case systemTooOld
        /// No FireWire controller in the registry: no adapter plugged in.
        case adapterNotFound
        /// No adapter: the driver cannot be checked.
        case driverNeedsAdapter
        /// A FireWire controller without a DriverKit driver on it.
        case driverNotActive
        /// No Imacon / Hasselblad scanner in the registry.
        case scannerNotFound
    }

    public enum State: Sendable, Hashable {
        case ok
        case warning(Warning)

        public var isOK: Bool { self == .ok }
    }

    public struct Line: Sendable, Hashable {
        public let item: Item
        public let state: State
    }

    /// The four lines, in the assistant's order.
    public static func evaluate(_ snapshot: InstallationSnapshot) -> [Line] {
        let system: State = snapshot.system.major >= minimumMajorVersion ? .ok : .warning(.systemTooOld)
        let scanner: State = snapshot.scannerDescription == nil ? .warning(.scannerNotFound) : .ok
        // An X1 seen means the chain works: adapter and driver are fine even if the
        // registry does not show them as expected (the detection rests on hypotheses).
        if scanner == .ok {
            return [Line(item: .macOS, state: system), Line(item: .adapter, state: .ok),
                    Line(item: .driver, state: .ok), Line(item: .scanner, state: .ok)]
        }
        let adapter: State = snapshot.controllers.isEmpty ? .warning(.adapterNotFound) : .ok
        let driver: State
        if snapshot.controllers.isEmpty {
            driver = .warning(.driverNeedsAdapter)
        } else if snapshot.controllers.contains(where: \.hasDriverKitDriver) {
            driver = .ok
        } else {
            driver = .warning(.driverNotActive)
        }
        return [Line(item: .macOS, state: system), Line(item: .adapter, state: adapter),
                Line(item: .driver, state: driver), Line(item: .scanner, state: scanner)]
    }

    /// What the application shows at launch (user's decisions of
    /// 2026-11-25): the assistant opens by itself only when the adapter or
    /// the driver is missing; otherwise, without an X1, the "No X1 found"
    /// alert (with a button to the assistant). Never both.
    public enum LaunchPresentation: Sendable, Hashable {
        case nothing
        case assistant
        case noScannerAlert
    }

    public static func launchPresentation(for lines: [Line]) -> LaunchPresentation {
        func isOK(_ item: Item) -> Bool { lines.first { $0.item == item }?.state.isOK ?? false }
        if !isOK(.adapter) || !isOK(.driver) { return .assistant }
        if !isOK(.scanner) { return .noScannerAlert }
        return .nothing
    }
}

/// What the registry showed at one moment.
public struct InstallationSnapshot: Sendable, Hashable {
    public struct SystemVersion: Sendable, Hashable {
        public var major: Int
        public var minor: Int
        public var patch: Int

        public init(major: Int, minor: Int, patch: Int) {
            self.major = major
            self.minor = minor
            self.patch = patch
        }
    }

    public var system: SystemVersion
    /// The FireWire (IEEE 1394) controllers: on a recent Mac, only the
    /// adapter's, an `IOPCIDevice` of class code 0x0C0010 tunnelled through
    /// Thunderbolt ([confirmed] on one setup, 2026-11-26; docs/decisions.md,
    /// "Installation check").
    public var controllers: [FireWireController]
    /// "vendor product" of the scanner found (`ScannerPresence.find()`), or nil.
    public var scannerDescription: String?

    public init(system: SystemVersion, controllers: [FireWireController], scannerDescription: String?) {
        self.system = system
        self.controllers = controllers
        self.scannerDescription = scannerDescription
    }
}

/// A PCI device of class IEEE 1394 and the drivers attached to it.
public struct FireWireController: Sendable, Hashable {
    public var drivers: [Driver]

    public init(drivers: [Driver]) {
        self.drivers = drivers
    }

    /// A DriverKit driver on the controller is taken as ASFireWire: macOS 26
    /// has no FireWire driver of its own, and ASFireWire is the only DriverKit
    /// FireWire driver known. Seen on one setup (2026-11-26, [confirmed] as
    /// observed): `ASFWDriver` and `ASFWSCSIController`, `IOUserServerName`
    /// `net.asfw.driver`, one level under the controller. No name is matched:
    /// any DriverKit driver there counts (that only ASFireWire attaches there
    /// is not tested).
    public var hasDriverKitDriver: Bool { drivers.contains(where: \.isDriverKit) }

    /// PCI class code (the registry's `class-code`, little endian): base
    /// class 0x0C (serial bus), subclass 0x00 (IEEE 1394), any programming
    /// interface (0x10: OHCI).
    public static func isFireWire(classCode: [UInt8]) -> Bool {
        guard classCode.count >= 3 else { return false }
        return classCode[2] == 0x0C && classCode[1] == 0x00
    }
}

/// A driver attached to a controller, as the registry names it.
public struct Driver: Sendable, Hashable {
    /// The registry class (`IOUserService` and the like for a DriverKit driver).
    public var className: String
    /// `IOUserClass`: set for a DriverKit driver.
    public var userClass: String?
    /// `IOUserServerName`: the DriverKit extension's bundle identifier.
    public var userServerName: String?

    public init(className: String, userClass: String? = nil, userServerName: String? = nil) {
        self.className = className
        self.userClass = userClass
        self.userServerName = userServerName
    }

    public var isDriverKit: Bool { userClass != nil || userServerName != nil }
}

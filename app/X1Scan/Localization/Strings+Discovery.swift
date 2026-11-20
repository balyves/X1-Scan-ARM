// SPDX-License-Identifier: MIT
import Foundation

/// Discovery mode (lot A, step C).
extension Strings {
    static var enterDiscovery: String {
        String(localized: "discovery.enter", defaultValue: "Try Without a Scanner", comment: "File menu item and button of the No X1 found message: discovery mode, the app on the virtual X1 without a scanner")
    }
    static var leaveDiscovery: String {
        String(localized: "discovery.leave", defaultValue: "Leave Discovery Mode", comment: "Banner button and File menu item: leaves discovery mode")
    }
    static var leaveDiscoveryHelp: String {
        String(localized: "discovery.leave.help", defaultValue: "Back to the source used before; the real X1 is looked for again", comment: "Tooltip of the banner's Leave Discovery Mode button")
    }
    static var discoveryBanner: String {
        String(localized: "discovery.banner", defaultValue: "Discovery mode — no scanner connected", comment: "Banner above the image in discovery mode (an em dash between the two parts)")
    }
    /// Before ".tif" in the files written in discovery mode.
    static var discoverySuffix: String {
        String(localized: "discovery.fileSuffix", defaultValue: "_sample", comment: "Suffix added to the names of files written in discovery mode, before .tif: letters, digits, _ or - only")
    }
    static var sourceInDiscovery: String {
        String(localized: "discovery.sourceNote", defaultValue: "Leave discovery mode (File menu) to choose the real X1.", comment: "Settings > Scanner note under the Source menu, disabled in discovery mode")
    }
    static var launchPresenceNote: String {
        String(localized: "settings.launchPresenceNote", defaultValue: "At launch, with the real X1 as the source, X1 Scan only looks whether an X1 is connected, without reading it: use Scanner > Read Identity.", comment: "Settings > Scanner note under Source at launch: the presence check (nothing opened or sent)")
    }
    static var noScannerAtLaunchDetails: String {
        String(localized: "discovery.noScanner.details", defaultValue: "Presence check: no Imacon or Hasselblad device in the I/O Registry. Nothing was opened or sent to a scanner.", comment: "Details of the No X1 found message after the presence check (at launch, or on leaving discovery mode): what was done")
    }
}

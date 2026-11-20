// SPDX-License-Identifier: MIT
import CX1IOKit

/// Whether an Imacon / Hasselblad scanner is visible in the I/O Registry
/// (lot A, discovery mode and the "No X1 found" message at launch). Looks up
/// the registry only (`cx1_find`): the device is never opened and no command
/// is sent, so a program that has the scanner open keeps it, and the X1 is
/// neither read nor moved. Nothing here goes through `CommandPolicy`: there
/// is no command.
public enum ScannerPresence {
    /// "vendor product" of the first matching device, or nil when there is none
    /// or the registry could not be searched.
    public static func find() -> String? {
        var description = [CChar](repeating: 0, count: 160)
        guard cx1_find(&description, description.count) == 0 else { return nil }
        let bytes = description.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    public static var isScannerPresent: Bool { find() != nil }
}

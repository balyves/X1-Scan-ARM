// SPDX-License-Identifier: MIT
import Foundation
import X1Image

/// Export palette settings, saved between launches.
public struct ExportSettings: Sendable, Hashable, Codable {
    public static let defaultBaseName = "X1-preview"

    /// Destination folder; nil until chosen.
    public var folder: URL?
    /// Start of the file name; date and a counter are added.
    public var baseName: String = ExportSettings.defaultBaseName

    public init(folder: URL? = nil, baseName: String = ExportSettings.defaultBaseName) {
        self.folder = folder
        self.baseName = baseName
    }
}

public enum ExportError: Error, Hashable, CustomStringConvertible {
    case noFolder
    case noImage
    case folderMissing(String)
    case write(String)

    public var description: String {
        switch self {
        case .noFolder: "no export folder"
        case .noImage: "no image to export"
        case .folderMissing(let path): "folder not found: \(path)"
        case .write(let detail): "could not write the file: \(detail)"
        }
    }
}

/// Writes the corrected preview as a 16-bit RGB TIFF: linear, no profile,
/// no curve (decisions.md, version 1). Never overwrites a file.
public enum ExportService {
    /// `base` with characters that cannot appear in a file name replaced,
    /// surrounding spaces removed, and the default name when empty.
    public static func sanitizedBaseName(_ base: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\").union(.controlCharacters)
        let cleaned = String(base.unicodeScalars.map { forbidden.contains($0) ? "-" : Character($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return cleaned.isEmpty ? ExportSettings.defaultBaseName : cleaned
    }

    /// `<base>-<yyyy-MM-dd>-<nnn>.tif`, with the first counter whose file does not exist.
    public static func fileName(base: String, date: Date, calendar: Calendar = .current,
                                exists: (String) -> Bool) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let prefix = "\(sanitizedBaseName(base))-\(day)-"
        var counter = 1
        while true {
            let name = prefix + String(format: "%03d", counter) + ".tif"
            if !exists(name) { return name }
            counter += 1
        }
    }

    /// Writes `image` into the settings' folder and returns the file's URL.
    public static func export(_ image: PreviewImage?, settings: ExportSettings, date: Date = Date(),
                              fileManager: FileManager = .default) throws(ExportError) -> URL {
        guard let folder = settings.folder else { throw .noFolder }
        guard let image, image.height > 0 else { throw .noImage }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw .folderMissing(folder.path)
        }
        let name = fileName(base: settings.baseName, date: date) {
            fileManager.fileExists(atPath: folder.appending(path: $0).path)
        }
        let url = folder.appending(path: name)
        do {
            // If a file appeared in between, fail rather than replace it (cannot be combined with .atomic).
            try TIFFWriter.data(for: image.exportImage).write(to: url, options: .withoutOverwriting)
        } catch {
            throw .write(error.localizedDescription)
        }
        return url
    }
}

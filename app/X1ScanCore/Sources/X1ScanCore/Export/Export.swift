// SPDX-License-Identifier: MIT
import Foundation
import X1Image

/// Export settings, shared by the Export palette and Settings > Export,
/// saved between launches.
public struct ExportSettings: Sendable, Hashable, Codable {
    public static let defaultTemplate = "X1-preview-{date}-{n}"

    /// Destination folder; nil until chosen.
    public var folder: URL?
    /// File name without extension. Tokens: `{date}` (yyyy-MM-dd), `{heure}`
    /// or `{time}` (HH-mm-ss), `{n}` (001, 002…: the first number free in the folder).
    public var nameTemplate: String = ExportSettings.defaultTemplate

    public init(folder: URL? = nil, nameTemplate: String = ExportSettings.defaultTemplate) {
        self.folder = folder
        self.nameTemplate = nameTemplate
    }

    private enum CodingKeys: String, CodingKey {
        case folder, nameTemplate
        case baseName  // step 2: `<baseName>-<date>-<nnn>.tif`
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        folder = try container.decodeIfPresent(URL.self, forKey: .folder)
        if let template = try container.decodeIfPresent(String.self, forKey: .nameTemplate) {
            nameTemplate = template
        } else if let base = try container.decodeIfPresent(String.self, forKey: .baseName),
                  let clean = ExportService.sanitizedFileName(base) {
            nameTemplate = clean + "-{date}-{n}"
        }  // an empty step 2 base meant the default name
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(folder, forKey: .folder)
        try container.encode(nameTemplate, forKey: .nameTemplate)
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
    /// `name` with characters that cannot appear in a file name replaced and
    /// surrounding spaces and dots removed; nil when nothing is left.
    public static func sanitizedFileName(_ name: String) -> String? {
        let forbidden = CharacterSet(charactersIn: "/:\\").union(.controlCharacters)
        let cleaned = String(name.unicodeScalars.map { forbidden.contains($0) ? "-" : Character($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return cleaned.isEmpty ? nil : cleaned
    }

    /// The file name for `template` at `date`, with the first counter whose
    /// file does not exist. Without `{n}`, the plain name is used if free,
    /// then `-002`, `-003`… are added. An empty result uses the default template.
    public static func fileName(template: String, date: Date, calendar: Calendar = .current,
                                exists: (String) -> Bool) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let time = String(format: "%02d-%02d-%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
        func name(_ template: String) -> String? {
            sanitizedFileName(template.replacingOccurrences(of: "{date}", with: day)
                .replacingOccurrences(of: "{heure}", with: time)
                .replacingOccurrences(of: "{time}", with: time))
        }
        let resolved = name(template).map { _ in template } ?? ExportSettings.defaultTemplate
        let hasCounter = resolved.contains("{n}")
        var counter = 1
        while true {
            let number = String(format: "%03d", counter)
            let candidate: String
            if hasCounter {
                candidate = name(resolved.replacingOccurrences(of: "{n}", with: number))! + ".tif"
            } else {
                candidate = name(resolved)! + (counter == 1 ? "" : "-" + number) + ".tif"
            }
            if !exists(candidate) { return candidate }
            counter += 1
        }
    }

    /// The name the next export would get, for the Export palette.
    public static func nextFileName(settings: ExportSettings, date: Date = Date(),
                                    fileManager: FileManager = .default) -> String {
        fileName(template: settings.nameTemplate, date: date) { name in
            settings.folder.map { fileManager.fileExists(atPath: $0.appending(path: name).path) } ?? false
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
        let name = fileName(template: settings.nameTemplate, date: date) {
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

// SPDX-License-Identifier: MIT
import Foundation
import X1Image

/// A file name token. The template stores the English placeholder only;
/// the app shows translated button labels.
public enum ExportToken: String, Sendable, Hashable, CaseIterable {
    case roll
    case frame
    case date
    case time
    case counter = "n"

    /// `{roll}`, `{frame}`, `{date}`, `{time}`, `{n}`.
    public var placeholder: String { "{\(rawValue)}" }
}

/// Export settings, shared by the Export palette and Settings > Export,
/// saved between launches.
public struct ExportSettings: Sendable, Hashable, Codable {
    public static let defaultTemplate = "X1-preview-{date}-{n}"
    public static let counterDigitsRange = 1...6
    public static let frameRange = 1...99_999
    public static let counterStartRange = 0...999_999

    /// Destination folder; nil until chosen.
    public var folder: URL?
    /// File name without extension. Tokens (`ExportToken`): `{roll}`,
    /// `{frame}` (two digits at least), `{date}` (yyyy-MM-dd), `{time}`
    /// (HH-mm-ss), `{n}` (the first number free in the folder from
    /// `counterStart`, `counterDigits` digits).
    public var nameTemplate: String = ExportSettings.defaultTemplate
    /// Roll name for `{roll}`, as typed (the preview follows it live).
    public var roll: String = ""
    /// The roll name last validated (Return or leaving the field, or an export).
    public private(set) var validatedRoll: String = ""
    /// Frame number for `{frame}`, 1 to 99 999.
    public var frame: Int = 1 {
        didSet { frame = Self.clamp(frame, Self.frameRange) }
    }
    /// Adds 1 to `frame` after each successful export.
    public var incrementsFrame = true
    /// First value tried for `{n}`, 0 to 999 999.
    public var counterStart: Int = 1 {
        didSet { counterStart = Self.clamp(counterStart, Self.counterStartRange) }
    }
    /// Digits of `{n}`, 1 to 6.
    public var counterDigits: Int = 3 {
        didSet { counterDigits = Self.clamp(counterDigits, Self.counterDigitsRange) }
    }

    /// Return pressed or the roll field left: passing to another roll puts
    /// the frame back to 1. Typing alone, or validating the same name, does not.
    public mutating func validateRoll() {
        guard needsRollValidation else { return }
        validatedRoll = roll
        frame = 1
    }

    /// The roll name was edited and not validated yet.
    public var needsRollValidation: Bool { roll != validatedRoll }

    /// The frame set by hand (stepper, field): a roll name typed before is
    /// validated first, so that the frame chosen for it is kept.
    public mutating func setFrame(_ value: Int) {
        validateRoll()
        frame = value
    }

    /// These settings as an export would use them (roll validated).
    public var validated: ExportSettings {
        var copy = self
        copy.validateRoll()
        return copy
    }

    static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    public init(folder: URL? = nil, nameTemplate: String = ExportSettings.defaultTemplate) {
        self.folder = folder
        self.nameTemplate = nameTemplate
    }

    private enum CodingKeys: String, CodingKey {
        case folder, nameTemplate, roll, validatedRoll, frame, incrementsFrame, counterStart, counterDigits
        case baseName  // step 2: `<baseName>-<date>-<nnn>.tif`
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        folder = try container.decodeIfPresent(URL.self, forKey: .folder)
        if let template = try container.decodeIfPresent(String.self, forKey: .nameTemplate) {
            // Step 2b also accepted the French token {heure}; the template now stores English tokens only.
            nameTemplate = template.replacingOccurrences(of: "{heure}", with: ExportToken.time.placeholder)
        } else if let base = try container.decodeIfPresent(String.self, forKey: .baseName),
                  let clean = ExportService.sanitizedFileName(base) {
            nameTemplate = clean + "-{date}-{n}"
        }  // an empty step 2 base meant the default name
        roll = try container.decodeIfPresent(String.self, forKey: .roll) ?? ""
        validatedRoll = try container.decodeIfPresent(String.self, forKey: .validatedRoll) ?? roll
        frame = Self.clamp(try container.decodeIfPresent(Int.self, forKey: .frame) ?? 1, Self.frameRange)
        incrementsFrame = try container.decodeIfPresent(Bool.self, forKey: .incrementsFrame) ?? true
        counterStart = Self.clamp(try container.decodeIfPresent(Int.self, forKey: .counterStart) ?? 1,
                                  Self.counterStartRange)
        counterDigits = Self.clamp(try container.decodeIfPresent(Int.self, forKey: .counterDigits) ?? 3,
                                   Self.counterDigitsRange)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(folder, forKey: .folder)
        try container.encode(nameTemplate, forKey: .nameTemplate)
        try container.encode(roll, forKey: .roll)
        try container.encode(validatedRoll, forKey: .validatedRoll)
        try container.encode(frame, forKey: .frame)
        try container.encode(incrementsFrame, forKey: .incrementsFrame)
        try container.encode(counterStart, forKey: .counterStart)
        try container.encode(counterDigits, forKey: .counterDigits)
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

    /// The file name for `settings` at `date`, with the first counter whose
    /// file does not exist (from `counterStart`). Without `{n}`, the plain
    /// name is used if free, then `-2`, `-3`… (with `counterDigits` digits)
    /// are added. An empty result uses the default template.
    public static func fileName(settings: ExportSettings, date: Date, calendar: Calendar = .current,
                                exists: (String) -> Bool) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let time = String(format: "%02d-%02d-%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
        let frame = padded(settings.frame, 2)
        func name(_ template: String) -> String? {
            // {roll} last: a roll name that contains a token is kept as typed.
            sanitizedFileName(template
                .replacingOccurrences(of: ExportToken.frame.placeholder, with: frame)
                .replacingOccurrences(of: ExportToken.date.placeholder, with: day)
                .replacingOccurrences(of: ExportToken.time.placeholder, with: time)
                .replacingOccurrences(of: ExportToken.roll.placeholder, with: settings.roll))
        }
        let counter = ExportToken.counter.placeholder
        // Checked with a sample number, so that a template made of {n} alone still counts as a name.
        let template = name(settings.nameTemplate.replacingOccurrences(of: counter, with: "1")) != nil
            ? settings.nameTemplate : ExportSettings.defaultTemplate
        let hasCounter = template.contains(counter)
        let digits = settings.counterDigits
        var number = hasCounter ? settings.counterStart : 1
        while true {
            let formatted = padded(number, digits)
            let candidate: String
            if hasCounter {
                candidate = name(template.replacingOccurrences(of: counter, with: formatted))! + ".tif"
            } else {
                candidate = name(template)! + (number == 1 ? "" : "-" + formatted) + ".tif"
            }
            if !exists(candidate) { return candidate }
            number += 1
        }
    }

    /// `value` in decimal, with leading zeros up to `digits` digits.
    static func padded(_ value: Int, _ digits: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: max(digits - text.count, 0)) + text
    }

    /// The name the next export would get, for the Export palette.
    public static func nextFileName(settings: ExportSettings, date: Date = Date(),
                                    fileManager: FileManager = .default) -> String {
        fileName(settings: settings, date: date) { name in
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
        let name = fileName(settings: settings, date: date) {
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

// SPDX-License-Identifier: MIT
import CoreGraphics
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

    /// Characters that already separate two parts of a name.
    static let separators: Set<Character> = ["-", "_", " ", "."]

    /// `template` without this placeholder, for a token whose value is empty,
    /// so that "X1-{roll}-{frame}" gives "X1-07", not "X1--07":
    /// - glued to other text on either side ("Scan{roll}_{frame}",
    ///   "X1-{roll}{frame}"), only the placeholder goes: it brought no
    ///   separator of its own;
    /// - otherwise the run of separators before it goes with it
    ///   ("X1 - {roll} - {frame}" gives "X1 - {frame}"), or, at the start of
    ///   the name, the run after it ("{roll}-{frame}" gives "{frame}").
    public func removed(from template: String) -> String {
        var characters = Array(template)
        let token = Array(placeholder)
        let isSeparator = { (character: Character) in Self.separators.contains(character) }
        var index = 0
        while index + token.count <= characters.count {
            guard Array(characters[index..<(index + token.count)]) == token else { index += 1; continue }
            let start = index, end = index + token.count
            let gluedBefore = start > 0 && !isSeparator(characters[start - 1])
            let gluedAfter = end < characters.count && !isSeparator(characters[end])
            var range = start..<end
            if !gluedBefore && !gluedAfter {
                var before = start
                while before > 0, isSeparator(characters[before - 1]) { before -= 1 }
                if before < start {
                    range = before..<end
                } else {
                    var after = end
                    while after < characters.count, isSeparator(characters[after]) { after += 1 }
                    range = start..<after
                }
            }
            characters.removeSubrange(range)
            index = range.lowerBound
        }
        return String(characters)
    }

    /// Inserts the placeholder into `text` at the character offset `caret`
    /// (replacing `selectionLength` characters), adding a "-" before and after
    /// where the neighbour is not already a separator. A caret out of range
    /// (or nil) inserts at the end. Returns the text and the caret after it.
    public func insert(into text: String, at caret: Int?, selectionLength: Int = 0) -> (text: String, caret: Int) {
        let characters = Array(text)
        let start = min(max(caret ?? characters.count, 0), characters.count)
        let end = min(start + max(selectionLength, 0), characters.count)
        let before = characters[..<start], after = characters[end...]
        var inserted = placeholder
        if let last = before.last, !Self.separators.contains(last) { inserted = "-" + inserted }
        if let next = after.first, !Self.separators.contains(next) { inserted += "-" }
        let result = String(before) + inserted + String(after)
        return (result, start + inserted.count)
    }
}

/// Export settings, shared by the settings panel (Output) and Settings > Export,
/// saved between launches.
public struct ExportSettings: Sendable, Hashable, Codable {
    public static let defaultTemplate = "X1-preview-{date}-{n}"
    /// Templates offered in the panel's Name menu (the current one is always listed too).
    public static let presetTemplates = [defaultTemplate, "{roll}-{frame}", "{roll}_{frame}_{date}", "{date}-{time}-{n}"]
    public static let counterDigitsRange = 1...6
    public static let frameRange = 1...99_999
    public static let counterStartRange = 0...999_999

    /// Destination folder; nil until chosen.
    public var folder: URL?
    /// File name without extension. Tokens (`ExportToken`): `{roll}` (when
    /// the roll name is empty, removed with its separators, see
    /// `ExportToken.removed(from:)`), `{frame}` (two digits at least),
    /// `{date}` (yyyy-MM-dd), `{time}`
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
    /// Pixel layout of the TIFF. Changing it selects that format's default
    /// compression (ZIP in 16 bits, LZW in 8 bits).
    public var format: TIFFFormat = .rgb16 {
        didSet { if format != oldValue { compression = Self.defaultCompression(for: format) } }
    }
    public var compression: TIFFCompression = .deflate

    public static func defaultCompression(for format: TIFFFormat) -> TIFFCompression {
        format.bitsPerSample == 16 ? .deflate : .lzw
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
        case folder, nameTemplate, format, compression, roll, validatedRoll, frame, incrementsFrame, counterStart, counterDigits
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
        format = (try container.decodeIfPresent(String.self, forKey: .format)).flatMap(TIFFFormat.init(rawValue:)) ?? .rgb16
        compression = (try container.decodeIfPresent(String.self, forKey: .compression))
            .flatMap(TIFFCompression.init(rawValue:)) ?? Self.defaultCompression(for: format)
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
        try container.encode(format.rawValue, forKey: .format)
        try container.encode(compression.rawValue, forKey: .compression)
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
    /// are added. An empty roll name removes `{roll}` and its separators
    /// first; an empty result uses the default template.
    public static func fileName(settings: ExportSettings, date: Date, calendar: Calendar = .current,
                                exists: (String) -> Bool) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let time = String(format: "%02d-%02d-%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
        let frame = padded(settings.frame, 2)
        // An empty roll name takes its separator with it ("X1--07" would look like a gap).
        let rollIsEmpty = settings.roll.allSatisfy(\.isWhitespace)
        func name(_ template: String) -> String? {
            let template = rollIsEmpty ? ExportToken.roll.removed(from: template) : template
            // {roll} last: a roll name that contains a token is kept as typed.
            return sanitizedFileName(template
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

    /// The TIFF bytes for `image` with the format and compression of
    /// `settings`: 16 bits raw and linear without profile; 8 bits with the
    /// sRGB curve and an sRGB profile (grey: the grey profile with the sRGB
    /// curve). Provisional until the IT8 input profile (docs/decisions.md).
    public static func tiffData(for image: PreviewImage, settings: ExportSettings, resolution: Int = 72) -> Data {
        tiffData(for: image.exportImage, settings: settings, resolution: resolution)
    }

    /// The TIFF bytes for any RGB image (the preview or scan with its recipe applied).
    public static func tiffData(for image: RGB16Image, settings: ExportSettings, resolution: Int = 72) -> Data {
        let profile: Data? = switch settings.format {
        case .rgb8: ExportService.srgbProfile
        case .gray8: ICCProfiles.graySRGB
        case .rgb16, .gray16: nil
        }
        return TIFFWriter.data(for: image, format: settings.format, compression: settings.compression,
                               iccProfile: profile, resolution: resolution)
    }

    /// ColorSync's sRGB profile. 8 bits is never written without it: if it were
    /// missing, that would be a broken system, not a choice.
    static let srgbProfile: Data = {
        guard let data = CGColorSpace(name: CGColorSpace.sRGB)?.copyICCData() as Data? else {
            preconditionFailure("ColorSync has no sRGB profile")
        }
        return data
    }()

    /// Uncompressed pixel bytes of the exported image (bottom bar estimate).
    public static func estimatedBytes(for image: PreviewImage?, settings: ExportSettings) -> Int? {
        guard let image, image.width > 0, image.expectedHeight > 0 else { return nil }
        return settings.format.pixelBytes(width: image.width, height: image.expectedHeight)
    }

    /// `value` in decimal, with leading zeros up to `digits` digits.
    static func padded(_ value: Int, _ digits: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: max(digits - text.count, 0)) + text
    }

    /// The name the next export would get, for the settings panel.
    /// Same rules as `export`: a version of `master` if given, and a name
    /// counts as taken when the image or (`withRecipe`) its recipe exists.
    public static func nextFileName(settings: ExportSettings, date: Date = Date(), versionOf master: URL? = nil,
                                    withRecipe: Bool = false, fileManager: FileManager = .default) -> String {
        let folder = master?.deletingLastPathComponent() ?? settings.folder
        let taken = isTaken(in: folder, withRecipe: withRecipe, fileManager: fileManager)
        return master.map { versionFileName(of: $0, exists: taken) } ?? fileName(settings: settings, date: date, exists: taken)
    }

    /// A file name is taken in `folder` when the image exists, or its recipe (`withRecipe`).
    static func isTaken(in folder: URL?, withRecipe: Bool, fileManager: FileManager) -> (String) -> Bool {
        { name in
            guard let folder else { return false }
            let url = folder.appending(path: name)
            return fileManager.fileExists(atPath: url.path)
                || (withRecipe && fileManager.fileExists(atPath: Recipe.fileURL(forImage: url).path))
        }
    }

    /// Writes `image` into the settings' folder and returns the file's URL.
    /// `resolution`: pixels per inch written in the file (72 for a preview,
    /// the scan's resolution for a scan). With a `recipe`, its JSON file is
    /// written next to the image (`<name>.x1recipe.json`); `applyRecipe`
    /// renders the recipe into the pixels (Export), otherwise the pixels are
    /// the scanner's (the scan's master). `versionOf`: the master this export
    /// is made from; the file is then `<master>_v1.tif`, `_v2`… and never
    /// replaces the master or another version.
    public static func export(_ image: PreviewImage?, settings: ExportSettings, date: Date = Date(),
                              resolution: Int = 72, recipe: Recipe? = nil, applyRecipe: Bool = false,
                              pixelAspectRatio: Double = 1, versionOf master: URL? = nil,
                              fileManager: FileManager = .default) throws(ExportError) -> URL {
        guard let folder = master?.deletingLastPathComponent() ?? settings.folder else { throw .noFolder }
        guard let image, image.height > 0 else { throw .noImage }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw .folderMissing(folder.path)
        }
        let taken = isTaken(in: folder, withRecipe: recipe != nil, fileManager: fileManager)
        let name = master.map { versionFileName(of: $0, exists: taken) } ?? fileName(settings: settings, date: date, exists: taken)
        let url = folder.appending(path: name)
        let pixels = if let recipe, applyRecipe {
            RecipeRenderer.render(image.exportImage, pixelAspectRatio: pixelAspectRatio, recipe: recipe)
        } else {
            image.exportImage
        }
        // The recipe first: an image is never left on disk without its recipe.
        // If a file appeared in between, fail rather than replace it (cannot be combined with .atomic).
        let recipeURL = recipe.map { _ in Recipe.fileURL(forImage: url) }
        do {
            if let recipe, let recipeURL { try recipe.jsonData().write(to: recipeURL, options: .withoutOverwriting) }
        } catch {
            throw .write(error.localizedDescription)
        }
        do {
            try tiffData(for: pixels, settings: settings, resolution: resolution).write(to: url, options: .withoutOverwriting)
        } catch {
            if let recipeURL { try? fileManager.removeItem(at: recipeURL) }
            throw .write(error.localizedDescription)
        }
        return url
    }

    /// `<master>_v1.tif`, `_v2`…: the first version whose name is free.
    public static func versionFileName(of master: URL, exists: (String) -> Bool) -> String {
        let stem = master.deletingPathExtension().lastPathComponent
        var number = 1
        while exists("\(stem)_v\(number).tif") { number += 1 }
        return "\(stem)_v\(number).tif"
    }
}

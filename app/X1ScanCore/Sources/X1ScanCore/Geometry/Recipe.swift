// SPDX-License-Identifier: MIT
import Foundation

/// The non-destructive recipe of an image (lot 1): what to do with the
/// scanner's pixels, kept apart from them. Written as JSON next to every file
/// the app saves (`<name>.x1recipe.json`). Later lots add the film type, the
/// film base, the corrections and the reference to the master.
public struct Recipe: Sendable, Hashable, Codable {
    /// Format version of the JSON file.
    public static let currentVersion = 1
    /// Extension of the recipe file, after the image's name without its own extension.
    public static let fileExtension = "x1recipe.json"

    public private(set) var version: Int = Recipe.currentVersion
    /// Quarter turns and mirror.
    public var orientation: Orientation = .identity
    /// Fine angle and crop frame, after the turns.
    public var crop = CropSettings()

    public init(orientation: Orientation = .identity, crop: CropSettings = CropSettings()) {
        self.orientation = orientation
        self.crop = crop
    }

    private enum CodingKeys: String, CodingKey { case version, orientation, crop }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        orientation = try container.decodeIfPresent(Orientation.self, forKey: .orientation) ?? .identity
        crop = try container.decodeIfPresent(CropSettings.self, forKey: .crop) ?? CropSettings()
    }

    /// The recipe as written to disk: pretty, keys sorted, stable.
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public enum DecodingError: Error, Equatable {
        /// A version this application does not know (written by a newer one).
        case unsupportedVersion(Int)
    }

    public static func decode(from data: Data) throws -> Recipe {
        let recipe = try JSONDecoder().decode(Recipe.self, from: data)
        guard recipe.version == currentVersion else { throw DecodingError.unsupportedVersion(recipe.version) }
        return recipe
    }

    /// The recipe file that goes with `imageURL` (same folder, same name, other extension).
    public static func fileURL(forImage imageURL: URL) -> URL {
        imageURL.deletingPathExtension().appendingPathExtension(fileExtension)
    }
}

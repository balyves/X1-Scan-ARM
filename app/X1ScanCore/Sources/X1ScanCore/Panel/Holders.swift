// SPDX-License-Identifier: MIT
import Foundation
import Observation

/// An opening of a holder, in millimetres.
public struct HolderAperture: Sendable, Hashable, Codable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        width = try container.decode(Double.self)
        height = try container.decode(Double.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(width)
        try container.encode(height)
    }
}

/// An opening in inches, as Hasselblad's holder sheet writes it ("2¼",
/// "0.94"): text, so that fractions are kept. Decimals use a dot.
public struct HolderInches: Sendable, Hashable, Codable {
    public var width: String
    public var height: String

    public init(width: String, height: String) {
        self.width = width
        self.height = height
    }

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        width = try container.decode(String.self)
        height = try container.decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(width)
        try container.encode(height)
    }
}

/// A film holder: one of the defaults (Resources/holders.json) or one the
/// user added. Saved, not sent to the scanner (the X1 reads a code on the
/// holder, docs/protocol.md §13; the app does not use it yet).
public struct Holder: Sendable, Hashable, Codable, Identifiable {
    public enum Series: String, Sendable, Hashable, Codable {
        /// Supplied for the X1 and X5.
        case standard
        /// The common Flextight series.
        case common
        /// Added by the user.
        case custom
    }

    /// The reference for the defaults, a UUID string for custom holders.
    public var id: String
    /// Hasselblad reference number (optional for custom holders).
    public var reference: String?
    /// Format, e.g. `6×7`; for mounted slides, the slide size.
    public var format: String
    public var apertures: [HolderAperture]
    /// The openings in inches as the holder sheet gives them (defaults only;
    /// empty: computed from `apertures`).
    public var aperturesInches: [HolderInches]
    public var frames: Int
    public var series: Series
    public var mountedSlides: Bool
    /// Maker, e.g. `Hasselblad` (optional).
    public var manufacturer: String?
    /// Patent number printed on the holder, e.g. `US 6,081,352` (optional;
    /// every Hasselblad holder has it).
    public var patent: String?
    /// Bright slots 7-15 of the holder code read by the X1 (X1Image.HolderCode),
    /// when observed for this holder's format (optional).
    public var code: [Int]?

    public init(id: String = UUID().uuidString, reference: String?, format: String, apertures: [HolderAperture],
                frames: Int = 1, series: Series = .custom, mountedSlides: Bool = false,
                aperturesInches: [HolderInches] = [], manufacturer: String? = nil, patent: String? = nil,
                code: [Int]? = nil) {
        self.id = id
        self.reference = reference
        self.format = format
        self.apertures = apertures
        self.frames = max(frames, 1)
        self.series = series
        self.mountedSlides = mountedSlides
        self.aperturesInches = aperturesInches
        self.manufacturer = manufacturer
        self.patent = patent
        self.code = code
    }

    private enum CodingKeys: String, CodingKey {
        case id, reference, format, apertures, aperturesInches, frames, series, mountedSlides, manufacturer, patent, code
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reference = try container.decodeIfPresent(String.self, forKey: .reference)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? reference ?? UUID().uuidString
        format = try container.decode(String.self, forKey: .format)
        apertures = try container.decodeIfPresent([HolderAperture].self, forKey: .apertures) ?? []
        frames = max(try container.decodeIfPresent(Int.self, forKey: .frames) ?? 1, 1)
        series = try container.decodeIfPresent(Series.self, forKey: .series) ?? .custom
        mountedSlides = try container.decodeIfPresent(Bool.self, forKey: .mountedSlides) ?? false
        aperturesInches = try container.decodeIfPresent([HolderInches].self, forKey: .aperturesInches) ?? []
        manufacturer = try container.decodeIfPresent(String.self, forKey: .manufacturer)
        patent = try container.decodeIfPresent(String.self, forKey: .patent)
        code = try container.decodeIfPresent([Int].self, forKey: .code)
    }

    public var isCustom: Bool { series == .custom }

    /// The openings in inches: the sheet's values when given (one per
    /// opening), otherwise computed from the millimetres, 2 decimals at most.
    public var inches: [HolderInches] {
        if aperturesInches.count == apertures.count { return aperturesInches }
        return apertures.map { HolderInches(width: Self.inches($0.width), height: Self.inches($0.height)) }
    }

    /// 57 → "2.24", 94 → "3.7" (dot decimal separator, like the data file).
    public static func inches(_ millimetres: Double) -> String {
        let value = (millimetres / 25.4 * 100).rounded() / 100
        return value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }

    /// "4.5×6" → "4,5×6" where the locale's decimal separator is a comma: only
    /// a dot between two digits is replaced.
    public static func localizedDecimals(_ text: String, locale: Locale = .current) -> String {
        let separator = locale.decimalSeparator ?? "."
        guard separator != "." else { return text }
        let characters = Array(text)
        var result = ""
        for (i, c) in characters.enumerated() {
            if c == ".", i > 0, i + 1 < characters.count, characters[i - 1].isNumber, characters[i + 1].isNumber {
                result += separator
            } else {
                result.append(c)
            }
        }
        return result
    }
}

/// The default holders, from the versioned data file.
public enum DefaultHolders {
    private struct File: Decodable { let holders: [Holder] }

    public static let all: [Holder] = {
        guard let url = Bundle.module.url(forResource: "holders", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else {
            preconditionFailure("Resources/holders.json missing or invalid")
        }
        return file.holders
    }()

    /// Holders supplied with the X1: shown by default.
    public static var standardIDs: Set<String> { Set(all.filter { $0.series == .standard }.map(\.id)) }
}

/// The holders of Settings > Holders: which defaults the user owns (only
/// those appear in the panel), and the custom ones. Defaults can be hidden,
/// not deleted.
@MainActor
@Observable
public final class HolderLibrary {
    public let defaults: [Holder]
    public private(set) var custom: [Holder] {
        didSet { save() }
    }
    /// Owned holders (defaults and custom), shown in the panel's menu.
    public private(set) var owned: Set<String> {
        didSet { save() }
    }

    private let store: UserDefaults
    static let key = "Holders"

    private struct Saved: Codable {
        var owned: [String]
        var custom: [Holder]
    }

    public init(defaults: [Holder] = DefaultHolders.all, store: UserDefaults) {
        self.defaults = defaults
        self.store = store
        let data = store.data(forKey: Self.key)
        if let data, let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            custom = saved.custom.map { var h = $0; h.series = .custom; return h }
            owned = Set(saved.owned)
        } else {
            // Unreadable saved holders are kept aside, not overwritten by the next save.
            if let data { store.set(data, forKey: Self.key + ".unreadable") }
            custom = []
            owned = Set(defaults.filter { $0.series == .standard }.map(\.id))
        }
    }

    /// Every holder, defaults first (data file order), then custom ones.
    public var all: [Holder] { defaults + custom }

    /// The holders of the panel's menu, in the same order.
    public var ownedHolders: [Holder] { all.filter { owned.contains($0.id) } }

    public func holder(id: String?) -> Holder? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    public func isOwned(_ id: String) -> Bool { owned.contains(id) }

    public func setOwned(_ id: String, _ value: Bool) {
        guard holder(id: id) != nil else { return }
        if value { owned.insert(id) } else { owned.remove(id) }
    }

    /// Adds a custom holder, owned. Returns it.
    @discardableResult
    public func addCustom(reference: String?, format: String, aperture: HolderAperture?, frames: Int) -> Holder {
        let holder = Holder(reference: Self.clean(reference), format: Self.name(format),
                            apertures: aperture.map { [$0] } ?? [], frames: frames)
        custom.append(holder)
        owned.insert(holder.id)
        return holder
    }

    /// Changes a custom holder; defaults cannot be changed.
    public func updateCustom(_ id: String, reference: String?, format: String, aperture: HolderAperture?, frames: Int) {
        guard let index = custom.firstIndex(where: { $0.id == id }) else { return }
        custom[index].reference = Self.clean(reference)
        custom[index].format = Self.name(format)
        custom[index].apertures = aperture.map { [$0] } ?? []
        custom[index].aperturesInches = [] // computed from the new millimetres
        custom[index].frames = max(frames, 1)
    }

    /// Deletes a custom holder; defaults cannot be deleted (only hidden).
    public func deleteCustom(_ id: String) {
        guard custom.contains(where: { $0.id == id }) else { return }
        custom.removeAll { $0.id == id }
        owned.remove(id)
    }

    private static func clean(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func name(_ text: String) -> String {
        clean(text) ?? "?"
    }

    private func save() {
        let saved = Saved(owned: owned.sorted(), custom: custom)
        if let data = try? JSONEncoder().encode(saved) { store.set(data, forKey: Self.key) }
    }
}

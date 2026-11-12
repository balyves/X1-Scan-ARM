// SPDX-License-Identifier: MIT

/// Identifier of a palette. A string, so that a saved layout that names a
/// palette this version does not know still decodes (the palette is dropped
/// when the layout is reconciled with the registry).
public struct PaletteID: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }

    public static let scanner = PaletteID(rawValue: "scanner")
    public static let histogram = PaletteID(rawValue: "histogram")
    public static let info = PaletteID(rawValue: "info")
    public static let export = PaletteID(rawValue: "export")
}

/// Static description of a palette. The title is localised by the app from the id.
public struct PaletteDescriptor: Sendable, Hashable {
    public let id: PaletteID
    /// SF Symbol shown in the header and in the icon bar.
    public let symbolName: String
    public let collapsedByDefault: Bool
    /// Whether the palette may be shown in a floating window (later stage).
    public let canFloat: Bool

    public init(id: PaletteID, symbolName: String, collapsedByDefault: Bool = false, canFloat: Bool = true) {
        self.id = id
        self.symbolName = symbolName
        self.collapsedByDefault = collapsedByDefault
        self.canFloat = canFloat
    }
}

/// Every palette the app knows, in default order. New palettes are added here
/// and appear at the end of existing saved layouts.
public struct PaletteRegistry: Sendable {
    public let descriptors: [PaletteDescriptor]

    public init(_ descriptors: [PaletteDescriptor]) {
        precondition(Set(descriptors.map(\.id)).count == descriptors.count, "duplicate palette id")
        self.descriptors = descriptors
    }

    public static let standard = PaletteRegistry([
        PaletteDescriptor(id: .scanner, symbolName: "scanner"),
        PaletteDescriptor(id: .histogram, symbolName: "chart.bar.xaxis"),
        PaletteDescriptor(id: .info, symbolName: "info.circle"),
        PaletteDescriptor(id: .export, symbolName: "square.and.arrow.up", collapsedByDefault: true),
    ])

    public var ids: [PaletteID] { descriptors.map(\.id) }

    public func descriptor(for id: PaletteID) -> PaletteDescriptor? {
        descriptors.first { $0.id == id }
    }

    public func contains(_ id: PaletteID) -> Bool { descriptor(for: id) != nil }
}

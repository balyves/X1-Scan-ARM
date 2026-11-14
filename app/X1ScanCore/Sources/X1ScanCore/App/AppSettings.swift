// SPDX-License-Identifier: MIT
import Foundation
import Observation

/// Interface language. Takes effect at the next launch.
public enum InterfaceLanguage: String, Sendable, Hashable, CaseIterable {
    case system
    case french
    case english

    /// Value written to the app's `AppleLanguages`; nil for the system language.
    public var appleLanguages: [String]? {
        switch self {
        case .system: nil
        case .french: ["fr"]
        case .english: ["en"]
        }
    }
}

public enum AppearanceSetting: String, Sendable, Hashable, CaseIterable {
    case system
    case light
    case dark
}

/// Background around the image.
public enum CanvasBackground: String, Sendable, Hashable, CaseIterable {
    /// Middle grey: 18 % reflectance, L* 50, sRGB 119/119/119.
    case neutralGray
    case black
    case white

    /// sRGB component, 0...1, of this neutral colour.
    public var srgbLevel: Double {
        switch self {
        case .neutralGray: 119.0 / 255
        case .black: 0
        case .white: 1
        }
    }
}

/// Zoom mode when the app opens.
public enum StartupZoom: String, Sendable, Hashable, CaseIterable {
    case fit
    case actualSize
}

/// Scanner source when the app opens.
public enum StartupSource: String, Sendable, Hashable, CaseIterable {
    case virtual
    case real
    /// The source used when the app was last quit.
    case last
}

/// Settings window (⌘,), saved in UserDefaults. The export settings are in
/// `AppModel.exportSettings`, shared with the Export palette.
@MainActor
@Observable
public final class AppSettings {
    public var language: InterfaceLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
            if let languages = language.appleLanguages {
                defaults.set(languages, forKey: Keys.appleLanguages)
            } else {
                defaults.removeObject(forKey: Keys.appleLanguages)
            }
        }
    }
    /// The serial number is personal data (CLAUDE.md): masked unless the user turns this off.
    public var hidesSerialNumber: Bool {
        didSet { defaults.set(hidesSerialNumber, forKey: Keys.hidesSerialNumber) }
    }
    public var appearance: AppearanceSetting {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }
    public var canvasBackground: CanvasBackground {
        didSet { defaults.set(canvasBackground.rawValue, forKey: Keys.canvasBackground) }
    }
    public var startupZoom: StartupZoom {
        didSet { defaults.set(startupZoom.rawValue, forKey: Keys.startupZoom) }
    }
    public var startupSource: StartupSource {
        didSet { defaults.set(startupSource.rawValue, forKey: Keys.startupSource) }
    }

    private let defaults: UserDefaults

    enum Keys {
        static let language = "InterfaceLanguage"
        static let appleLanguages = "AppleLanguages"
        static let hidesSerialNumber = "HidesSerialNumber"
        static let appearance = "Appearance"
        static let canvasBackground = "CanvasBackground"
        static let startupZoom = "StartupZoom"
        static let startupSource = "StartupSource"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = Self.value(defaults, Keys.language, InterfaceLanguage.system)
        hidesSerialNumber = defaults.object(forKey: Keys.hidesSerialNumber) as? Bool ?? true
        appearance = Self.value(defaults, Keys.appearance, AppearanceSetting.system)
        canvasBackground = Self.value(defaults, Keys.canvasBackground, CanvasBackground.neutralGray)
        startupZoom = Self.value(defaults, Keys.startupZoom, StartupZoom.fit)
        startupSource = Self.value(defaults, Keys.startupSource, StartupSource.last)
    }

    private static func value<T: RawRepresentable<String>>(_ defaults: UserDefaults, _ key: String, _ fallback: T) -> T {
        guard let raw = defaults.string(forKey: key), let value = T(rawValue: raw) else { return fallback }
        return value
    }

    /// The serial number as it should be shown.
    public func displayedSerial(_ serial: String) -> String {
        SerialMasking.display(serial, revealed: !hidesSerialNumber)
    }
}

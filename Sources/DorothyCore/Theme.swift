import Foundation

/// The user's theme choice, stored in UserDefaults under `defaultsKey`.
public enum Appearance: String, CaseIterable, Codable, Sendable {
    case system, light, dark

    public static let defaultsKey = "appearance"

    /// Missing or unknown values fall back to light, the original look.
    public init(stored: String?) {
        self = stored.flatMap(Appearance.init(rawValue:)) ?? .light
    }

    public var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    public func isDark(systemDark: Bool) -> Bool {
        switch self {
        case .system: systemDark
        case .light: false
        case .dark: true
        }
    }
}

/// Hex colors for one theme. Accents are shared; surfaces, lines and text flip.
public struct Palette: Equatable, Sendable {
    public var paper: String        // window / card fill
    public var line: String         // borders, hard shadows, primary text
    public var onAccent: String     // text and glyphs on accent fills
    public var muted: String        // secondary text
    public var placeholder: String
    public var doneBG: String
    public var disabledBG: String
    public var dangerBG: String
    public var yellow: String
    public var pink: String
    public var orange: String
    public var cobalt: String
    public var mint: String

    public static let light = Palette(
        paper: "#FFFFFF", line: "#111111", onAccent: "#111111", muted: "#444444", placeholder: "#6B6B6B",
        doneBG: "#F2F2F2", disabledBG: "#E6E6E6", dangerBG: "#FFF0F7",
        yellow: "#FFD60A", pink: "#FF4FA3", orange: "#FF7A1A", cobalt: "#2E5BFF", mint: "#22D39A")

    public static let dark = Palette(
        paper: "#161616", line: "#F2F2F2", onAccent: "#111111", muted: "#B5B5B5", placeholder: "#8A8A8A",
        doneBG: "#262626", disabledBG: "#2E2E2E", dangerBG: "#3A1426",
        yellow: "#FFD60A", pink: "#FF4FA3", orange: "#FF7A1A", cobalt: "#2E5BFF", mint: "#22D39A")

    public static func forDark(_ dark: Bool) -> Palette { dark ? .dark : .light }
}

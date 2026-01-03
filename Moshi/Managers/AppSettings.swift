import Foundation
import SwiftUI
import Combine

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // MARK: - Appearance

    @Published var appearanceMode: AppearanceMode {
        didSet { defaults.set(appearanceMode.rawValue, forKey: "appearanceMode") }
    }

    @Published var currentTheme: TerminalTheme {
        didSet {
            if let data = try? JSONEncoder().encode(currentTheme) {
                defaults.set(data, forKey: "terminalTheme")
            }
        }
    }

    @Published var terminalFont: TerminalFont {
        didSet {
            if let data = try? JSONEncoder().encode(terminalFont) {
                defaults.set(data, forKey: "terminalFont")
            }
        }
    }

    @Published var cursorStyle: CursorStyle {
        didSet { defaults.set(cursorStyle.rawValue, forKey: "cursorStyle") }
    }

    @Published var cursorBlink: Bool {
        didSet { defaults.set(cursorBlink, forKey: "cursorBlink") }
    }

    // MARK: - Terminal Behavior

    @Published var scrollbackLimit: Int {
        didSet { defaults.set(scrollbackLimit, forKey: "scrollbackLimit") }
    }

    @Published var bellSound: Bool {
        didSet { defaults.set(bellSound, forKey: "bellSound") }
    }

    @Published var bellVibrate: Bool {
        didSet { defaults.set(bellVibrate, forKey: "bellVibrate") }
    }

    @Published var autoCorrect: Bool {
        didSet { defaults.set(autoCorrect, forKey: "autoCorrect") }
    }

    @Published var smartQuotes: Bool {
        didSet { defaults.set(smartQuotes, forKey: "smartQuotes") }
    }

    // MARK: - Connection

    @Published var defaultUseMosh: Bool {
        didSet { defaults.set(defaultUseMosh, forKey: "defaultUseMosh") }
    }

    @Published var defaultAutoTmux: Bool {
        didSet { defaults.set(defaultAutoTmux, forKey: "defaultAutoTmux") }
    }

    @Published var keepAliveInterval: Int {
        didSet { defaults.set(keepAliveInterval, forKey: "keepAliveInterval") }
    }

    @Published var connectionTimeout: Int {
        didSet { defaults.set(connectionTimeout, forKey: "connectionTimeout") }
    }

    @Published var autoReconnect: Bool {
        didSet { defaults.set(autoReconnect, forKey: "autoReconnect") }
    }

    // MARK: - Keyboard

    @Published var showMacroKeyboard: Bool {
        didSet { defaults.set(showMacroKeyboard, forKey: "showMacroKeyboard") }
    }

    @Published var hapticFeedback: Bool {
        didSet { defaults.set(hapticFeedback, forKey: "hapticFeedback") }
    }

    @Published var keyClickSound: Bool {
        didSet { defaults.set(keyClickSound, forKey: "keyClickSound") }
    }

    // MARK: - Tmux

    @Published var tmuxPrefix: TmuxPrefix {
        didSet { defaults.set(tmuxPrefix.rawValue, forKey: "tmuxPrefix") }
    }

    @Published var tmuxDefaultSessionName: String {
        didSet { defaults.set(tmuxDefaultSessionName, forKey: "tmuxDefaultSessionName") }
    }

    // MARK: - Security

    @Published var requireBiometrics: Bool {
        didSet { defaults.set(requireBiometrics, forKey: "requireBiometrics") }
    }

    @Published var lockOnBackground: Bool {
        didSet { defaults.set(lockOnBackground, forKey: "lockOnBackground") }
    }

    @Published var clipboardTimeout: Int {
        didSet { defaults.set(clipboardTimeout, forKey: "clipboardTimeout") }
    }

    // MARK: - Initialization

    private init() {
        // Appearance
        appearanceMode = AppearanceMode(rawValue: defaults.string(forKey: "appearanceMode") ?? "") ?? .system

        if let themeData = defaults.data(forKey: "terminalTheme"),
           let theme = try? JSONDecoder().decode(TerminalTheme.self, from: themeData) {
            currentTheme = theme
        } else {
            currentTheme = .dracula
        }

        if let fontData = defaults.data(forKey: "terminalFont"),
           let font = try? JSONDecoder().decode(TerminalFont.self, from: fontData) {
            terminalFont = font
        } else {
            terminalFont = TerminalFont()
        }

        cursorStyle = CursorStyle(rawValue: defaults.string(forKey: "cursorStyle") ?? "") ?? .block
        cursorBlink = defaults.object(forKey: "cursorBlink") as? Bool ?? true

        // Terminal
        scrollbackLimit = defaults.object(forKey: "scrollbackLimit") as? Int ?? 10000
        bellSound = defaults.object(forKey: "bellSound") as? Bool ?? false
        bellVibrate = defaults.object(forKey: "bellVibrate") as? Bool ?? true
        autoCorrect = defaults.object(forKey: "autoCorrect") as? Bool ?? false
        smartQuotes = defaults.object(forKey: "smartQuotes") as? Bool ?? false

        // Connection
        defaultUseMosh = defaults.object(forKey: "defaultUseMosh") as? Bool ?? true
        defaultAutoTmux = defaults.object(forKey: "defaultAutoTmux") as? Bool ?? true
        keepAliveInterval = defaults.object(forKey: "keepAliveInterval") as? Int ?? 60
        connectionTimeout = defaults.object(forKey: "connectionTimeout") as? Int ?? 30
        autoReconnect = defaults.object(forKey: "autoReconnect") as? Bool ?? true

        // Keyboard
        showMacroKeyboard = defaults.object(forKey: "showMacroKeyboard") as? Bool ?? true
        hapticFeedback = defaults.object(forKey: "hapticFeedback") as? Bool ?? true
        keyClickSound = defaults.object(forKey: "keyClickSound") as? Bool ?? false

        // Tmux
        tmuxPrefix = TmuxPrefix(rawValue: defaults.string(forKey: "tmuxPrefix") ?? "") ?? .ctrlB
        tmuxDefaultSessionName = defaults.string(forKey: "tmuxDefaultSessionName") ?? "moshi"

        // Security
        requireBiometrics = defaults.object(forKey: "requireBiometrics") as? Bool ?? true
        lockOnBackground = defaults.object(forKey: "lockOnBackground") as? Bool ?? true
        clipboardTimeout = defaults.object(forKey: "clipboardTimeout") as? Int ?? 60
    }

    // MARK: - Computed Properties

    var colorScheme: ColorScheme? {
        switch appearanceMode {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    // MARK: - Reset

    func resetToDefaults() {
        appearanceMode = .system
        currentTheme = .dracula
        terminalFont = TerminalFont()
        cursorStyle = .block
        cursorBlink = true

        scrollbackLimit = 10000
        bellSound = false
        bellVibrate = true
        autoCorrect = false
        smartQuotes = false

        defaultUseMosh = true
        defaultAutoTmux = true
        keepAliveInterval = 60
        connectionTimeout = 30
        autoReconnect = true

        showMacroKeyboard = true
        hapticFeedback = true
        keyClickSound = false

        tmuxPrefix = .ctrlB
        tmuxDefaultSessionName = "moshi"

        requireBiometrics = true
        lockOnBackground = true
        clipboardTimeout = 60
    }
}

// MARK: - Enums

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }
}

enum CursorStyle: String, CaseIterable, Identifiable {
    case block = "Block"
    case underline = "Underline"
    case bar = "Bar"

    var id: String { rawValue }
}

enum TmuxPrefix: String, CaseIterable, Identifiable {
    case ctrlA = "Ctrl-A"
    case ctrlB = "Ctrl-B"
    case ctrlSpace = "Ctrl-Space"

    var id: String { rawValue }

    var sequence: String {
        switch self {
        case .ctrlA: return "\u{01}"
        case .ctrlB: return "\u{02}"
        case .ctrlSpace: return "\u{00}"
        }
    }
}

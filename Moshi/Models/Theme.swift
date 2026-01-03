import SwiftUI

struct TerminalTheme: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var background: ThemeColor
    var foreground: ThemeColor
    var cursor: ThemeColor
    var selection: ThemeColor
    var palette: [ThemeColor] // 16 colors (0-7 normal, 8-15 bright)

    init(
        id: UUID = UUID(),
        name: String,
        background: ThemeColor,
        foreground: ThemeColor,
        cursor: ThemeColor,
        selection: ThemeColor,
        palette: [ThemeColor]
    ) {
        self.id = id
        self.name = name
        self.background = background
        self.foreground = foreground
        self.cursor = cursor
        self.selection = selection
        self.palette = palette
    }

    var swiftUIBackground: Color {
        background.color
    }

    var swiftUIForeground: Color {
        foreground.color
    }

    func colorForIndex(_ index: Int) -> Color {
        guard index >= 0 && index < palette.count else {
            return foreground.color
        }
        return palette[index].color
    }
}

struct ThemeColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b, a: UInt64
        switch hex.count {
        case 6:
            (r, g, b, a) = (int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF, 255)
        case 8:
            (r, g, b, a) = (int >> 24 & 0xFF, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b, a) = (0, 0, 0, 255)
        }

        self.red = Double(r) / 255
        self.green = Double(g) / 255
        self.blue = Double(b) / 255
        self.alpha = Double(a) / 255
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

// MARK: - Built-in Themes

extension TerminalTheme {
    static let solarizedDark = TerminalTheme(
        name: "Solarized Dark",
        background: ThemeColor(hex: "002b36"),
        foreground: ThemeColor(hex: "839496"),
        cursor: ThemeColor(hex: "93a1a1"),
        selection: ThemeColor(hex: "073642"),
        palette: [
            ThemeColor(hex: "073642"), // Black
            ThemeColor(hex: "dc322f"), // Red
            ThemeColor(hex: "859900"), // Green
            ThemeColor(hex: "b58900"), // Yellow
            ThemeColor(hex: "268bd2"), // Blue
            ThemeColor(hex: "d33682"), // Magenta
            ThemeColor(hex: "2aa198"), // Cyan
            ThemeColor(hex: "eee8d5"), // White
            ThemeColor(hex: "002b36"), // Bright Black
            ThemeColor(hex: "cb4b16"), // Bright Red
            ThemeColor(hex: "586e75"), // Bright Green
            ThemeColor(hex: "657b83"), // Bright Yellow
            ThemeColor(hex: "839496"), // Bright Blue
            ThemeColor(hex: "6c71c4"), // Bright Magenta
            ThemeColor(hex: "93a1a1"), // Bright Cyan
            ThemeColor(hex: "fdf6e3"), // Bright White
        ]
    )

    static let solarizedLight = TerminalTheme(
        name: "Solarized Light",
        background: ThemeColor(hex: "fdf6e3"),
        foreground: ThemeColor(hex: "657b83"),
        cursor: ThemeColor(hex: "586e75"),
        selection: ThemeColor(hex: "eee8d5"),
        palette: [
            ThemeColor(hex: "073642"),
            ThemeColor(hex: "dc322f"),
            ThemeColor(hex: "859900"),
            ThemeColor(hex: "b58900"),
            ThemeColor(hex: "268bd2"),
            ThemeColor(hex: "d33682"),
            ThemeColor(hex: "2aa198"),
            ThemeColor(hex: "eee8d5"),
            ThemeColor(hex: "002b36"),
            ThemeColor(hex: "cb4b16"),
            ThemeColor(hex: "586e75"),
            ThemeColor(hex: "657b83"),
            ThemeColor(hex: "839496"),
            ThemeColor(hex: "6c71c4"),
            ThemeColor(hex: "93a1a1"),
            ThemeColor(hex: "fdf6e3"),
        ]
    )

    static let dracula = TerminalTheme(
        name: "Dracula",
        background: ThemeColor(hex: "282a36"),
        foreground: ThemeColor(hex: "f8f8f2"),
        cursor: ThemeColor(hex: "f8f8f2"),
        selection: ThemeColor(hex: "44475a"),
        palette: [
            ThemeColor(hex: "21222c"),
            ThemeColor(hex: "ff5555"),
            ThemeColor(hex: "50fa7b"),
            ThemeColor(hex: "f1fa8c"),
            ThemeColor(hex: "bd93f9"),
            ThemeColor(hex: "ff79c6"),
            ThemeColor(hex: "8be9fd"),
            ThemeColor(hex: "f8f8f2"),
            ThemeColor(hex: "6272a4"),
            ThemeColor(hex: "ff6e6e"),
            ThemeColor(hex: "69ff94"),
            ThemeColor(hex: "ffffa5"),
            ThemeColor(hex: "d6acff"),
            ThemeColor(hex: "ff92df"),
            ThemeColor(hex: "a4ffff"),
            ThemeColor(hex: "ffffff"),
        ]
    )

    static let nord = TerminalTheme(
        name: "Nord",
        background: ThemeColor(hex: "2e3440"),
        foreground: ThemeColor(hex: "d8dee9"),
        cursor: ThemeColor(hex: "d8dee9"),
        selection: ThemeColor(hex: "434c5e"),
        palette: [
            ThemeColor(hex: "3b4252"),
            ThemeColor(hex: "bf616a"),
            ThemeColor(hex: "a3be8c"),
            ThemeColor(hex: "ebcb8b"),
            ThemeColor(hex: "81a1c1"),
            ThemeColor(hex: "b48ead"),
            ThemeColor(hex: "88c0d0"),
            ThemeColor(hex: "e5e9f0"),
            ThemeColor(hex: "4c566a"),
            ThemeColor(hex: "bf616a"),
            ThemeColor(hex: "a3be8c"),
            ThemeColor(hex: "ebcb8b"),
            ThemeColor(hex: "81a1c1"),
            ThemeColor(hex: "b48ead"),
            ThemeColor(hex: "8fbcbb"),
            ThemeColor(hex: "eceff4"),
        ]
    )

    static let tokyoNight = TerminalTheme(
        name: "Tokyo Night",
        background: ThemeColor(hex: "1a1b26"),
        foreground: ThemeColor(hex: "c0caf5"),
        cursor: ThemeColor(hex: "c0caf5"),
        selection: ThemeColor(hex: "33467c"),
        palette: [
            ThemeColor(hex: "15161e"),
            ThemeColor(hex: "f7768e"),
            ThemeColor(hex: "9ece6a"),
            ThemeColor(hex: "e0af68"),
            ThemeColor(hex: "7aa2f7"),
            ThemeColor(hex: "bb9af7"),
            ThemeColor(hex: "7dcfff"),
            ThemeColor(hex: "a9b1d6"),
            ThemeColor(hex: "414868"),
            ThemeColor(hex: "f7768e"),
            ThemeColor(hex: "9ece6a"),
            ThemeColor(hex: "e0af68"),
            ThemeColor(hex: "7aa2f7"),
            ThemeColor(hex: "bb9af7"),
            ThemeColor(hex: "7dcfff"),
            ThemeColor(hex: "c0caf5"),
        ]
    )

    static let gruvboxDark = TerminalTheme(
        name: "Gruvbox Dark",
        background: ThemeColor(hex: "282828"),
        foreground: ThemeColor(hex: "ebdbb2"),
        cursor: ThemeColor(hex: "ebdbb2"),
        selection: ThemeColor(hex: "504945"),
        palette: [
            ThemeColor(hex: "282828"),
            ThemeColor(hex: "cc241d"),
            ThemeColor(hex: "98971a"),
            ThemeColor(hex: "d79921"),
            ThemeColor(hex: "458588"),
            ThemeColor(hex: "b16286"),
            ThemeColor(hex: "689d6a"),
            ThemeColor(hex: "a89984"),
            ThemeColor(hex: "928374"),
            ThemeColor(hex: "fb4934"),
            ThemeColor(hex: "b8bb26"),
            ThemeColor(hex: "fabd2f"),
            ThemeColor(hex: "83a598"),
            ThemeColor(hex: "d3869b"),
            ThemeColor(hex: "8ec07c"),
            ThemeColor(hex: "ebdbb2"),
        ]
    )

    static let monokai = TerminalTheme(
        name: "Monokai Pro",
        background: ThemeColor(hex: "2d2a2e"),
        foreground: ThemeColor(hex: "fcfcfa"),
        cursor: ThemeColor(hex: "fcfcfa"),
        selection: ThemeColor(hex: "5b595c"),
        palette: [
            ThemeColor(hex: "403e41"),
            ThemeColor(hex: "ff6188"),
            ThemeColor(hex: "a9dc76"),
            ThemeColor(hex: "ffd866"),
            ThemeColor(hex: "fc9867"),
            ThemeColor(hex: "ab9df2"),
            ThemeColor(hex: "78dce8"),
            ThemeColor(hex: "fcfcfa"),
            ThemeColor(hex: "727072"),
            ThemeColor(hex: "ff6188"),
            ThemeColor(hex: "a9dc76"),
            ThemeColor(hex: "ffd866"),
            ThemeColor(hex: "fc9867"),
            ThemeColor(hex: "ab9df2"),
            ThemeColor(hex: "78dce8"),
            ThemeColor(hex: "fcfcfa"),
        ]
    )

    static let allThemes: [TerminalTheme] = [
        .solarizedDark,
        .solarizedLight,
        .dracula,
        .nord,
        .tokyoNight,
        .gruvboxDark,
        .monokai
    ]
}

// MARK: - Font Settings

struct TerminalFont: Codable, Equatable {
    var name: String
    var size: CGFloat

    init(name: String = "Menlo", size: CGFloat = 14) {
        self.name = name
        self.size = size
    }

    static let availableFonts: [String] = [
        "Menlo",
        "SF Mono",
        "Courier New",
        "Monaco",
        "Consolas"
    ]

    var uiFont: UIFont {
        UIFont(name: name, size: size) ?? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    var font: Font {
        .custom(name, size: size)
    }
}

import Foundation
import Combine

final class MacroManager: ObservableObject {
    static let shared = MacroManager()

    @Published var customMacros: [Macro] = []
    @Published var recentMacros: [Macro] = []

    private let maxRecentMacros = 10
    private let userDefaults = UserDefaults.standard
    private let customMacrosKey = "customMacros"
    private let recentMacrosKey = "recentMacros"

    private init() {
        loadMacros()
    }

    // MARK: - Persistence

    private func loadMacros() {
        // Load custom macros
        if let data = userDefaults.data(forKey: customMacrosKey),
           let stored = try? JSONDecoder().decode([StoredMacro].self, from: data) {
            customMacros = stored.map { $0.toMacro() }
        } else {
            // Default custom macros
            customMacros = createDefaultCustomMacros()
        }
    }

    func saveMacros() {
        let stored = customMacros.map { StoredMacro(from: $0) }
        if let data = try? JSONEncoder().encode(stored) {
            userDefaults.set(data, forKey: customMacrosKey)
        }
    }

    // MARK: - CRUD Operations

    func addMacro(_ macro: Macro) {
        customMacros.append(macro)
        saveMacros()
    }

    func updateMacro(_ macro: Macro) {
        if let index = customMacros.firstIndex(where: { $0.id == macro.id }) {
            customMacros[index] = macro
            saveMacros()
        }
    }

    func deleteMacro(_ macro: Macro) {
        customMacros.removeAll { $0.id == macro.id }
        saveMacros()
    }

    func moveMacro(from source: IndexSet, to destination: Int) {
        customMacros.move(fromOffsets: source, toOffset: destination)
        saveMacros()
    }

    // MARK: - Recent Macros

    func recordMacroUse(_ macro: Macro) {
        recentMacros.removeAll { $0.id == macro.id }
        recentMacros.insert(macro, at: 0)

        if recentMacros.count > maxRecentMacros {
            recentMacros.removeLast()
        }
    }

    // MARK: - Import/Export

    func exportMacros() -> Data? {
        let stored = customMacros.map { StoredMacro(from: $0) }
        return try? JSONEncoder().encode(stored)
    }

    func importMacros(from data: Data) -> Bool {
        guard let stored = try? JSONDecoder().decode([StoredMacro].self, from: data) else {
            return false
        }

        let imported = stored.map { $0.toMacro() }
        customMacros.append(contentsOf: imported)
        saveMacros()
        return true
    }

    // MARK: - Default Macros

    private func createDefaultCustomMacros() -> [Macro] {
        return [
            Macro(label: "npm run", icon: "play", action: .sendText("npm run "), category: "custom"),
            Macro(label: "docker ps", icon: "shippingbox", action: .sendCommand("docker ps"), category: "custom"),
            Macro(label: "htop", icon: "chart.bar", action: .sendCommand("htop"), category: "custom"),
            Macro(label: "nvim", icon: "doc.text", action: .sendText("nvim "), category: "custom"),
            Macro(label: "python3", icon: "chevron.left.forwardslash.chevron.right", action: .sendCommand("python3"), category: "custom"),
            Macro(label: "ssh", icon: "network", action: .sendText("ssh "), category: "custom"),
        ]
    }
}

// MARK: - Stored Macro (for persistence)

struct StoredMacro: Codable {
    let id: UUID
    let label: String
    let icon: String?
    let actionType: ActionType
    let actionValue: String
    let colorName: String?
    let category: String

    enum ActionType: String, Codable {
        case sendText
        case sendCommand
        case specialKey
        case tmuxPrefix
    }

    init(from macro: Macro) {
        self.id = macro.id
        self.label = macro.label
        self.icon = macro.icon
        self.category = macro.category
        self.colorName = macro.color.map { colorToString($0) }

        switch macro.action {
        case .sendText(let text):
            self.actionType = .sendText
            self.actionValue = text
        case .sendCommand(let command):
            self.actionType = .sendCommand
            self.actionValue = command
        case .specialKey(let key):
            self.actionType = .specialKey
            self.actionValue = key.rawValue
        case .tmuxPrefix:
            self.actionType = .tmuxPrefix
            self.actionValue = ""
        default:
            self.actionType = .sendText
            self.actionValue = ""
        }
    }

    func toMacro() -> Macro {
        let action: MacroAction
        switch actionType {
        case .sendText:
            action = .sendText(actionValue)
        case .sendCommand:
            action = .sendCommand(actionValue)
        case .specialKey:
            action = .specialKey(SpecialKey(rawValue: actionValue) ?? .escape)
        case .tmuxPrefix:
            action = .tmuxPrefix
        }

        return Macro(
            label: label,
            icon: icon,
            action: action,
            color: colorName.flatMap { stringToColor($0) },
            category: category
        )
    }
}

// MARK: - Color Helpers

private func colorToString(_ color: Color) -> String {
    // Simplified color serialization
    switch color {
    case .red: return "red"
    case .orange: return "orange"
    case .yellow: return "yellow"
    case .green: return "green"
    case .blue: return "blue"
    case .purple: return "purple"
    case .pink: return "pink"
    default: return "primary"
    }
}

private func stringToColor(_ string: String) -> Color? {
    switch string {
    case "red": return .red
    case "orange": return .orange
    case "yellow": return .yellow
    case "green": return .green
    case "blue": return .blue
    case "purple": return .purple
    case "pink": return .pink
    default: return nil
    }
}

import SwiftUI

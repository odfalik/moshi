import SwiftUI

struct MacroEditorView: View {
    @EnvironmentObject var appSettings: AppSettings
    @StateObject private var macroManager = MacroManager.shared

    @State private var showingAddMacro = false
    @State private var editingMacro: Macro?

    var body: some View {
        List {
            // Custom Macros
            Section {
                ForEach(macroManager.customMacros) { macro in
                    MacroEditorRow(macro: macro)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingMacro = macro
                        }
                }
                .onDelete { offsets in
                    for offset in offsets {
                        macroManager.deleteMacro(macroManager.customMacros[offset])
                    }
                }
                .onMove { source, destination in
                    macroManager.moveMacro(from: source, to: destination)
                }

                Button {
                    showingAddMacro = true
                } label: {
                    Label("Add Macro", systemImage: "plus.circle")
                }
            } header: {
                Text("Custom Macros")
            } footer: {
                Text("Custom macros appear in the 'Custom' row of the macro keyboard.")
            }

            // Built-in Macro Preview
            Section("Built-in Macros") {
                NavigationLink {
                    BuiltInMacroList(title: "Special Keys", macros: Macro.specialKeys)
                } label: {
                    Label("Special Keys", systemImage: "keyboard")
                }

                NavigationLink {
                    BuiltInMacroList(title: "Bash", macros: Macro.bashMacros)
                } label: {
                    Label("Bash / CLI", systemImage: "terminal")
                }

                NavigationLink {
                    BuiltInMacroList(title: "Git", macros: Macro.gitMacros)
                } label: {
                    Label("Git", systemImage: "arrow.triangle.branch")
                }

                NavigationLink {
                    BuiltInMacroList(title: "Claude Code", macros: Macro.claudeMacros)
                } label: {
                    Label("Claude Code", systemImage: "bubble.left.and.bubble.right")
                }

                NavigationLink {
                    BuiltInMacroList(title: "Tmux", macros: Macro.tmuxMacros)
                } label: {
                    Label("Tmux", systemImage: "square.split.2x2")
                }
            }

            // Import/Export
            Section {
                Button {
                    exportMacros()
                } label: {
                    Label("Export Macros", systemImage: "square.and.arrow.up")
                }

                Button {
                    // Import would use document picker
                } label: {
                    Label("Import Macros", systemImage: "square.and.arrow.down")
                }
            }
        }
        .navigationTitle("Macros")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                EditButton()
            }
        }
        .sheet(isPresented: $showingAddMacro) {
            MacroEditSheet(macro: nil) { newMacro in
                macroManager.addMacro(newMacro)
            }
        }
        .sheet(item: $editingMacro) { macro in
            MacroEditSheet(macro: macro) { updatedMacro in
                macroManager.updateMacro(updatedMacro)
            }
        }
    }

    private func exportMacros() {
        if let data = macroManager.exportMacros() {
            // Share sheet
            let activityVC = UIActivityViewController(
                activityItems: [data],
                applicationActivities: nil
            )

            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootVC = window.rootViewController {
                rootVC.present(activityVC, animated: true)
            }
        }
    }
}

// MARK: - Macro Editor Row

struct MacroEditorRow: View {
    let macro: Macro

    var body: some View {
        HStack(spacing: 12) {
            if let icon = macro.icon {
                Image(systemName: icon)
                    .foregroundColor(macro.color ?? .primary)
                    .frame(width: 24)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(macro.label)
                    .font(.headline)

                Text(actionDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    var actionDescription: String {
        switch macro.action {
        case .sendText(let text):
            return "Send: \(text)"
        case .sendCommand(let command):
            return "Run: \(command)"
        case .specialKey(let key):
            return "Key: \(key.displayName)"
        case .tmuxPrefix:
            return "Tmux Prefix"
        case .composite:
            return "Multiple actions"
        case .custom:
            return "Custom action"
        }
    }
}

// MARK: - Built-in Macro List

struct BuiltInMacroList: View {
    let title: String
    let macros: [Macro]

    var body: some View {
        List {
            ForEach(macros) { macro in
                HStack(spacing: 12) {
                    if let icon = macro.icon {
                        Image(systemName: icon)
                            .foregroundColor(macro.color ?? .primary)
                            .frame(width: 24)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(macro.label)
                            .font(.headline)

                        Text(actionDescription(for: macro))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle(title)
    }

    func actionDescription(for macro: Macro) -> String {
        switch macro.action {
        case .sendText(let text):
            return "Send: \"\(text)\""
        case .sendCommand(let command):
            return "Run: \(command)"
        case .specialKey(let key):
            return "Send \(key.displayName) key"
        case .tmuxPrefix:
            return "Send tmux prefix"
        case .composite(let actions):
            return "\(actions.count) actions"
        case .custom:
            return "Custom action"
        }
    }
}

// MARK: - Macro Edit Sheet

struct MacroEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    let macro: Macro?
    let onSave: (Macro) -> Void

    @State private var label = ""
    @State private var icon = ""
    @State private var actionType: ActionType = .sendCommand
    @State private var actionValue = ""
    @State private var selectedColor: Color?
    @State private var selectedSpecialKey: SpecialKey = .escape

    enum ActionType: String, CaseIterable {
        case sendText = "Send Text"
        case sendCommand = "Run Command"
        case specialKey = "Special Key"
        case tmuxPrefix = "Tmux Prefix"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    TextField("Label", text: $label)

                    TextField("Icon (SF Symbol name)", text: $icon)
                        .autocapitalization(.none)

                    Picker("Color", selection: $selectedColor) {
                        Text("Default").tag(nil as Color?)
                        ForEach(colorOptions, id: \.self) { color in
                            HStack {
                                Circle().fill(color).frame(width: 16, height: 16)
                            }.tag(color as Color?)
                        }
                    }
                }

                Section("Action") {
                    Picker("Type", selection: $actionType) {
                        ForEach(ActionType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    switch actionType {
                    case .sendText:
                        TextField("Text to send", text: $actionValue)
                            .autocapitalization(.none)

                    case .sendCommand:
                        TextField("Command", text: $actionValue)
                            .autocapitalization(.none)

                    case .specialKey:
                        Picker("Key", selection: $selectedSpecialKey) {
                            ForEach(SpecialKey.allCases, id: \.self) { key in
                                Text(key.displayName).tag(key)
                            }
                        }

                    case .tmuxPrefix:
                        Text("Sends the configured tmux prefix key")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if !icon.isEmpty {
                    Section("Preview") {
                        HStack {
                            Spacer()
                            MacroButton(macro: previewMacro) {}
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle(macro == nil ? "New Macro" : "Edit Macro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveMacro()
                    }
                    .disabled(label.isEmpty)
                }
            }
            .onAppear {
                loadMacro()
            }
        }
    }

    private var colorOptions: [Color] {
        [.red, .orange, .yellow, .green, .blue, .purple, .pink]
    }

    private var previewMacro: Macro {
        Macro(
            label: label.isEmpty ? "Preview" : label,
            icon: icon.isEmpty ? nil : icon,
            action: buildAction(),
            color: selectedColor
        )
    }

    private func loadMacro() {
        guard let macro = macro else { return }

        label = macro.label
        icon = macro.icon ?? ""
        selectedColor = macro.color

        switch macro.action {
        case .sendText(let text):
            actionType = .sendText
            actionValue = text
        case .sendCommand(let command):
            actionType = .sendCommand
            actionValue = command
        case .specialKey(let key):
            actionType = .specialKey
            selectedSpecialKey = key
        case .tmuxPrefix:
            actionType = .tmuxPrefix
        default:
            break
        }
    }

    private func buildAction() -> MacroAction {
        switch actionType {
        case .sendText:
            return .sendText(actionValue)
        case .sendCommand:
            return .sendCommand(actionValue)
        case .specialKey:
            return .specialKey(selectedSpecialKey)
        case .tmuxPrefix:
            return .tmuxPrefix
        }
    }

    private func saveMacro() {
        let newMacro = Macro(
            label: label,
            icon: icon.isEmpty ? nil : icon,
            action: buildAction(),
            color: selectedColor,
            category: "custom"
        )
        onSave(newMacro)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        MacroEditorView()
            .environmentObject(AppSettings.shared)
    }
}

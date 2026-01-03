import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var hostManager: HostManager

    @State private var showingResetConfirmation = false
    @State private var showingClearDataConfirmation = false
    @State private var showingExportSheet = false

    var body: some View {
        NavigationStack {
            Form {
                // Appearance
                Section("Appearance") {
                    Picker("Theme", selection: $appSettings.appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }

                    NavigationLink {
                        ThemePickerView()
                    } label: {
                        HStack {
                            Text("Terminal Theme")
                            Spacer()
                            Text(appSettings.currentTheme.name)
                                .foregroundColor(.secondary)
                        }
                    }

                    NavigationLink {
                        FontSettingsView()
                    } label: {
                        HStack {
                            Text("Font")
                            Spacer()
                            Text("\(appSettings.terminalFont.name) \(Int(appSettings.terminalFont.size))pt")
                                .foregroundColor(.secondary)
                        }
                    }

                    Picker("Cursor Style", selection: $appSettings.cursorStyle) {
                        ForEach(CursorStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }

                    Toggle("Cursor Blink", isOn: $appSettings.cursorBlink)
                }

                // Terminal
                Section("Terminal") {
                    Stepper("Scrollback: \(appSettings.scrollbackLimit) lines", value: $appSettings.scrollbackLimit, in: 1000...100000, step: 1000)

                    Toggle("Bell Sound", isOn: $appSettings.bellSound)
                    Toggle("Bell Vibrate", isOn: $appSettings.bellVibrate)
                    Toggle("Auto-correct", isOn: $appSettings.autoCorrect)
                    Toggle("Smart Quotes", isOn: $appSettings.smartQuotes)
                }

                // Connection
                Section("Connection Defaults") {
                    Toggle("Use Mosh by Default", isOn: $appSettings.defaultUseMosh)
                    Toggle("Auto-attach tmux", isOn: $appSettings.defaultAutoTmux)

                    Stepper("Keep Alive: \(appSettings.keepAliveInterval)s", value: $appSettings.keepAliveInterval, in: 0...300, step: 10)

                    Stepper("Timeout: \(appSettings.connectionTimeout)s", value: $appSettings.connectionTimeout, in: 5...120, step: 5)

                    Toggle("Auto Reconnect", isOn: $appSettings.autoReconnect)
                }

                // Keyboard
                Section("Keyboard") {
                    Toggle("Show Macro Keyboard", isOn: $appSettings.showMacroKeyboard)
                    Toggle("Haptic Feedback", isOn: $appSettings.hapticFeedback)
                    Toggle("Key Click Sound", isOn: $appSettings.keyClickSound)

                    NavigationLink {
                        MacroEditorView()
                    } label: {
                        Text("Manage Macros")
                    }
                }

                // Tmux
                Section("Tmux") {
                    Picker("Prefix Key", selection: $appSettings.tmuxPrefix) {
                        ForEach(TmuxPrefix.allCases) { prefix in
                            Text(prefix.rawValue).tag(prefix)
                        }
                    }

                    TextField("Default Session Name", text: $appSettings.tmuxDefaultSessionName)
                }

                // Security
                Section("Security") {
                    Toggle("Require \(KeychainManager.shared.biometricType())", isOn: $appSettings.requireBiometrics)

                    Toggle("Lock on Background", isOn: $appSettings.lockOnBackground)

                    Stepper("Clipboard Timeout: \(appSettings.clipboardTimeout)s", value: $appSettings.clipboardTimeout, in: 0...300, step: 10)

                    NavigationLink {
                        KeyGeneratorView()
                    } label: {
                        HStack {
                            Text("SSH Keys")
                            Spacer()
                            Text("\(hostManager.sshKeys.count)")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Data Management
                Section("Data") {
                    Button {
                        showingExportSheet = true
                    } label: {
                        Label("Export Hosts", systemImage: "square.and.arrow.up")
                    }

                    Button(role: .destructive) {
                        showingClearDataConfirmation = true
                    } label: {
                        Label("Clear All Data", systemImage: "trash")
                    }
                }

                // About
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Build")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                            .foregroundColor(.secondary)
                    }

                    Button {
                        showingResetConfirmation = true
                    } label: {
                        Text("Reset to Defaults")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Reset Settings?", isPresented: $showingResetConfirmation) {
                Button("Reset", role: .destructive) {
                    appSettings.resetToDefaults()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will reset all settings to their default values.")
            }
            .confirmationDialog("Clear All Data?", isPresented: $showingClearDataConfirmation) {
                Button("Clear All", role: .destructive) {
                    clearAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete all hosts, SSH keys, and saved credentials. This cannot be undone.")
            }
            .sheet(isPresented: $showingExportSheet) {
                ExportHostsSheet()
            }
        }
    }

    private func clearAllData() {
        // Clear hosts
        for host in hostManager.hosts {
            hostManager.deleteHost(host)
        }

        // Clear keys
        for key in hostManager.sshKeys {
            hostManager.deleteKey(key)
        }

        // Clear keychain
        try? KeychainManager.shared.clearAll()

        // Reset settings
        appSettings.resetToDefaults()
    }
}

// MARK: - Theme Picker

struct ThemePickerView: View {
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        List {
            ForEach(TerminalTheme.allThemes) { theme in
                Button {
                    appSettings.currentTheme = theme
                } label: {
                    HStack {
                        ThemePreview(theme: theme)
                            .frame(width: 80, height: 50)
                            .cornerRadius(6)

                        Text(theme.name)
                            .foregroundColor(.primary)

                        Spacer()

                        if theme.id == appSettings.currentTheme.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }
        }
        .navigationTitle("Terminal Theme")
    }
}

struct ThemePreview: View {
    let theme: TerminalTheme

    var body: some View {
        ZStack {
            theme.swiftUIBackground

            VStack(alignment: .leading, spacing: 2) {
                Text("$ ls -la")
                    .foregroundColor(theme.swiftUIForeground)
                Text("file.txt")
                    .foregroundColor(theme.colorForIndex(2)) // Green
            }
            .font(.system(size: 8, design: .monospaced))
            .padding(4)
        }
    }
}

// MARK: - Font Settings

struct FontSettingsView: View {
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        Form {
            Section("Font Family") {
                ForEach(TerminalFont.availableFonts, id: \.self) { fontName in
                    Button {
                        appSettings.terminalFont = TerminalFont(name: fontName, size: appSettings.terminalFont.size)
                    } label: {
                        HStack {
                            Text(fontName)
                                .font(.custom(fontName, size: 17))
                                .foregroundColor(.primary)

                            Spacer()

                            if fontName == appSettings.terminalFont.name {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }

            Section("Font Size") {
                Stepper("\(Int(appSettings.terminalFont.size)) pt", value: Binding(
                    get: { appSettings.terminalFont.size },
                    set: { appSettings.terminalFont = TerminalFont(name: appSettings.terminalFont.name, size: $0) }
                ), in: 8...24, step: 1)
            }

            Section("Preview") {
                Text("The quick brown fox jumps over the lazy dog")
                    .font(appSettings.terminalFont.font)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(appSettings.currentTheme.swiftUIBackground)
                    .foregroundColor(appSettings.currentTheme.swiftUIForeground)
                    .cornerRadius(8)
            }
        }
        .navigationTitle("Font")
    }
}

// MARK: - Export Sheet

struct ExportHostsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var hostManager: HostManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)

                Text("Export \(hostManager.hosts.count) Hosts")
                    .font(.title2.weight(.semibold))

                Text("Create a backup of your host configurations. Passwords are not included for security.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                if let data = hostManager.exportHosts() {
                    ShareLink(item: data, preview: SharePreview("Moshi Hosts Export", image: Image(systemName: "server.rack"))) {
                        Label("Share Export File", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal, 40)
                }
            }
            .padding()
            .navigationTitle("Export Hosts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings.shared)
        .environmentObject(HostManager.shared)
}

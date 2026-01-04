import SwiftUI

struct HostEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var hostManager: HostManager
    @EnvironmentObject var appSettings: AppSettings

    let host: Host?

    @State private var name: String = ""
    @State private var hostname: String = ""
    @State private var port: String = "22"
    @State private var username: String = ""
    @State private var authMethod: AuthMethod = .password
    @State private var password: String = ""
    @State private var selectedKeyId: UUID?

    @State private var useMosh: Bool = false  // Mosh not implemented yet
    @State private var moshPortStart: String = "60000"
    @State private var moshPortEnd: String = "61000"

    @State private var autoTmux: Bool = true
    @State private var tmuxSessionName: String = ""

    @State private var group: String = ""
    @State private var notes: String = ""
    @State private var colorTag: ColorTag?

    @State private var proxyJump: String = ""
    @State private var keepAliveInterval: String = "60"
    @State private var compression: Bool = false

    @State private var showingAdvanced = false
    @State private var showingError = false
    @State private var errorMessage = ""

    var isEditing: Bool { host != nil }

    var body: some View {
        Form {
            // Basic Settings
            Section("Connection") {
                TextField("Name (optional)", text: $name)
                    .textContentType(.nickname)

                TextField("Hostname or IP", text: $hostname)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()

                TextField("Port", text: $port)
                    .keyboardType(.numberPad)

                TextField("Username", text: $username)
                    .textContentType(.username)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
            }

            // Authentication
            Section("Authentication") {
                Picker("Method", selection: $authMethod) {
                    // Filter out SSH Agent - not supported on iOS
                    ForEach(AuthMethod.allCases.filter { $0 != .agent }) { method in
                        Label(method.rawValue, systemImage: method.icon)
                            .tag(method)
                    }
                }

                switch authMethod {
                case .password, .keyAndPassword:
                    SecureField("Password", text: $password)
                        .textContentType(.password)

                case .key, .keyAndPassword:
                    Picker("SSH Key", selection: $selectedKeyId) {
                        Text("None").tag(nil as UUID?)
                        ForEach(hostManager.sshKeys) { key in
                            Text(key.name).tag(key.id as UUID?)
                        }
                    }

                    if hostManager.sshKeys.isEmpty {
                        NavigationLink {
                            KeyGeneratorView()
                        } label: {
                            Label("Generate SSH Key", systemImage: "plus.circle")
                        }
                    }

                case .agent:
                    Text("SSH Agent will be used for authentication")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Connection Type
            Section("Protocol") {
                Toggle(isOn: $useMosh) {
                    VStack(alignment: .leading) {
                        Text("Use Mosh")
                        Text("Roaming and mobile-friendly")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if useMosh {
                    HStack {
                        Text("Port Range")
                        Spacer()
                        TextField("Start", text: $moshPortStart)
                            .frame(width: 60)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        Text("-")
                        TextField("End", text: $moshPortEnd)
                            .frame(width: 60)
                            .keyboardType(.numberPad)
                    }
                }
            }

            // Tmux
            Section("Tmux") {
                Toggle(isOn: $autoTmux) {
                    VStack(alignment: .leading) {
                        Text("Auto-attach tmux")
                        Text("Persistent session on reconnect")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if autoTmux {
                    TextField("Session Name (optional)", text: $tmuxSessionName)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }
            }

            // Organization
            Section("Organization") {
                TextField("Group", text: $group)

                Picker("Color Tag", selection: $colorTag) {
                    Text("None").tag(nil as ColorTag?)
                    ForEach(ColorTag.allCases) { tag in
                        HStack {
                            Circle()
                                .fill(tag.color)
                                .frame(width: 12, height: 12)
                            Text(tag.rawValue.capitalized)
                        }
                        .tag(tag as ColorTag?)
                    }
                }

                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }

            // Advanced
            Section {
                DisclosureGroup("Advanced Settings", isExpanded: $showingAdvanced) {
                    TextField("Proxy Jump (bastion host)", text: $proxyJump)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()

                    TextField("Keep Alive Interval (seconds)", text: $keepAliveInterval)
                        .keyboardType(.numberPad)

                    Toggle("Compression", isOn: $compression)
                }
            }
        }
        .navigationTitle(isEditing ? "Edit Host" : "New Host")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(isEditing ? "Save" : "Add") {
                    saveHost()
                }
                .disabled(!isValid)
            }
        }
        .onAppear {
            loadHost()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Validation

    var isValid: Bool {
        !hostname.isEmpty && !username.isEmpty && Int(port) != nil
    }

    // MARK: - Load/Save

    private func loadHost() {
        guard let host = host else {
            // Set defaults from app settings
            useMosh = appSettings.defaultUseMosh
            autoTmux = appSettings.defaultAutoTmux
            return
        }

        name = host.name
        hostname = host.hostname
        port = String(host.port)
        username = host.username
        authMethod = host.authMethod
        selectedKeyId = host.sshKeyId
        useMosh = host.useMosh
        moshPortStart = String(host.moshPorts.start)
        moshPortEnd = String(host.moshPorts.end)
        autoTmux = host.autoTmux
        tmuxSessionName = host.tmuxSessionName ?? ""
        group = host.group ?? ""
        notes = host.notes ?? ""
        colorTag = host.colorTag
        proxyJump = host.proxyJump ?? ""
        keepAliveInterval = String(host.keepAliveInterval)
        compression = host.compression

        // Load password from keychain
        if let savedPassword = try? KeychainManager.shared.getPassword(for: host.id) {
            password = savedPassword
        }
    }

    private func saveHost() {
        guard let portInt = Int(port) else {
            errorMessage = "Invalid port number"
            showingError = true
            return
        }

        let moshPorts = MoshPortRange(
            start: Int(moshPortStart) ?? 60000,
            end: Int(moshPortEnd) ?? 61000
        )

        let newHost = Host(
            id: host?.id ?? UUID(),
            name: name,
            hostname: hostname,
            port: portInt,
            username: username,
            authMethod: authMethod,
            useMosh: useMosh,
            moshPorts: moshPorts,
            autoTmux: autoTmux,
            tmuxSessionName: tmuxSessionName.isEmpty ? nil : tmuxSessionName,
            group: group.isEmpty ? nil : group,
            notes: notes.isEmpty ? nil : notes,
            lastConnected: host?.lastConnected,
            isFavorite: host?.isFavorite ?? false,
            colorTag: colorTag,
            sshKeyId: selectedKeyId,
            proxyJump: proxyJump.isEmpty ? nil : proxyJump,
            keepAliveInterval: Int(keepAliveInterval) ?? 60,
            compression: compression
        )

        // Save password to keychain
        if !password.isEmpty {
            do {
                try KeychainManager.shared.savePassword(password, for: newHost.id)
            } catch {
                errorMessage = "Failed to save password: \(error.localizedDescription)"
                showingError = true
                return
            }
        }

        if isEditing {
            hostManager.updateHost(newHost)
        } else {
            hostManager.addHost(newHost)
        }

        dismiss()
    }
}

#Preview {
    NavigationStack {
        HostEditView(host: nil)
            .environmentObject(HostManager.shared)
            .environmentObject(AppSettings.shared)
    }
}

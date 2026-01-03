import SwiftUI

struct QuickConnectView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var hostManager: HostManager
    @EnvironmentObject var appSettings: AppSettings

    @State private var connectionString = ""
    @State private var password = ""
    @State private var useMosh = true
    @State private var autoTmux = true
    @State private var isConnecting = false
    @State private var errorMessage: String?

    @FocusState private var focusedField: Field?

    enum Field {
        case connection, password
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("user@hostname:port", text: $connectionString)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .textContentType(.URL)
                        .focused($focusedField, equals: .connection)
                        .onSubmit {
                            focusedField = .password
                        }

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .onSubmit {
                            connect()
                        }
                } header: {
                    Text("Connection")
                } footer: {
                    Text("Format: user@hostname or user@hostname:port")
                        .font(.caption)
                }

                Section {
                    Toggle(isOn: $useMosh) {
                        Label("Use Mosh", systemImage: "antenna.radiowaves.left.and.right")
                    }

                    Toggle(isOn: $autoTmux) {
                        Label("Auto-attach tmux", systemImage: "square.split.2x2")
                    }
                } header: {
                    Text("Options")
                }

                // Recent connections
                if !sessionManager.recentConnections.isEmpty {
                    Section("Recent") {
                        ForEach(sessionManager.recentConnections.prefix(5)) { host in
                            Button {
                                connectionString = "\(host.username)@\(host.hostname)"
                                if host.port != 22 {
                                    connectionString += ":\(host.port)"
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(host.displayName)
                                            .foregroundColor(.primary)
                                        Text(host.connectionString)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    if let date = host.lastConnected {
                                        Text(date, style: .relative)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                // Error message
                if let error = errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Quick Connect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        connect()
                    } label: {
                        if isConnecting {
                            ProgressView()
                        } else {
                            Text("Connect")
                        }
                    }
                    .disabled(connectionString.isEmpty || isConnecting)
                }
            }
            .onAppear {
                useMosh = appSettings.defaultUseMosh
                autoTmux = appSettings.defaultAutoTmux
                focusedField = .connection
            }
        }
    }

    private func connect() {
        guard !connectionString.isEmpty else { return }

        isConnecting = true
        errorMessage = nil

        Task {
            do {
                // Parse connection string
                let host = parseConnectionString()

                // Save password if provided
                if !password.isEmpty {
                    try KeychainManager.shared.savePassword(password, for: host.id)
                }

                // Create session
                _ = try await sessionManager.createSession(for: host)

                await MainActor.run {
                    dismiss()
                }

            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isConnecting = false
                }
            }
        }
    }

    private func parseConnectionString() -> Host {
        var username = "root"
        var hostname = connectionString
        var port = 22

        // Parse user@host:port format
        if let atIndex = connectionString.lastIndex(of: "@") {
            username = String(connectionString[..<atIndex])
            hostname = String(connectionString[connectionString.index(after: atIndex)...])
        }

        if let colonIndex = hostname.lastIndex(of: ":") {
            if let parsedPort = Int(hostname[hostname.index(after: colonIndex)...]) {
                port = parsedPort
                hostname = String(hostname[..<colonIndex])
            }
        }

        return Host(
            hostname: hostname,
            port: port,
            username: username,
            authMethod: password.isEmpty ? .key : .password,
            useMosh: useMosh,
            autoTmux: autoTmux
        )
    }
}

#Preview {
    QuickConnectView()
        .environmentObject(SessionManager.shared)
        .environmentObject(HostManager.shared)
        .environmentObject(AppSettings.shared)
}

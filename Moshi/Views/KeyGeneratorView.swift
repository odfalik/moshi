import SwiftUI

struct KeyGeneratorView: View {
    @EnvironmentObject var hostManager: HostManager

    @State private var showingGenerateSheet = false
    @State private var showingImportSheet = false
    @State private var selectedKey: SSHKey?

    var body: some View {
        List {
            if hostManager.sshKeys.isEmpty {
                ContentUnavailableView(
                    "No SSH Keys",
                    systemImage: "key",
                    description: Text("Generate or import an SSH key to use for authentication")
                )
            } else {
                ForEach(hostManager.sshKeys) { key in
                    SSHKeyRow(key: key)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedKey = key
                        }
                }
                .onDelete { offsets in
                    for offset in offsets {
                        hostManager.deleteKey(hostManager.sshKeys[offset])
                    }
                }
            }
        }
        .navigationTitle("SSH Keys")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingGenerateSheet = true
                    } label: {
                        Label("Generate New Key", systemImage: "plus")
                    }

                    Button {
                        showingImportSheet = true
                    } label: {
                        Label("Import Key", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingGenerateSheet) {
            KeyGenerateSheet()
        }
        .sheet(isPresented: $showingImportSheet) {
            KeyImportSheet()
        }
        .sheet(item: $selectedKey) { key in
            KeyDetailSheet(key: key)
        }
    }
}

// MARK: - SSH Key Row

struct SSHKeyRow: View {
    let key: SSHKey

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.horizontal")
                .foregroundColor(.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(key.name)
                    .font(.headline)

                HStack(spacing: 8) {
                    Text(key.type.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray5))
                        .cornerRadius(4)

                    Text(key.fingerprint.prefix(20) + "...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text(key.createdAt, style: .date)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Generate Key Sheet

struct KeyGenerateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var hostManager: HostManager

    @State private var name = ""
    @State private var keyType: SSHKey.KeyType = .ed25519
    @State private var comment = ""
    @State private var passphrase = ""
    @State private var confirmPassphrase = ""
    @State private var isGenerating = false
    @State private var generatedKey: GeneratedKeyInfo?
    @State private var errorMessage: String?

    struct GeneratedKeyInfo {
        let key: SSHKey
        let publicKey: String
    }

    var body: some View {
        NavigationStack {
            if let keyInfo = generatedKey {
                // Show generated key
                GeneratedKeyView(keyInfo: keyInfo) {
                    dismiss()
                }
            } else {
                // Key generation form
                Form {
                    Section("Key Details") {
                        TextField("Name", text: $name)
                            .textContentType(.name)

                        Picker("Type", selection: $keyType) {
                            ForEach(SSHKey.KeyType.allCases, id: \.self) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }

                        TextField("Comment (optional)", text: $comment)
                    }

                    Section {
                        SecureField("Passphrase (optional)", text: $passphrase)

                        if !passphrase.isEmpty {
                            SecureField("Confirm Passphrase", text: $confirmPassphrase)
                        }
                    } header: {
                        Text("Passphrase")
                    } footer: {
                        Text("A passphrase adds extra protection. You'll need to enter it each time you use the key.")
                    }

                    if let error = errorMessage {
                        Section {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .foregroundColor(.red)
                        }
                    }
                }
                .navigationTitle("Generate SSH Key")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            generateKey()
                        } label: {
                            if isGenerating {
                                ProgressView()
                            } else {
                                Text("Generate")
                            }
                        }
                        .disabled(name.isEmpty || isGenerating || (!passphrase.isEmpty && passphrase != confirmPassphrase))
                    }
                }
            }
        }
    }

    private func generateKey() {
        guard !passphrase.isEmpty && passphrase != confirmPassphrase else {
            if !passphrase.isEmpty {
                errorMessage = "Passphrases don't match"
                return
            }
            errorMessage = nil
            return
        }

        isGenerating = true
        errorMessage = nil

        Task {
            do {
                let keyManager = SSHKeyManager.shared

                let (privateKeyData, publicKey, fingerprint) = try keyManager.generateKeyPair(
                    type: keyType,
                    comment: comment.isEmpty ? nil : comment
                )

                // Save private key to keychain
                let keyId = UUID()
                try KeychainManager.shared.savePrivateKey(
                    privateKeyData,
                    for: keyId,
                    passphrase: passphrase.isEmpty ? nil : passphrase
                )

                let sshKey = SSHKey(
                    id: keyId,
                    name: name,
                    type: keyType,
                    publicKey: publicKey,
                    fingerprint: fingerprint,
                    comment: comment.isEmpty ? nil : comment
                )

                await MainActor.run {
                    hostManager.addKey(sshKey)
                    generatedKey = GeneratedKeyInfo(key: sshKey, publicKey: publicKey)
                    isGenerating = false
                }

            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }
}

// MARK: - Generated Key View

struct GeneratedKeyView: View {
    let keyInfo: KeyGenerateSheet.GeneratedKeyInfo
    let onDone: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            Text("Key Generated!")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("Public Key")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(keyInfo.publicKey)
                    .font(.system(size: 11, design: .monospaced))
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            }
            .padding(.horizontal)

            VStack(spacing: 16) {
                Button {
                    UIPasteboard.general.string = keyInfo.publicKey
                    copied = true

                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied!" : "Copy Public Key", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                ShareLink(item: keyInfo.publicKey) {
                    Label("Share Public Key", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 40)

            Text("Add this public key to your server's ~/.ssh/authorized_keys file")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .navigationTitle("SSH Key")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Import Key Sheet

struct KeyImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var hostManager: HostManager

    @State private var name = ""
    @State private var privateKeyPEM = ""
    @State private var passphrase = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Key Details") {
                    TextField("Name", text: $name)
                }

                Section {
                    TextEditor(text: $privateKeyPEM)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 150)
                } header: {
                    Text("Private Key")
                } footer: {
                    Text("Paste your private key in PEM format (-----BEGIN ... -----)")
                }

                Section {
                    SecureField("Passphrase (if encrypted)", text: $passphrase)
                }

                if let error = errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Import SSH Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        importKey()
                    }
                    .disabled(name.isEmpty || privateKeyPEM.isEmpty)
                }
            }
        }
    }

    private func importKey() {
        do {
            let keyManager = SSHKeyManager.shared
            let (keyType, keyData) = try keyManager.importPrivateKey(from: privateKeyPEM)

            // Generate public key and fingerprint
            let (_, publicKey, fingerprint) = try keyManager.generateKeyPair(type: keyType)

            let keyId = UUID()

            // Save to keychain
            try KeychainManager.shared.savePrivateKey(
                keyData,
                for: keyId,
                passphrase: passphrase.isEmpty ? nil : passphrase
            )

            let sshKey = SSHKey(
                id: keyId,
                name: name,
                type: keyType,
                publicKey: publicKey,
                fingerprint: fingerprint
            )

            hostManager.addKey(sshKey)
            dismiss()

        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Key Detail Sheet

struct KeyDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var hostManager: HostManager

    let key: SSHKey

    @State private var showingDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section("Details") {
                    LabeledContent("Name", value: key.name)
                    LabeledContent("Type", value: key.type.rawValue)
                    LabeledContent("Created", value: key.createdAt.formatted())

                    if let comment = key.comment {
                        LabeledContent("Comment", value: comment)
                    }
                }

                Section("Fingerprint") {
                    Text(key.fingerprint)
                        .font(.system(size: 12, design: .monospaced))
                }

                Section("Public Key") {
                    Text(key.publicKey)
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(nil)

                    Button {
                        UIPasteboard.general.string = key.publicKey
                    } label: {
                        Label("Copy Public Key", systemImage: "doc.on.doc")
                    }

                    ShareLink(item: key.publicKey) {
                        Label("Share Public Key", systemImage: "square.and.arrow.up")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Key", systemImage: "trash")
                    }
                }
            }
            .navigationTitle(key.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Delete SSH Key?", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    hostManager.deleteKey(key)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete the key. Any hosts using this key will need to be updated.")
            }
        }
    }
}

#Preview {
    NavigationStack {
        KeyGeneratorView()
            .environmentObject(HostManager.shared)
    }
}

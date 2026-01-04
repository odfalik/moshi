import Foundation
import Citadel
import Crypto
import NIO
import NIOSSH

protocol SSHConnectionDelegate: AnyObject {
    func connectionDidReceiveOutput(_ output: String)
    func connectionDidDisconnect(error: Error?)
    func connectionDidChangeState(_ newState: ConnectionState)

    /// Called when connecting to a new host - return true to trust the key
    func connectionShouldTrustNewHost(fingerprint: String) async -> Bool

    /// Called when host key changed - return true to trust (dangerous!)
    func connectionHostKeyChanged(newFingerprint: String, oldFingerprint: String) async -> Bool
}

final class SSHConnection: @unchecked Sendable {
    private let host: Host
    private var client: SSHClient?
    private var stdinWriter: TTYStdinWriter?
    private var shellTask: Task<Void, Never>?
    private var authenticated = false

    weak var delegate: SSHConnectionDelegate?

    private var cols: Int = 80
    private var rows: Int = 24

    init(host: Host) {
        self.host = host
    }

    deinit {
        shellTask?.cancel()
    }

    // MARK: - Connection Lifecycle

    func connect() async throws {
        delegate?.connectionDidChangeState(.connecting)

        do {
            let authMethod = try await buildAuthMethod()

            // Create host key validator with callbacks to delegate
            let hostKeyValidator = createHostKeyValidator()

            client = try await SSHClient.connect(
                host: host.hostname,
                port: host.port,
                authenticationMethod: authMethod,
                hostKeyValidator: hostKeyValidator,
                reconnect: .never
            )

            delegate?.connectionDidChangeState(.authenticating)
            authenticated = true
            delegate?.connectionDidChangeState(.connected)

            Logger.network.info("SSH connection established to \(host.hostname)")

            // Start shell session
            if #available(iOS 18.0, *) {
                try await startShell()
            } else {
                try await startShellLegacy()
            }

        } catch {
            delegate?.connectionDidChangeState(.error(error.localizedDescription))
            throw error
        }
    }

    private func createHostKeyValidator() -> SSHHostKeyValidator {
        let hostname = host.hostname
        let port = host.port

        let validator = InteractiveHostKeyValidator(
            hostname: hostname,
            port: port,
            onNewHost: { [weak self] (_: NIOSSHPublicKey, fingerprint: String) async -> Bool in
                guard let delegate = self?.delegate else {
                    // No delegate - auto-accept (for backward compatibility)
                    return true
                }
                return await delegate.connectionShouldTrustNewHost(fingerprint: fingerprint)
            },
            onKeyChanged: { [weak self] (_: NIOSSHPublicKey, newFingerprint: String, oldFingerprint: String) async -> Bool in
                guard let delegate = self?.delegate else {
                    // No delegate - reject key changes by default (security)
                    return false
                }
                return await delegate.connectionHostKeyChanged(
                    newFingerprint: newFingerprint,
                    oldFingerprint: oldFingerprint
                )
            }
        )

        return .custom(validator)
    }

    private func buildAuthMethod() async throws -> SSHAuthenticationMethod {
        switch host.authMethod {
        case .password:
            guard let password = try KeychainManager.shared.getPassword(for: host.id) else {
                throw SSHError.authenticationFailed("No password stored")
            }
            return .passwordBased(username: host.username, password: password)

        case .key:
            guard let keyId = host.sshKeyId,
                  let privateKeyData = try KeychainManager.shared.getPrivateKey(for: keyId) else {
                throw SSHError.authenticationFailed("No SSH key found")
            }
            let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
            return .ed25519(username: host.username, privateKey: privateKey)

        case .keyAndPassword:
            // Try key first, fall back to password
            if let keyId = host.sshKeyId,
               let privateKeyData = try KeychainManager.shared.getPrivateKey(for: keyId),
               let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData) {
                return .ed25519(username: host.username, privateKey: privateKey)
            }
            guard let password = try KeychainManager.shared.getPassword(for: host.id) else {
                throw SSHError.authenticationFailed("No credentials stored")
            }
            return .passwordBased(username: host.username, password: password)

        case .agent:
            throw SSHError.authenticationFailed("SSH Agent not available on iOS")
        }
    }

    // MARK: - Shell Session

    @available(iOS 18.0, *)
    private func startShell() async throws {
        guard let client = client else {
            throw SSHError.notConnected
        }

        let ptyRequest = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: "xterm-256color",
            terminalCharacterWidth: cols,
            terminalRowHeight: rows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: .init([:])
        )

        // Use a continuation to wait for stdinWriter to be set
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var continuationResumed = false

            // Start shell in background task so it persists
            shellTask = Task { [weak self] in
                do {
                    try await client.withPTY(ptyRequest) { inbound, outbound in
                        guard let self = self else { return }

                        // Store the writer for sending input
                        await MainActor.run {
                            self.stdinWriter = outbound
                            Logger.network.info("SSHConnection: stdinWriter set, ready for input")
                        }

                        // Signal that we're ready
                        if !continuationResumed {
                            continuationResumed = true
                            continuation.resume()
                        }

                        // Read output
                        for try await output in inbound {
                            switch output {
                            case .stdout(var buffer):
                                if let text = buffer.readString(length: buffer.readableBytes) {
                                    await MainActor.run {
                                        self.delegate?.connectionDidReceiveOutput(text)
                                    }
                                }
                            case .stderr(var buffer):
                                if let text = buffer.readString(length: buffer.readableBytes) {
                                    await MainActor.run {
                                        self.delegate?.connectionDidReceiveOutput(text)
                                    }
                                }
                            }
                        }
                    }

                    // Shell ended normally
                    await MainActor.run { [weak self] in
                        self?.delegate?.connectionDidDisconnect(error: nil)
                    }
                } catch {
                    // Resume continuation with error if not already resumed
                    if !continuationResumed {
                        continuationResumed = true
                        continuation.resume(throwing: error)
                    }
                    await MainActor.run { [weak self] in
                        self?.delegate?.connectionDidDisconnect(error: error)
                    }
                }
            }
        }
    }

    // Fallback for iOS 17 - limited functionality
    private func startShellLegacy() async throws {
        // iOS 17 doesn't support the PTY API needed for interactive shells
        // Throw a clear error so users know they need iOS 18+
        throw SSHError.unsupportedIOSVersion
    }

    // MARK: - Data I/O

    /// Check if the connection is ready for input
    var isReady: Bool {
        authenticated && stdinWriter != nil && shellTask != nil && !shellTask!.isCancelled
    }

    func send(_ text: String) {
        guard authenticated else {
            Logger.network.debug("SSHConnection.send: Not authenticated, dropping input")
            return
        }

        // Check if shell task is still running
        guard let task = shellTask, !task.isCancelled else {
            Logger.network.warning("SSHConnection.send: Shell task not running, notifying disconnect")
            delegate?.connectionDidDisconnect(error: SSHError.connectionClosed)
            return
        }

        Task {
            do {
                if let writer = stdinWriter {
                    var buffer = ByteBuffer()
                    buffer.writeString(text)
                    try await writer.write(buffer)
                    Logger.network.debug("SSHConnection.send: Sent \(text.count) characters")
                } else {
                    Logger.network.warning("SSHConnection.send: stdinWriter is nil, connection may be closing")
                    // Don't immediately disconnect - the writer might be temporarily unavailable
                }
            } catch {
                Logger.network.error("Failed to send data: \(error.localizedDescription)")
                // Notify about the error so the UI can show it
                await MainActor.run { [weak self] in
                    self?.delegate?.connectionDidDisconnect(error: error)
                }
            }
        }
    }

    func resize(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows

        Logger.network.info("Resize requested: \(cols)x\(rows), stdinWriter: \(stdinWriter != nil ? "ready" : "nil")")

        Task {
            do {
                if let writer = stdinWriter {
                    try await writer.changeSize(
                        cols: cols,
                        rows: rows,
                        pixelWidth: 0,
                        pixelHeight: 0
                    )
                    Logger.network.info("Resize sent successfully: \(cols)x\(rows)")
                } else {
                    Logger.network.warning("Cannot resize: stdinWriter not ready yet")
                }
            } catch {
                Logger.network.error("Failed to resize: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Command Execution

    func executeCommand(_ command: String) async throws -> String {
        guard let client = client else {
            throw SSHError.notConnected
        }

        var result = try await client.executeCommand(command)
        return result.readString(length: result.readableBytes) ?? ""
    }

    // MARK: - Mosh Support (Placeholder)

    func startMoshServer(portRange: MoshPortRange) async throws -> MoshServerInfo {
        let command = "mosh-server new -p \(portRange.start):\(portRange.end) -l LANG=en_US.UTF-8"
        let output = try await executeCommand(command)

        // Parse mosh-server output: MOSH CONNECT <port> <key>
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            if line.hasPrefix("MOSH CONNECT") {
                let components = line.components(separatedBy: " ")
                if components.count >= 4,
                   let port = Int(components[2]) {
                    let key = components[3].trimmingCharacters(in: .whitespacesAndNewlines)
                    return MoshServerInfo(port: port, key: key)
                }
            }
        }

        throw SSHError.moshServerFailed
    }

    // MARK: - Disconnect

    func disconnect() {
        authenticated = false
        shellTask?.cancel()
        shellTask = nil
        stdinWriter = nil

        Task {
            try? await client?.close()
            client = nil
        }
    }
}

// MARK: - Errors

enum SSHError: LocalizedError {
    case notConnected
    case connectionClosed
    case protocolMismatch
    case keyExchangeFailed
    case authenticationFailed(String)
    case invalidKey
    case invalidPacket
    case moshServerFailed
    case timeout
    case unsupportedIOSVersion

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to server"
        case .connectionClosed:
            return "Connection closed by server"
        case .protocolMismatch:
            return "SSH protocol version mismatch"
        case .keyExchangeFailed:
            return "Key exchange failed"
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        case .invalidKey:
            return "Invalid SSH key"
        case .invalidPacket:
            return "Invalid SSH packet received"
        case .moshServerFailed:
            return "Failed to start mosh-server"
        case .timeout:
            return "Connection timed out"
        case .unsupportedIOSVersion:
            return "Interactive terminal requires iOS 18 or later"
        }
    }
}

// MARK: - Mosh Server Info

struct MoshServerInfo {
    let port: Int
    let key: String
}

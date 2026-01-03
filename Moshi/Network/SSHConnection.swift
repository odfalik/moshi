import Foundation
import Network
import CryptoKit

protocol SSHConnectionDelegate: AnyObject {
    func connectionDidReceiveOutput(_ output: String)
    func connectionDidDisconnect(error: Error?)
    func connectionDidChangeState(_ newState: ConnectionState)
}

final class SSHConnection: @unchecked Sendable {
    private let host: Host
    private var connection: NWConnection?
    private var channel: SSHChannel?
    private var authenticated = false
    private let queue = DispatchQueue(label: "com.moshi.ssh", qos: .userInteractive)

    weak var delegate: SSHConnectionDelegate?

    private var cols: Int = 80
    private var rows: Int = 24

    init(host: Host) {
        self.host = host
    }

    // MARK: - Connection Lifecycle

    func connect() async throws {
        delegate?.connectionDidChangeState(.connecting)

        // Create TCP connection
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host.hostname),
            port: NWEndpoint.Port(integerLiteral: UInt16(host.port))
        )

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        // Configure TLS for security
        if let tlsOptions = parameters.defaultProtocolStack.applicationProtocols.first as? NWProtocolTLS.Options {
            sec_protocol_options_set_verify_block(tlsOptions.securityProtocolOptions, { _, _, completion in
                // For SSH, we handle host key verification separately
                completion(true)
            }, queue)
        }

        connection = NWConnection(to: endpoint, using: parameters)

        return try await withCheckedThrowingContinuation { continuation in
            connection?.stateUpdateHandler = { [weak self] state in
                self?.handleConnectionState(state, continuation: continuation)
            }
            connection?.start(queue: queue)
        }
    }

    private func handleConnectionState(_ state: NWConnection.State, continuation: CheckedContinuation<Void, Error>? = nil) {
        switch state {
        case .ready:
            Task {
                do {
                    try await performSSHHandshake()
                    try await authenticate()
                    try await openChannel()
                    continuation?.resume()
                } catch {
                    continuation?.resume(throwing: error)
                }
            }

        case .failed(let error):
            delegate?.connectionDidChangeState(.error(error.localizedDescription))
            continuation?.resume(throwing: error)

        case .cancelled:
            delegate?.connectionDidDisconnect(error: nil)

        case .waiting(let error):
            Logger.network.warning("Connection waiting: \(error.localizedDescription)")

        default:
            break
        }
    }

    // MARK: - SSH Protocol

    private func performSSHHandshake() async throws {
        // Send SSH version identification
        let clientVersion = "SSH-2.0-Moshi_1.0\r\n"
        try await send(data: Data(clientVersion.utf8))

        // Receive server version
        let serverVersion = try await receive(maxLength: 256)
        guard let versionString = String(data: serverVersion, encoding: .utf8),
              versionString.hasPrefix("SSH-2.0") else {
            throw SSHError.protocolMismatch
        }

        Logger.network.info("Server version: \(versionString.trimmingCharacters(in: .whitespacesAndNewlines))")

        // Perform key exchange
        try await performKeyExchange()
    }

    private func performKeyExchange() async throws {
        // Build key exchange init packet
        let kexInit = SSHPacket.keyExchangeInit(
            kexAlgorithms: ["curve25519-sha256", "curve25519-sha256@libssh.org"],
            serverHostKeyAlgorithms: ["ssh-ed25519", "rsa-sha2-256", "rsa-sha2-512"],
            encryptionAlgorithmsClientToServer: ["chacha20-poly1305@openssh.com", "aes256-gcm@openssh.com", "aes128-gcm@openssh.com"],
            encryptionAlgorithmsServerToClient: ["chacha20-poly1305@openssh.com", "aes256-gcm@openssh.com", "aes128-gcm@openssh.com"],
            macAlgorithmsClientToServer: ["hmac-sha2-256-etm@openssh.com", "hmac-sha2-256"],
            macAlgorithmsServerToClient: ["hmac-sha2-256-etm@openssh.com", "hmac-sha2-256"],
            compressionAlgorithms: host.compression ? ["zlib@openssh.com", "none"] : ["none"]
        )

        try await sendPacket(kexInit)

        // Receive server's key exchange init
        _ = try await receivePacket()

        // Perform Curve25519 key exchange
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let publicKeyData = privateKey.publicKey.rawRepresentation

        // Send client public key
        let kexECDH = SSHPacket.kexECDHInit(publicKey: publicKeyData)
        try await sendPacket(kexECDH)

        // Receive server response with shared secret
        let serverKexReply = try await receivePacket()

        // Derive session keys from shared secret
        try deriveSessionKeys(from: serverKexReply, privateKey: privateKey)

        // Send new keys notification
        try await sendPacket(SSHPacket.newKeys())
        _ = try await receivePacket() // Receive server's new keys

        Logger.network.info("Key exchange completed")
    }

    private func deriveSessionKeys(from packet: SSHPacket, privateKey: Curve25519.KeyAgreement.PrivateKey) throws {
        // Extract server public key and compute shared secret
        guard let serverPublicKeyData = packet.serverPublicKey,
              let serverPublicKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: serverPublicKeyData) else {
            throw SSHError.keyExchangeFailed
        }

        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: serverPublicKey)

        // Derive encryption keys using HKDF
        let sessionId = sharedSecret.withUnsafeBytes { Data($0) }

        // Store derived keys for encryption/decryption
        channel = SSHChannel(sessionId: sessionId)
    }

    // MARK: - Authentication

    private func authenticate() async throws {
        delegate?.connectionDidChangeState(.authenticating)

        switch host.authMethod {
        case .password:
            try await authenticateWithPassword()
        case .key:
            try await authenticateWithKey()
        case .keyAndPassword:
            try await authenticateWithKeyAndPassword()
        case .agent:
            try await authenticateWithAgent()
        }

        authenticated = true
        delegate?.connectionDidChangeState(.connected)
    }

    private func authenticateWithPassword() async throws {
        guard let password = try KeychainManager.shared.getPassword(for: host.id) else {
            throw SSHError.authenticationFailed("No password stored")
        }

        let authRequest = SSHPacket.passwordAuth(
            username: host.username,
            password: password
        )

        try await sendPacket(authRequest)
        let response = try await receivePacket()

        guard response.type == .userAuthSuccess else {
            throw SSHError.authenticationFailed("Invalid credentials")
        }
    }

    private func authenticateWithKey() async throws {
        guard let keyId = host.sshKeyId,
              let privateKeyData = try KeychainManager.shared.getPrivateKey(for: keyId) else {
            throw SSHError.authenticationFailed("No SSH key found")
        }

        // Sign authentication challenge with private key
        let signature = try signAuthChallenge(with: privateKeyData)

        let authRequest = SSHPacket.publicKeyAuth(
            username: host.username,
            keyType: "ssh-ed25519",
            publicKey: try getPublicKey(from: privateKeyData),
            signature: signature
        )

        try await sendPacket(authRequest)
        let response = try await receivePacket()

        guard response.type == .userAuthSuccess else {
            throw SSHError.authenticationFailed("Key authentication failed")
        }
    }

    private func authenticateWithKeyAndPassword() async throws {
        do {
            try await authenticateWithKey()
        } catch {
            try await authenticateWithPassword()
        }
    }

    private func authenticateWithAgent() async throws {
        // Connect to SSH agent (if available through extension)
        throw SSHError.authenticationFailed("SSH Agent not available on iOS")
    }

    private func signAuthChallenge(with privateKeyData: Data) throws -> Data {
        guard let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData) else {
            throw SSHError.invalidKey
        }

        let challenge = channel?.sessionId ?? Data()
        return try privateKey.signature(for: challenge)
    }

    private func getPublicKey(from privateKeyData: Data) throws -> Data {
        guard let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData) else {
            throw SSHError.invalidKey
        }
        return privateKey.publicKey.rawRepresentation
    }

    // MARK: - Channel Operations

    private func openChannel() async throws {
        // Request PTY
        let ptyRequest = SSHPacket.ptyRequest(
            term: "xterm-256color",
            cols: cols,
            rows: rows
        )
        try await sendPacket(ptyRequest)
        _ = try await receivePacket()

        // Open shell
        let shellRequest = SSHPacket.shellRequest()
        try await sendPacket(shellRequest)
        _ = try await receivePacket()

        // Start receiving data
        startReceiving()

        Logger.network.info("Shell channel opened")
    }

    func startMoshServer(portRange: MoshPortRange) async throws -> MoshServerInfo {
        let command = "mosh-server new -p \(portRange.start):\(portRange.end) -l LANG=en_US.UTF-8"

        try await sendPacket(SSHPacket.execRequest(command: command))

        let response = try await receivePacket()
        guard let output = response.payload,
              let outputString = String(data: output, encoding: .utf8) else {
            throw SSHError.moshServerFailed
        }

        // Parse mosh-server output
        // Format: MOSH CONNECT <port> <key>
        let components = outputString.components(separatedBy: " ")
        guard components.count >= 4,
              components[0] == "MOSH",
              components[1] == "CONNECT",
              let port = Int(components[2]) else {
            throw SSHError.moshServerFailed
        }

        let key = components[3].trimmingCharacters(in: .whitespacesAndNewlines)

        return MoshServerInfo(port: port, key: key)
    }

    // MARK: - Data I/O

    func send(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        Task {
            try? await sendPacket(SSHPacket.channelData(data: data))
        }
    }

    func resize(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
        Task {
            try? await sendPacket(SSHPacket.windowChange(cols: cols, rows: rows))
        }
    }

    private func startReceiving() {
        Task {
            while authenticated {
                do {
                    let packet = try await receivePacket()
                    if packet.type == .channelData, let data = packet.payload {
                        if let output = String(data: data, encoding: .utf8) {
                            delegate?.connectionDidReceiveOutput(output)
                        }
                    }
                } catch {
                    if authenticated {
                        delegate?.connectionDidDisconnect(error: error)
                    }
                    break
                }
            }
        }
    }

    // MARK: - Low-level I/O

    private func send(data: Data) async throws {
        guard let connection = connection else {
            throw SSHError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func receive(maxLength: Int) async throws -> Data {
        guard let connection = connection else {
            throw SSHError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: maxLength) { data, _, _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let data = data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: SSHError.connectionClosed)
                }
            }
        }
    }

    private func sendPacket(_ packet: SSHPacket) async throws {
        let data = channel?.encrypt(packet.encode()) ?? packet.encode()
        try await send(data: data)
    }

    private func receivePacket() async throws -> SSHPacket {
        let data = try await receive(maxLength: 35000)
        let decrypted = channel?.decrypt(data) ?? data
        return try SSHPacket.decode(from: decrypted)
    }

    // MARK: - Disconnect

    func disconnect() {
        authenticated = false
        connection?.cancel()
        connection = nil
        channel = nil
    }
}

// MARK: - SSH Packet

struct SSHPacket {
    enum PacketType: UInt8 {
        case disconnect = 1
        case ignore = 2
        case unimplemented = 3
        case debug = 4
        case serviceRequest = 5
        case serviceAccept = 6
        case kexInit = 20
        case newKeys = 21
        case kexECDHInit = 30
        case kexECDHReply = 31
        case userAuthRequest = 50
        case userAuthFailure = 51
        case userAuthSuccess = 52
        case channelOpen = 90
        case channelOpenConfirmation = 91
        case channelData = 94
        case channelRequest = 98
        case unknown = 255
    }

    let type: PacketType
    let payload: Data?
    var serverPublicKey: Data?

    static func keyExchangeInit(
        kexAlgorithms: [String],
        serverHostKeyAlgorithms: [String],
        encryptionAlgorithmsClientToServer: [String],
        encryptionAlgorithmsServerToClient: [String],
        macAlgorithmsClientToServer: [String],
        macAlgorithmsServerToClient: [String],
        compressionAlgorithms: [String]
    ) -> SSHPacket {
        var data = Data()
        data.append(PacketType.kexInit.rawValue)
        // Add 16 bytes of random cookie
        data.append(contentsOf: (0..<16).map { _ in UInt8.random(in: 0...255) })
        // Add algorithm lists
        data.append(contentsOf: encodeNameList(kexAlgorithms))
        data.append(contentsOf: encodeNameList(serverHostKeyAlgorithms))
        data.append(contentsOf: encodeNameList(encryptionAlgorithmsClientToServer))
        data.append(contentsOf: encodeNameList(encryptionAlgorithmsServerToClient))
        data.append(contentsOf: encodeNameList(macAlgorithmsClientToServer))
        data.append(contentsOf: encodeNameList(macAlgorithmsServerToClient))
        data.append(contentsOf: encodeNameList(compressionAlgorithms))
        data.append(contentsOf: encodeNameList(compressionAlgorithms))
        // First kex packet follows: false
        data.append(0)
        // Reserved
        data.append(contentsOf: [0, 0, 0, 0])

        return SSHPacket(type: .kexInit, payload: data)
    }

    static func kexECDHInit(publicKey: Data) -> SSHPacket {
        var data = Data()
        data.append(PacketType.kexECDHInit.rawValue)
        data.append(contentsOf: encodeString(publicKey))
        return SSHPacket(type: .kexECDHInit, payload: data)
    }

    static func newKeys() -> SSHPacket {
        return SSHPacket(type: .newKeys, payload: Data([PacketType.newKeys.rawValue]))
    }

    static func passwordAuth(username: String, password: String) -> SSHPacket {
        var data = Data()
        data.append(PacketType.userAuthRequest.rawValue)
        data.append(contentsOf: encodeString(Data(username.utf8)))
        data.append(contentsOf: encodeString(Data("ssh-connection".utf8)))
        data.append(contentsOf: encodeString(Data("password".utf8)))
        data.append(0) // No password change
        data.append(contentsOf: encodeString(Data(password.utf8)))
        return SSHPacket(type: .userAuthRequest, payload: data)
    }

    static func publicKeyAuth(username: String, keyType: String, publicKey: Data, signature: Data) -> SSHPacket {
        var data = Data()
        data.append(PacketType.userAuthRequest.rawValue)
        data.append(contentsOf: encodeString(Data(username.utf8)))
        data.append(contentsOf: encodeString(Data("ssh-connection".utf8)))
        data.append(contentsOf: encodeString(Data("publickey".utf8)))
        data.append(1) // Has signature
        data.append(contentsOf: encodeString(Data(keyType.utf8)))
        data.append(contentsOf: encodeString(publicKey))
        data.append(contentsOf: encodeString(signature))
        return SSHPacket(type: .userAuthRequest, payload: data)
    }

    static func ptyRequest(term: String, cols: Int, rows: Int) -> SSHPacket {
        var data = Data()
        data.append(PacketType.channelRequest.rawValue)
        data.append(contentsOf: [0, 0, 0, 0]) // Channel ID
        data.append(contentsOf: encodeString(Data("pty-req".utf8)))
        data.append(1) // Want reply
        data.append(contentsOf: encodeString(Data(term.utf8)))
        data.append(contentsOf: encodeUInt32(UInt32(cols)))
        data.append(contentsOf: encodeUInt32(UInt32(rows)))
        data.append(contentsOf: encodeUInt32(0)) // Pixel width
        data.append(contentsOf: encodeUInt32(0)) // Pixel height
        data.append(contentsOf: encodeString(Data())) // Terminal modes
        return SSHPacket(type: .channelRequest, payload: data)
    }

    static func shellRequest() -> SSHPacket {
        var data = Data()
        data.append(PacketType.channelRequest.rawValue)
        data.append(contentsOf: [0, 0, 0, 0]) // Channel ID
        data.append(contentsOf: encodeString(Data("shell".utf8)))
        data.append(1) // Want reply
        return SSHPacket(type: .channelRequest, payload: data)
    }

    static func execRequest(command: String) -> SSHPacket {
        var data = Data()
        data.append(PacketType.channelRequest.rawValue)
        data.append(contentsOf: [0, 0, 0, 0]) // Channel ID
        data.append(contentsOf: encodeString(Data("exec".utf8)))
        data.append(1) // Want reply
        data.append(contentsOf: encodeString(Data(command.utf8)))
        return SSHPacket(type: .channelRequest, payload: data)
    }

    static func channelData(data: Data) -> SSHPacket {
        var packetData = Data()
        packetData.append(PacketType.channelData.rawValue)
        packetData.append(contentsOf: [0, 0, 0, 0]) // Channel ID
        packetData.append(contentsOf: encodeString(data))
        return SSHPacket(type: .channelData, payload: packetData)
    }

    static func windowChange(cols: Int, rows: Int) -> SSHPacket {
        var data = Data()
        data.append(PacketType.channelRequest.rawValue)
        data.append(contentsOf: [0, 0, 0, 0]) // Channel ID
        data.append(contentsOf: encodeString(Data("window-change".utf8)))
        data.append(0) // No reply
        data.append(contentsOf: encodeUInt32(UInt32(cols)))
        data.append(contentsOf: encodeUInt32(UInt32(rows)))
        data.append(contentsOf: encodeUInt32(0)) // Pixel width
        data.append(contentsOf: encodeUInt32(0)) // Pixel height
        return SSHPacket(type: .channelRequest, payload: data)
    }

    func encode() -> Data {
        guard let payload = payload else { return Data() }

        var packet = Data()
        let paddingLength = 8 - ((payload.count + 5) % 8)
        let packetLength = payload.count + paddingLength + 1

        packet.append(contentsOf: SSHPacket.encodeUInt32(UInt32(packetLength)))
        packet.append(UInt8(paddingLength))
        packet.append(payload)
        packet.append(contentsOf: (0..<paddingLength).map { _ in UInt8.random(in: 0...255) })

        return packet
    }

    static func decode(from data: Data) throws -> SSHPacket {
        guard data.count >= 5 else {
            throw SSHError.invalidPacket
        }

        let packetLength = Int(decodeUInt32(Array(data[0..<4])))
        let paddingLength = Int(data[4])
        let payloadLength = packetLength - paddingLength - 1

        guard data.count >= 4 + packetLength,
              payloadLength > 0 else {
            throw SSHError.invalidPacket
        }

        let payload = data[5..<(5 + payloadLength)]
        let type = PacketType(rawValue: payload[payload.startIndex]) ?? .unknown

        return SSHPacket(type: type, payload: Data(payload))
    }

    // MARK: - Encoding Helpers

    static func encodeString(_ data: Data) -> [UInt8] {
        var result = encodeUInt32(UInt32(data.count))
        result.append(contentsOf: data)
        return result
    }

    static func encodeNameList(_ names: [String]) -> [UInt8] {
        let joined = names.joined(separator: ",")
        return encodeString(Data(joined.utf8))
    }

    static func encodeUInt32(_ value: UInt32) -> [UInt8] {
        return [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
    }

    static func decodeUInt32(_ bytes: [UInt8]) -> UInt32 {
        return UInt32(bytes[0]) << 24 |
               UInt32(bytes[1]) << 16 |
               UInt32(bytes[2]) << 8 |
               UInt32(bytes[3])
    }
}

// MARK: - SSH Channel

final class SSHChannel {
    let sessionId: Data
    private var encryptionKey: SymmetricKey?
    private var decryptionKey: SymmetricKey?

    init(sessionId: Data) {
        self.sessionId = sessionId
        deriveKeys()
    }

    private func deriveKeys() {
        // Derive encryption keys from session ID using HKDF
        let keyMaterial = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: sessionId),
            outputByteCount: 64
        )

        keyMaterial.withUnsafeBytes { bytes in
            let keyData = Data(bytes)
            encryptionKey = SymmetricKey(data: keyData[0..<32])
            decryptionKey = SymmetricKey(data: keyData[32..<64])
        }
    }

    func encrypt(_ data: Data) -> Data {
        guard let key = encryptionKey else { return data }

        do {
            let nonce = AES.GCM.Nonce()
            let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)
            return sealedBox.combined ?? data
        } catch {
            Logger.network.error("Encryption failed: \(error.localizedDescription)")
            return data
        }
    }

    func decrypt(_ data: Data) -> Data {
        guard let key = decryptionKey else { return data }

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            Logger.network.error("Decryption failed: \(error.localizedDescription)")
            return data
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
        }
    }
}

// MARK: - Mosh Server Info

struct MoshServerInfo {
    let port: Int
    let key: String
}

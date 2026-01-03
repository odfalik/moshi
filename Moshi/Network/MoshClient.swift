import Foundation
import Network
import CryptoKit

protocol MoshClientDelegate: AnyObject {
    func moshDidReceiveOutput(_ output: String)
    func moshDidDisconnect(error: Error?)
    func moshDidReconnect()
}

final class MoshClient: @unchecked Sendable {
    private let hostname: String
    private let port: Int
    private let sessionKey: String

    private var connection: NWConnection?
    private var cryptoState: MoshCryptoState?
    private let queue = DispatchQueue(label: "com.moshi.mosh", qos: .userInteractive)

    private var sequenceNumber: UInt64 = 0
    private var lastReceivedSequence: UInt64 = 0
    private var connected = false
    private var lastServerTimestamp: TimeInterval = 0

    private var cols: Int = 80
    private var rows: Int = 24

    weak var delegate: MoshClientDelegate?

    // Mosh protocol constants
    private let moshProtocolVersion: UInt16 = 1
    private let fragmentSize = 1400

    init(hostname: String, port: Int, key: String) {
        self.hostname = hostname
        self.port = port
        self.sessionKey = key
    }

    // MARK: - Connection

    func connect() async throws {
        // Initialize crypto with session key
        cryptoState = try MoshCryptoState(key: sessionKey)

        // Create UDP connection
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(hostname),
            port: NWEndpoint.Port(integerLiteral: UInt16(port))
        )

        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true
        parameters.allowFastOpen = true

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
            connected = true
            startReceiving()
            sendInitialState()
            continuation?.resume()

        case .failed(let error):
            connected = false
            delegate?.moshDidDisconnect(error: error)
            continuation?.resume(throwing: error)

        case .cancelled:
            connected = false
            delegate?.moshDidDisconnect(error: nil)

        case .waiting:
            // Network path changed, mosh handles this gracefully
            Logger.network.info("Mosh connection waiting for network path")

        default:
            break
        }
    }

    // MARK: - Mosh Protocol

    private func sendInitialState() {
        // Send initial terminal size
        var state = MoshClientState()
        state.terminalCols = UInt16(cols)
        state.terminalRows = UInt16(rows)

        sendState(state)
    }

    private func sendState(_ state: MoshClientState) {
        sequenceNumber += 1

        var data = Data()

        // Mosh packet header
        data.append(contentsOf: withUnsafeBytes(of: moshProtocolVersion.bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: sequenceNumber.bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: lastReceivedSequence.bigEndian) { Array($0) })

        // Encode client state
        let stateData = state.encode()
        data.append(stateData)

        // Encrypt and send
        if let encrypted = cryptoState?.encrypt(data, sequence: sequenceNumber) {
            sendDatagram(encrypted)
        }
    }

    func send(_ text: String) {
        guard connected else { return }

        var state = MoshClientState()
        state.input = text
        state.terminalCols = UInt16(cols)
        state.terminalRows = UInt16(rows)

        sendState(state)
    }

    func resize(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows

        var state = MoshClientState()
        state.terminalCols = UInt16(cols)
        state.terminalRows = UInt16(rows)
        state.resizeEvent = true

        sendState(state)
    }

    // MARK: - Receiving

    private func startReceiving() {
        receiveNextDatagram()
    }

    private func receiveNextDatagram() {
        connection?.receiveMessage { [weak self] data, _, _, error in
            guard let self = self else { return }

            if let error = error {
                if self.connected {
                    Logger.network.error("Mosh receive error: \(error.localizedDescription)")
                }
                return
            }

            if let data = data {
                self.handleDatagram(data)
            }

            if self.connected {
                self.receiveNextDatagram()
            }
        }
    }

    private func handleDatagram(_ data: Data) {
        // Decrypt
        guard let decrypted = cryptoState?.decrypt(data) else {
            Logger.network.warning("Failed to decrypt mosh packet")
            return
        }

        // Parse header
        guard decrypted.count >= 18 else { return }

        let version = decrypted.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt16.self).bigEndian }
        let serverSequence = decrypted.withUnsafeBytes { $0.load(fromByteOffset: 2, as: UInt64.self).bigEndian }
        let ackSequence = decrypted.withUnsafeBytes { $0.load(fromByteOffset: 10, as: UInt64.self).bigEndian }

        // Validate
        guard version == moshProtocolVersion else {
            Logger.network.warning("Mosh protocol version mismatch")
            return
        }

        // Check for replay/out-of-order
        if serverSequence <= lastReceivedSequence {
            return
        }
        lastReceivedSequence = serverSequence

        // Parse server state
        let stateData = decrypted.dropFirst(18)
        if let serverState = MoshServerState.decode(from: Data(stateData)) {
            processServerState(serverState)
        }

        // Update server timestamp for latency estimation
        lastServerTimestamp = Date().timeIntervalSince1970
    }

    private func processServerState(_ state: MoshServerState) {
        // Handle terminal output
        if !state.terminalOutput.isEmpty {
            delegate?.moshDidReceiveOutput(state.terminalOutput)
        }

        // Handle reconnection notification
        if state.reconnected {
            delegate?.moshDidReconnect()
        }
    }

    // MARK: - Low-level I/O

    private func sendDatagram(_ data: Data) {
        connection?.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                Logger.network.error("Mosh send error: \(error.localizedDescription)")
            }
        })
    }

    // MARK: - Disconnect

    func disconnect() {
        connected = false
        connection?.cancel()
        connection = nil
    }
}

// MARK: - Mosh Crypto State

final class MoshCryptoState {
    private let encryptionKey: SymmetricKey
    private let decryptionKey: SymmetricKey

    init(key: String) throws {
        // Mosh key is base64 encoded
        guard let keyData = Data(base64Encoded: key),
              keyData.count >= 16 else {
            throw MoshError.invalidKey
        }

        // Derive separate keys for encryption and decryption
        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: keyData),
            info: Data("moshi-client".utf8),
            outputByteCount: 64
        )

        derivedKey.withUnsafeBytes { bytes in
            let keyData = Data(bytes)
            encryptionKey = SymmetricKey(data: keyData[0..<32])
            decryptionKey = SymmetricKey(data: keyData[32..<64])
        }
    }

    func encrypt(_ data: Data, sequence: UInt64) -> Data? {
        do {
            // Use sequence number as nonce
            var nonceData = Data(repeating: 0, count: 12)
            nonceData.replaceSubrange(4..<12, with: withUnsafeBytes(of: sequence.bigEndian) { Data($0) })
            let nonce = try AES.GCM.Nonce(data: nonceData)

            let sealedBox = try AES.GCM.seal(data, using: encryptionKey, nonce: nonce)
            return sealedBox.combined
        } catch {
            Logger.network.error("Mosh encryption error: \(error.localizedDescription)")
            return nil
        }
    }

    func decrypt(_ data: Data) -> Data? {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: decryptionKey)
        } catch {
            Logger.network.error("Mosh decryption error: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - Mosh State Structures

struct MoshClientState {
    var input: String = ""
    var terminalCols: UInt16 = 80
    var terminalRows: UInt16 = 24
    var resizeEvent: Bool = false

    func encode() -> Data {
        var data = Data()

        // Terminal size
        data.append(contentsOf: withUnsafeBytes(of: terminalCols.bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: terminalRows.bigEndian) { Array($0) })

        // Flags
        var flags: UInt8 = 0
        if resizeEvent { flags |= 0x01 }
        data.append(flags)

        // Input (length-prefixed UTF-8)
        let inputData = Data(input.utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt16(inputData.count).bigEndian) { Array($0) })
        data.append(inputData)

        return data
    }
}

struct MoshServerState {
    var terminalOutput: String = ""
    var cursorCol: Int = 0
    var cursorRow: Int = 0
    var reconnected: Bool = false

    static func decode(from data: Data) -> MoshServerState? {
        guard data.count >= 5 else { return nil }

        var state = MoshServerState()
        var offset = 0

        // Read flags
        let flags = data[offset]
        state.reconnected = (flags & 0x01) != 0
        offset += 1

        // Read cursor position
        state.cursorCol = Int(data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt16.self).bigEndian })
        offset += 2
        state.cursorRow = Int(data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt16.self).bigEndian })
        offset += 2

        // Read output length and data
        if data.count > offset + 2 {
            let outputLength = Int(data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt16.self).bigEndian })
            offset += 2

            if data.count >= offset + outputLength {
                let outputData = data[offset..<(offset + outputLength)]
                state.terminalOutput = String(data: outputData, encoding: .utf8) ?? ""
            }
        }

        return state
    }
}

// MARK: - Errors

enum MoshError: LocalizedError {
    case invalidKey
    case connectionFailed
    case protocolError

    var errorDescription: String? {
        switch self {
        case .invalidKey:
            return "Invalid mosh session key"
        case .connectionFailed:
            return "Failed to connect to mosh server"
        case .protocolError:
            return "Mosh protocol error"
        }
    }
}

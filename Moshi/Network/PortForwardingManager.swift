import Foundation
import Network

final class PortForwardingManager: ObservableObject {
    @Published private(set) var activeForwards: [PortForward] = []

    private var listeners: [UUID: NWListener] = [:]
    private var connections: [UUID: [NWConnection]] = [:]
    private let queue = DispatchQueue(label: "com.moshi.portforward")

    struct PortForward: Identifiable {
        let id: UUID
        let type: ForwardType
        let localPort: Int
        let remoteHost: String
        let remotePort: Int
        let session: Session
        var state: ForwardState
        var connectionCount: Int

        enum ForwardType {
            case local   // -L: local port forwards to remote
            case remote  // -R: remote port forwards to local
            case dynamic // -D: SOCKS proxy
        }

        enum ForwardState {
            case starting
            case active
            case error(String)
            case stopped
        }
    }

    // MARK: - Local Port Forwarding

    func createLocalForward(
        session: Session,
        localPort: Int,
        remoteHost: String,
        remotePort: Int
    ) async throws -> PortForward {
        let id = UUID()

        var forward = PortForward(
            id: id,
            type: .local,
            localPort: localPort,
            remoteHost: remoteHost,
            remotePort: remotePort,
            session: session,
            state: .starting,
            connectionCount: 0
        )

        // Create local listener
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        guard let port = NWEndpoint.Port(rawValue: UInt16(localPort)) else {
            throw PortForwardError.invalidPort
        }

        let listener = try NWListener(using: parameters, on: port)

        listener.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                self?.handleListenerState(id: id, state: state)
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewLocalConnection(forwardId: id, connection: connection)
        }

        listeners[id] = listener
        connections[id] = []

        listener.start(queue: queue)

        forward.state = .active
        await MainActor.run {
            activeForwards.append(forward)
        }

        Logger.network.info("Local port forward created: localhost:\(localPort) -> \(remoteHost):\(remotePort)")

        return forward
    }

    private func handleListenerState(id: UUID, state: NWListener.State) {
        guard let index = activeForwards.firstIndex(where: { $0.id == id }) else { return }

        switch state {
        case .ready:
            activeForwards[index].state = .active

        case .failed(let error):
            activeForwards[index].state = .error(error.localizedDescription)
            stopForward(id: id)

        case .cancelled:
            activeForwards[index].state = .stopped

        default:
            break
        }
    }

    private func handleNewLocalConnection(forwardId: UUID, connection: NWConnection) {
        guard let forward = activeForwards.first(where: { $0.id == forwardId }) else {
            connection.cancel()
            return
        }

        // Accept the connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                // Establish remote connection through SSH
                self?.bridgeToRemote(
                    localConnection: connection,
                    forward: forward
                )

            case .failed, .cancelled:
                connection.cancel()

            default:
                break
            }
        }

        connection.start(queue: queue)
        connections[forwardId]?.append(connection)

        // Update connection count
        if let index = activeForwards.firstIndex(where: { $0.id == forwardId }) {
            DispatchQueue.main.async {
                self.activeForwards[index].connectionCount += 1
            }
        }
    }

    private func bridgeToRemote(localConnection: NWConnection, forward: PortForward) {
        // Request port forward channel through SSH session
        // This would integrate with SSHConnection's channel multiplexing

        // For now, we'll relay data through the session's command channel
        // In a full implementation, this would use SSH's direct-tcpip channel

        startRelaying(
            local: localConnection,
            remoteHost: forward.remoteHost,
            remotePort: forward.remotePort,
            session: forward.session
        )
    }

    private func startRelaying(
        local: NWConnection,
        remoteHost: String,
        remotePort: Int,
        session: Session
    ) {
        // Read from local, send to remote
        func readLocal() {
            local.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let data = data, !data.isEmpty {
                    // In a full implementation, send through SSH channel
                    // session.sendData(data, toChannel: channelId)
                }

                if !isComplete && error == nil {
                    readLocal()
                }
            }
        }

        readLocal()
    }

    // MARK: - Dynamic Port Forwarding (SOCKS5)

    func createDynamicForward(session: Session, localPort: Int) async throws -> PortForward {
        let id = UUID()

        var forward = PortForward(
            id: id,
            type: .dynamic,
            localPort: localPort,
            remoteHost: "",
            remotePort: 0,
            session: session,
            state: .starting,
            connectionCount: 0
        )

        // Create SOCKS5 proxy listener
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        guard let port = NWEndpoint.Port(rawValue: UInt16(localPort)) else {
            throw PortForwardError.invalidPort
        }

        let listener = try NWListener(using: parameters, on: port)

        listener.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                self?.handleListenerState(id: id, state: state)
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleSOCKS5Connection(forwardId: id, connection: connection, session: session)
        }

        listeners[id] = listener
        connections[id] = []

        listener.start(queue: queue)

        forward.state = .active
        await MainActor.run {
            activeForwards.append(forward)
        }

        Logger.network.info("SOCKS5 proxy created on port \(localPort)")

        return forward
    }

    private func handleSOCKS5Connection(forwardId: UUID, connection: NWConnection, session: Session) {
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                self.handleSOCKS5Handshake(connection: connection, session: session)

            case .failed, .cancelled:
                connection.cancel()

            default:
                break
            }
        }

        connection.start(queue: queue)
        connections[forwardId]?.append(connection)
    }

    private func handleSOCKS5Handshake(connection: NWConnection, session: Session) {
        // SOCKS5 handshake
        connection.receive(minimumIncompleteLength: 2, maximumLength: 257) { [weak self] data, _, _, error in
            guard let data = data, data.count >= 2 else {
                connection.cancel()
                return
            }

            // Version check
            guard data[0] == 0x05 else {
                connection.cancel()
                return
            }

            // Send auth method response (no auth)
            let response = Data([0x05, 0x00])
            connection.send(content: response, completion: .contentProcessed { _ in
                self?.handleSOCKS5Request(connection: connection, session: session)
            })
        }
    }

    private func handleSOCKS5Request(connection: NWConnection, session: Session) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 262) { data, _, _, error in
            guard let data = data, data.count >= 4 else {
                connection.cancel()
                return
            }

            // Parse SOCKS5 request
            guard data[0] == 0x05, // Version
                  data[1] == 0x01  // CONNECT command
            else {
                // Send failure response
                let response = Data([0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0])
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }

            // Parse address
            let addressType = data[3]
            var targetHost: String = ""
            var targetPort: Int = 0
            var offset = 4

            switch addressType {
            case 0x01: // IPv4
                if data.count >= offset + 6 {
                    targetHost = "\(data[offset]).\(data[offset+1]).\(data[offset+2]).\(data[offset+3])"
                    offset += 4
                    targetPort = Int(data[offset]) << 8 | Int(data[offset+1])
                }

            case 0x03: // Domain name
                if data.count > offset {
                    let domainLength = Int(data[offset])
                    offset += 1
                    if data.count >= offset + domainLength + 2 {
                        targetHost = String(data: data[offset..<(offset+domainLength)], encoding: .utf8) ?? ""
                        offset += domainLength
                        targetPort = Int(data[offset]) << 8 | Int(data[offset+1])
                    }
                }

            case 0x04: // IPv6
                if data.count >= offset + 18 {
                    // Parse IPv6 address
                    var parts: [String] = []
                    for i in 0..<8 {
                        let part = Int(data[offset + i*2]) << 8 | Int(data[offset + i*2 + 1])
                        parts.append(String(format: "%x", part))
                    }
                    targetHost = parts.joined(separator: ":")
                    offset += 16
                    targetPort = Int(data[offset]) << 8 | Int(data[offset+1])
                }

            default:
                break
            }

            guard !targetHost.isEmpty && targetPort > 0 else {
                let response = Data([0x05, 0x01, 0x00, 0x01, 0, 0, 0, 0, 0, 0])
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }

            // Send success response
            var response = Data([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0])
            response.append(contentsOf: [UInt8(targetPort >> 8), UInt8(targetPort & 0xFF)])
            connection.send(content: response, completion: .contentProcessed { _ in
                // Bridge connection through SSH
                self.startRelaying(
                    local: connection,
                    remoteHost: targetHost,
                    remotePort: targetPort,
                    session: session
                )
            })
        }
    }

    // MARK: - Management

    func stopForward(id: UUID) {
        listeners[id]?.cancel()
        listeners.removeValue(forKey: id)

        connections[id]?.forEach { $0.cancel() }
        connections.removeValue(forKey: id)

        if let index = activeForwards.firstIndex(where: { $0.id == id }) {
            DispatchQueue.main.async {
                self.activeForwards.remove(at: index)
            }
        }
    }

    func stopAllForwards() {
        for id in listeners.keys {
            stopForward(id: id)
        }
    }

    func stopForwards(for session: Session) {
        let sessionForwards = activeForwards.filter { $0.session.id == session.id }
        for forward in sessionForwards {
            stopForward(id: forward.id)
        }
    }
}

// MARK: - Errors

enum PortForwardError: LocalizedError {
    case invalidPort
    case portInUse
    case connectionFailed
    case sessionNotConnected

    var errorDescription: String? {
        switch self {
        case .invalidPort:
            return "Invalid port number"
        case .portInUse:
            return "Port is already in use"
        case .connectionFailed:
            return "Failed to establish connection"
        case .sessionNotConnected:
            return "SSH session is not connected"
        }
    }
}

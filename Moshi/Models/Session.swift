import Foundation
import SwiftUI
import Combine

final class Session: Identifiable, ObservableObject {
    let id: UUID
    let host: Host
    let createdAt: Date

    @Published var state: ConnectionState = .disconnected
    @Published var tmuxSession: TmuxSession?
    @Published var terminalOutput: String = ""
    @Published var cursorPosition: CursorPosition = CursorPosition()
    @Published var scrollbackLines: [TerminalLine] = []
    @Published var lastActivity: Date = Date()

    private var connection: SSHConnection?
    private var moshClient: MoshClient?
    private var cancellables = Set<AnyCancellable>()

    weak var delegate: SessionDelegate?

    init(host: Host) {
        self.id = UUID()
        self.host = host
        self.createdAt = Date()
    }

    // MARK: - Connection Management

    func connect() async throws {
        await MainActor.run {
            state = .connecting
        }

        do {
            if host.useMosh {
                try await connectWithMosh()
            } else {
                try await connectWithSSH()
            }

            await MainActor.run {
                state = .connected
                lastActivity = Date()
            }

            // Auto-attach to tmux if enabled (don't fail connection if tmux fails)
            if host.autoTmux {
                do {
                    try await attachOrCreateTmuxSession()
                } catch {
                    // Log tmux error but keep connection alive
                    Logger.session.warning("Tmux auto-attach failed: \(error.localizedDescription)")
                    // Connection is still usable without tmux
                }
            }

        } catch {
            await MainActor.run {
                state = .error(error.localizedDescription)
            }
            throw error
        }
    }

    private func connectWithSSH() async throws {
        connection = SSHConnection(host: host)
        connection?.delegate = self
        try await connection?.connect()
    }

    private func connectWithMosh() async throws {
        // First establish SSH to get mosh-server info
        let sshConnection = SSHConnection(host: host)
        try await sshConnection.connect()  // Must connect first!
        let moshInfo = try await sshConnection.startMoshServer(portRange: host.moshPorts)

        // Then connect with mosh client
        moshClient = MoshClient(
            hostname: host.hostname,
            port: moshInfo.port,
            key: moshInfo.key
        )
        moshClient?.delegate = self
        try await moshClient?.connect()
    }

    private func attachOrCreateTmuxSession() async throws {
        let tmuxIntegration = TmuxIntegration(session: self)
        let sessions = try await tmuxIntegration.listSessions()

        let targetSession = host.effectiveTmuxSessionName

        if let existing = sessions.first(where: { $0.name == targetSession }) {
            try await tmuxIntegration.attachSession(existing)
            await MainActor.run {
                tmuxSession = existing
            }
        } else {
            let newSession = try await tmuxIntegration.createSession(name: targetSession)
            await MainActor.run {
                tmuxSession = newSession
            }
        }
    }

    func disconnect() {
        state = .disconnecting

        Task {
            // Detach from tmux first (keeps session alive on server)
            if tmuxSession != nil {
                sendCommand(TmuxIntegration.detachCommand)
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }

            connection?.disconnect()
            moshClient?.disconnect()

            await MainActor.run {
                state = .disconnected
                connection = nil
                moshClient = nil
            }
        }
    }

    // MARK: - Terminal I/O

    func sendInput(_ text: String) {
        guard state == .connected else { return }

        if let moshClient = moshClient {
            moshClient.send(text)
        } else if let connection = connection {
            connection.send(text)
        }

        lastActivity = Date()
    }

    func sendCommand(_ command: String) {
        sendInput(command + "\n")
    }

    func sendSpecialKey(_ key: SpecialKey) {
        sendInput(key.sequence)
    }

    func resize(cols: Int, rows: Int) {
        connection?.resize(cols: cols, rows: rows)
        moshClient?.resize(cols: cols, rows: rows)
    }

    // MARK: - Tmux Operations

    func createTmuxWindow(name: String? = nil) async throws {
        guard let _ = tmuxSession else { return }
        let tmux = TmuxIntegration(session: self)
        try await tmux.createWindow(name: name)
    }

    func switchTmuxWindow(_ index: Int) {
        sendCommand("tmux select-window -t \(index)")
    }

    func splitTmuxPane(horizontal: Bool) {
        sendCommand("tmux split-window \(horizontal ? "-h" : "-v")")
    }
}

// MARK: - SSH Connection Delegate

extension Session: SSHConnectionDelegate {
    func connectionDidReceiveOutput(_ output: String) {
        Task { @MainActor in
            terminalOutput += output
            lastActivity = Date()
            delegate?.sessionDidReceiveOutput(self, output: output)
        }
    }

    func connectionDidDisconnect(error: Error?) {
        Task { @MainActor in
            if let error = error {
                state = .error(error.localizedDescription)
            } else {
                state = .disconnected
            }
        }
    }

    func connectionDidChangeState(_ newState: ConnectionState) {
        Task { @MainActor in
            state = newState
        }
    }

    func connectionShouldTrustNewHost(fingerprint: String) async -> Bool {
        // Ask delegate for user confirmation
        if let delegate = delegate {
            return await delegate.sessionShouldTrustNewHost(self, fingerprint: fingerprint)
        }
        // Default: auto-trust first connection (for backward compatibility)
        Logger.network.warning("Auto-trusting new host (no delegate): \(fingerprint)")
        return true
    }

    func connectionHostKeyChanged(newFingerprint: String, oldFingerprint: String) async -> Bool {
        // Ask delegate for user confirmation
        if let delegate = delegate {
            return await delegate.sessionHostKeyChanged(self, newFingerprint: newFingerprint, oldFingerprint: oldFingerprint)
        }
        // Default: reject key changes (security)
        Logger.network.error("Rejecting host key change (no delegate): \(oldFingerprint) -> \(newFingerprint)")
        return false
    }
}

// MARK: - Mosh Client Delegate

extension Session: MoshClientDelegate {
    func moshDidReceiveOutput(_ output: String) {
        Task { @MainActor in
            terminalOutput += output
            lastActivity = Date()
            delegate?.sessionDidReceiveOutput(self, output: output)
        }
    }

    func moshDidDisconnect(error: Error?) {
        Task { @MainActor in
            if let error = error {
                state = .error(error.localizedDescription)
            } else {
                state = .disconnected
            }
        }
    }

    func moshDidReconnect() {
        Task { @MainActor in
            state = .connected
        }
    }
}

// MARK: - Session Delegate

protocol SessionDelegate: AnyObject {
    func sessionDidReceiveOutput(_ session: Session, output: String)
    func sessionDidChangeState(_ session: Session, state: ConnectionState)
    func sessionDidUpdateTmux(_ session: Session)

    /// Called when connecting to a new host - return true to trust
    func sessionShouldTrustNewHost(_ session: Session, fingerprint: String) async -> Bool

    /// Called when host key changed - return true to trust (dangerous!)
    func sessionHostKeyChanged(_ session: Session, newFingerprint: String, oldFingerprint: String) async -> Bool
}

// MARK: - Supporting Types

struct CursorPosition {
    var row: Int = 0
    var col: Int = 0
}

struct TerminalLine: Identifiable {
    let id = UUID()
    var cells: [TerminalCell]
    var wrapped: Bool = false
}

struct TerminalCell {
    var character: Character = " "
    var foreground: TerminalColor = .default
    var background: TerminalColor = .default
    var attributes: CellAttributes = []
}

struct CellAttributes: OptionSet {
    let rawValue: UInt8

    static let bold = CellAttributes(rawValue: 1 << 0)
    static let italic = CellAttributes(rawValue: 1 << 1)
    static let underline = CellAttributes(rawValue: 1 << 2)
    static let strikethrough = CellAttributes(rawValue: 1 << 3)
    static let blink = CellAttributes(rawValue: 1 << 4)
    static let inverse = CellAttributes(rawValue: 1 << 5)
}

enum TerminalColor {
    case `default`
    case indexed(Int)
    case rgb(UInt8, UInt8, UInt8)
}

enum SpecialKey: String, CaseIterable {
    case escape = "ESC"
    case tab = "TAB"
    case ctrlC = "^C"
    case ctrlD = "^D"
    case ctrlZ = "^Z"
    case ctrlL = "^L"
    case up = "UP"
    case down = "DOWN"
    case left = "LEFT"
    case right = "RIGHT"
    case home = "HOME"
    case end = "END"
    case pageUp = "PGUP"
    case pageDown = "PGDN"
    case delete = "DEL"
    case insert = "INS"
    case f1 = "F1"
    case f2 = "F2"
    case f3 = "F3"
    case f4 = "F4"
    case f5 = "F5"
    case f6 = "F6"
    case f7 = "F7"
    case f8 = "F8"
    case f9 = "F9"
    case f10 = "F10"
    case f11 = "F11"
    case f12 = "F12"

    var sequence: String {
        switch self {
        case .escape: return "\u{1B}"
        case .tab: return "\t"
        case .ctrlC: return "\u{03}"
        case .ctrlD: return "\u{04}"
        case .ctrlZ: return "\u{1A}"
        case .ctrlL: return "\u{0C}"
        case .up: return "\u{1B}[A"
        case .down: return "\u{1B}[B"
        case .right: return "\u{1B}[C"
        case .left: return "\u{1B}[D"
        case .home: return "\u{1B}[H"
        case .end: return "\u{1B}[F"
        case .pageUp: return "\u{1B}[5~"
        case .pageDown: return "\u{1B}[6~"
        case .delete: return "\u{1B}[3~"
        case .insert: return "\u{1B}[2~"
        case .f1: return "\u{1B}OP"
        case .f2: return "\u{1B}OQ"
        case .f3: return "\u{1B}OR"
        case .f4: return "\u{1B}OS"
        case .f5: return "\u{1B}[15~"
        case .f6: return "\u{1B}[17~"
        case .f7: return "\u{1B}[18~"
        case .f8: return "\u{1B}[19~"
        case .f9: return "\u{1B}[20~"
        case .f10: return "\u{1B}[21~"
        case .f11: return "\u{1B}[23~"
        case .f12: return "\u{1B}[24~"
        }
    }

    var displayName: String {
        rawValue
    }
}

// MARK: - Tmux Session

struct TmuxSession: Identifiable, Codable {
    let id: String
    var name: String
    var windows: [TmuxWindow]
    var activeWindowIndex: Int
    var attached: Bool
    var createdAt: Date?

    init(id: String, name: String, windows: [TmuxWindow] = [], activeWindowIndex: Int = 0, attached: Bool = false, createdAt: Date? = nil) {
        self.id = id
        self.name = name
        self.windows = windows
        self.activeWindowIndex = activeWindowIndex
        self.attached = attached
        self.createdAt = createdAt
    }
}

struct TmuxWindow: Identifiable, Codable {
    let id: String
    var index: Int
    var name: String
    var panes: [TmuxPane]
    var activePaneId: String?
    var isActive: Bool

    init(id: String, index: Int, name: String, panes: [TmuxPane] = [], activePaneId: String? = nil, isActive: Bool = false) {
        self.id = id
        self.index = index
        self.name = name
        self.panes = panes
        self.activePaneId = activePaneId
        self.isActive = isActive
    }
}

struct TmuxPane: Identifiable, Codable {
    let id: String
    var index: Int
    var width: Int
    var height: Int
    var isActive: Bool
    var currentCommand: String?

    init(id: String, index: Int, width: Int = 80, height: Int = 24, isActive: Bool = false, currentCommand: String? = nil) {
        self.id = id
        self.index = index
        self.width = width
        self.height = height
        self.isActive = isActive
        self.currentCommand = currentCommand
    }
}

import Foundation
import SwiftUI
import Combine

final class Session: Identifiable, ObservableObject {
    let id: UUID
    let host: Host
    let createdAt: Date

    /// User-facing name for this session (e.g., "Claude - Moshi Project")
    @Published var name: String

    /// Unique tmux session name for this Session instance
    /// Format: moshi-<short-uuid> (e.g., "moshi-a1b2c3d4")
    let tmuxSessionName: String

    @Published var state: ConnectionState = .disconnected
    @Published var tmuxSession: TmuxSession?
    @Published var tmuxStatus: TmuxStatus = .unknown
    @Published var terminalOutput: String = ""
    /// Incremented when terminalOutput is replaced (not appended) - signals view to reprocess
    @Published var outputRevision: Int = 0
    @Published var cursorPosition: CursorPosition = CursorPosition()
    @Published var scrollbackLines: [TerminalLine] = []
    @Published var lastActivity: Date = Date()

    private var connection: SSHConnection?
    private var moshClient: MoshClient?
    private var cancellables = Set<AnyCancellable>()
    private var tmuxIntegration: TmuxIntegration?

    // Output batching for performance
    private var outputBuffer = ""
    private var outputFlushTimer: Timer?
    private let outputFlushInterval: TimeInterval = 0.016  // ~60fps
    private let outputBufferLock = NSLock()

    weak var delegate: SessionDelegate?

    init(host: Host, name: String? = nil, existingTmuxSessionName: String? = nil, existingId: UUID? = nil) {
        self.id = existingId ?? UUID()
        self.host = host
        self.createdAt = Date()
        // User-facing name defaults to host display name
        self.name = name ?? host.displayName
        // Use existing tmux session name (for reconnection) or generate unique name
        self.tmuxSessionName = existingTmuxSessionName ?? "moshi-\(self.id.uuidString.prefix(8).lowercased())"
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
                    await MainActor.run {
                        tmuxStatus = .attached
                    }
                } catch let error as TmuxError where error == .notInstalled {
                    // Tmux not installed - mark status but keep connection
                    await MainActor.run {
                        tmuxStatus = .notInstalled
                    }
                    Logger.session.info("Tmux not installed on server, continuing without session persistence")
                } catch {
                    // Other tmux error - mark as failed but keep connection
                    await MainActor.run {
                        tmuxStatus = .failed(error.localizedDescription)
                    }
                    Logger.session.warning("Tmux auto-attach failed: \(error.localizedDescription)")
                }
            } else {
                await MainActor.run {
                    tmuxStatus = .disabled
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
        let integration = TmuxIntegration(session: self)
        self.tmuxIntegration = integration

        Logger.session.info("Looking for tmux session: \(tmuxSessionName)")
        let sessions = try await integration.listSessions()
        Logger.session.info("Found \(sessions.count) tmux sessions: \(sessions.map { $0.name })")

        // Look for our specific tmux session (unique to this Session instance)
        if let existing = sessions.first(where: { $0.name == tmuxSessionName }) {
            // Found our session - capture scrollback before attaching
            do {
                let scrollback = try await integration.capturePaneContent(sessionName: tmuxSessionName)
                await MainActor.run {
                    // Prepend scrollback to terminal output
                    if !scrollback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        terminalOutput = scrollback
                        outputRevision += 1  // Signal view to reprocess from start
                    }
                }
            } catch {
                Logger.session.warning("Failed to capture scrollback: \(error.localizedDescription)")
            }

            // Reattach to existing session
            try await integration.attachSession(existing)
            await MainActor.run {
                tmuxSession = existing
            }
            Logger.session.info("Reattached to existing tmux session: \(tmuxSessionName)")
        } else {
            // Our session doesn't exist (e.g., host rebooted) - create fresh
            let newSession = try await integration.createSession(name: tmuxSessionName)
            await MainActor.run {
                tmuxSession = newSession
                // Notify user that previous session was lost
                terminalOutput = "⚠️ Previous tmux session not found (host may have rebooted).\n   Started fresh session: \(tmuxSessionName)\n\n"
                outputRevision += 1  // Signal view to reprocess from start
            }
            Logger.session.info("Created new tmux session (previous not found): \(tmuxSessionName)")
        }
    }

    /// Disconnect from the session but keep the tmux session alive on server
    /// The session can be reconnected later to resume work
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

    /// Close the session completely, killing the tmux session on the server
    /// This is a permanent action - the session state will be lost
    func close() async {
        await MainActor.run {
            state = .disconnecting
        }

        // Kill the tmux session on the server (if connected and have tmux)
        if state == .connected || connection != nil, tmuxSession != nil {
            let integration = TmuxIntegration(session: self)
            do {
                try await integration.killSession(tmuxSession!)
            } catch {
                Logger.session.warning("Failed to kill tmux session: \(error.localizedDescription)")
            }
        }

        // Close the SSH connection
        connection?.disconnect()
        moshClient?.disconnect()

        await MainActor.run {
            state = .disconnected
            connection = nil
            moshClient = nil
            tmuxSession = nil
            tmuxStatus = .unknown
        }
    }

    /// Reconnect to the session, reattaching to the existing tmux session
    func reconnect() async throws {
        guard state == .disconnected else {
            throw SessionError.invalidState("Cannot reconnect: session is not disconnected")
        }

        // Don't clear terminalOutput - we'll restore scrollback from tmux
        try await connect()
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
        // Forward output to tmux integration for marker parsing
        tmuxIntegration?.processOutput(output)

        // Buffer output for batched updates (improves performance during fast output)
        outputBufferLock.lock()
        outputBuffer += output
        outputBufferLock.unlock()

        // Schedule flush if not already scheduled
        DispatchQueue.main.async { [weak self] in
            self?.scheduleOutputFlush()
        }
    }

    private func scheduleOutputFlush() {
        guard outputFlushTimer == nil else { return }

        outputFlushTimer = Timer.scheduledTimer(withTimeInterval: outputFlushInterval, repeats: false) { [weak self] _ in
            self?.flushOutputBuffer()
        }
    }

    private func flushOutputBuffer() {
        outputFlushTimer = nil

        outputBufferLock.lock()
        let bufferedOutput = outputBuffer
        outputBuffer = ""
        outputBufferLock.unlock()

        guard !bufferedOutput.isEmpty else { return }

        terminalOutput += bufferedOutput
        lastActivity = Date()
        delegate?.sessionDidReceiveOutput(self, output: bufferedOutput)
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
        // Forward output to tmux integration for marker parsing
        tmuxIntegration?.processOutput(output)

        // Buffer output for batched updates (same as SSH)
        outputBufferLock.lock()
        outputBuffer += output
        outputBufferLock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.scheduleOutputFlush()
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
    case enter = "ENTER"
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
        case .enter: return "\r"
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

// MARK: - Tmux Status

enum TmuxStatus: Equatable {
    case unknown
    case disabled
    case attached
    case notInstalled
    case failed(String)

    var isProtected: Bool {
        self == .attached
    }

    var icon: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .disabled: return "xmark.circle"
        case .attached: return "checkmark.shield"
        case .notInstalled: return "exclamationmark.triangle"
        case .failed: return "exclamationmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .unknown: return .secondary
        case .disabled: return .secondary
        case .attached: return .green
        case .notInstalled: return .orange
        case .failed: return .red
        }
    }

    var description: String {
        switch self {
        case .unknown: return "Checking tmux..."
        case .disabled: return "Session persistence disabled"
        case .attached: return "Session protected by tmux"
        case .notInstalled: return "Install tmux for session persistence"
        case .failed(let reason): return "Tmux error: \(reason)"
        }
    }
}

// MARK: - Session Error

enum SessionError: LocalizedError {
    case invalidState(String)
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidState(let message):
            return "Invalid session state: \(message)"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        }
    }
}

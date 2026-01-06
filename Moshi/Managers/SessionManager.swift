import Foundation
import Combine
import SwiftUI

@MainActor
final class SessionManager: ObservableObject {
    static let shared = SessionManager()

    @Published var activeSessions: [Session] = []
    @Published var currentSessionId: UUID?
    @Published var recentConnections: [Host] = []

    /// Set when a session should be navigated to (for auto-open behavior)
    @Published var pendingNavigationSessionId: UUID?

    private var cancellables = Set<AnyCancellable>()
    private let maxRecentConnections = 10

    var currentSession: Session? {
        activeSessions.first { $0.id == currentSessionId }
    }

    private init() {
        loadRecentConnections()
        // Note: restoreSessions() must be called after HostManager is ready
        // This is done in the app's onAppear or scene delegate
    }

    /// Call this after HostManager is initialized to restore persisted sessions
    func initialize(hostManager: HostManager) {
        restoreSessions(hostManager: hostManager)
    }

    // MARK: - Session Lifecycle

    func createSession(for host: Host, name: String? = nil) async throws -> Session {
        let session = Session(host: host, name: name)

        await MainActor.run {
            activeSessions.append(session)
            currentSessionId = session.id
            saveSessionState()  // Persist immediately
        }

        // Start Live Activity
        await LiveActivityManager.shared.startActivity(for: session)

        // Connect
        try await session.connect()

        // Update Live Activity with connected state
        await LiveActivityManager.shared.updateActivity(for: session)

        // Record in recent connections
        recordConnection(host)

        // Trigger navigation to the new session
        await MainActor.run {
            pendingNavigationSessionId = session.id
        }

        return session
    }

    /// Close the session completely (kills tmux session on server and removes from list)
    func closeSession(_ session: Session) {
        // End Live Activity
        LiveActivityManager.shared.endActivity(for: session)

        Task {
            await session.close()

            await MainActor.run {
                activeSessions.removeAll { $0.id == session.id }

                if currentSessionId == session.id {
                    currentSessionId = activeSessions.first?.id
                }

                saveSessionState()  // Persist the removal
            }
        }
    }

    /// Disconnect session but keep it in the list for potential reconnection
    func disconnectSession(_ session: Session) {
        session.disconnect()
        // Update Live Activity to show disconnected state
        LiveActivityManager.shared.updateActivity(for: session)
    }

    /// Reconnect a disconnected session
    func reconnectSession(_ session: Session) async throws {
        try await session.reconnect()
        // Update Live Activity
        await LiveActivityManager.shared.updateActivity(for: session)
    }

    func closeAllSessions() {
        // End all Live Activities
        LiveActivityManager.shared.endAllActivities()

        for session in activeSessions {
            session.disconnect()
        }
        activeSessions.removeAll()
        currentSessionId = nil
    }

    func switchToSession(_ session: Session) {
        guard activeSessions.contains(where: { $0.id == session.id }) else { return }
        currentSessionId = session.id
    }

    func switchToSession(at index: Int) {
        guard index >= 0 && index < activeSessions.count else { return }
        currentSessionId = activeSessions[index].id
    }

    // MARK: - Session Navigation

    func nextSession() {
        guard let currentId = currentSessionId,
              let currentIndex = activeSessions.firstIndex(where: { $0.id == currentId }) else {
            currentSessionId = activeSessions.first?.id
            return
        }

        let nextIndex = (currentIndex + 1) % activeSessions.count
        currentSessionId = activeSessions[nextIndex].id
    }

    func previousSession() {
        guard let currentId = currentSessionId,
              let currentIndex = activeSessions.firstIndex(where: { $0.id == currentId }) else {
            currentSessionId = activeSessions.first?.id
            return
        }

        let prevIndex = (currentIndex - 1 + activeSessions.count) % activeSessions.count
        currentSessionId = activeSessions[prevIndex].id
    }

    // MARK: - Quick Connect

    func quickConnect(to connectionString: String) async throws -> Session {
        // Parse connection string: user@host:port or user@host
        let host = parseConnectionString(connectionString)
        return try await createSession(for: host)
    }

    private func parseConnectionString(_ string: String) -> Host {
        var username = "root"
        var hostname = string
        var port = 22

        // Parse user@host:port format
        if let atIndex = string.lastIndex(of: "@") {
            username = String(string[..<atIndex])
            hostname = String(string[string.index(after: atIndex)...])
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
            authMethod: .password,
            useMosh: false,  // Mosh not implemented yet
            autoTmux: true
        )
    }

    // MARK: - Recent Connections

    private func recordConnection(_ host: Host) {
        // Remove existing entry for this host
        recentConnections.removeAll { $0.hostname == host.hostname && $0.username == host.username }

        // Add to front
        var updatedHost = host
        updatedHost.lastConnected = Date()
        recentConnections.insert(updatedHost, at: 0)

        // Trim to max size
        if recentConnections.count > maxRecentConnections {
            recentConnections.removeLast(recentConnections.count - maxRecentConnections)
        }

        saveRecentConnections()
    }

    private func loadRecentConnections() {
        if let data = UserDefaults.standard.data(forKey: "recentConnections"),
           let hosts = try? JSONDecoder().decode([Host].self, from: data) {
            recentConnections = hosts
        }
    }

    private func saveRecentConnections() {
        if let data = try? JSONEncoder().encode(recentConnections) {
            UserDefaults.standard.set(data, forKey: "recentConnections")
        }
    }

    // MARK: - Session State Monitoring

    func observeSessionStates() {
        for session in activeSessions {
            session.$state
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    self?.handleSessionStateChange(session, state: state)
                }
                .store(in: &cancellables)
        }
    }

    private func handleSessionStateChange(_ session: Session, state: ConnectionState) {
        switch state {
        case .error(let message):
            Logger.session.error("Session \(session.id) error: \(message)")
            // Could show notification or alert

        case .disconnected:
            // Keep disconnected sessions in the list - user can reconnect or close
            Logger.session.info("Session \(session.id) disconnected")

        default:
            break
        }
    }

    // MARK: - Session Persistence

    func saveSessionState() {
        let sessionStates = activeSessions.map { session -> SavedSessionState in
            SavedSessionState(
                id: session.id,
                hostId: session.host.id,
                name: session.name,
                tmuxSessionName: session.tmuxSessionName,
                createdAt: session.createdAt
            )
        }

        if let data = try? JSONEncoder().encode(sessionStates) {
            UserDefaults.standard.set(data, forKey: "savedSessions")
        }
        Logger.session.debug("Saved \(sessionStates.count) sessions to storage")
    }

    /// Restore sessions from storage as disconnected (doesn't auto-connect)
    func restoreSessions(hostManager: HostManager) {
        guard let data = UserDefaults.standard.data(forKey: "savedSessions"),
              let states = try? JSONDecoder().decode([SavedSessionState].self, from: data) else {
            return
        }

        for state in states {
            // Find the host for this session
            guard let host = hostManager.hosts.first(where: { $0.id == state.hostId }) else {
                Logger.session.warning("Cannot restore session '\(state.name)': host not found")
                continue
            }

            // Create session in disconnected state (don't connect yet)
            let session = Session(
                host: host,
                name: state.name,
                existingTmuxSessionName: state.tmuxSessionName,
                existingId: state.id
            )
            // Session starts in .disconnected state by default
            activeSessions.append(session)
            Logger.session.info("Restored session '\(state.name)' (disconnected)")
        }

        // Select first session if any
        if currentSessionId == nil, let first = activeSessions.first {
            currentSessionId = first.id
        }
    }

    /// Delete a session permanently (removes from storage)
    func deleteSession(_ session: Session) {
        // End Live Activity
        LiveActivityManager.shared.endActivity(for: session)

        // If connected, close properly
        if session.state == .connected {
            Task {
                await session.close()
            }
        }

        // Remove from list
        activeSessions.removeAll { $0.id == session.id }

        if currentSessionId == session.id {
            currentSessionId = activeSessions.first?.id
        }

        // Persist the change
        saveSessionState()
    }
}

// MARK: - Saved Session State

struct SavedSessionState: Codable, Identifiable {
    let id: UUID
    let hostId: UUID
    let name: String
    let tmuxSessionName: String
    let createdAt: Date
}

// MARK: - Session Manager Extensions

extension SessionManager {
    var hasActiveSessions: Bool {
        !activeSessions.isEmpty
    }

    var connectedSessionCount: Int {
        activeSessions.filter { $0.state == .connected }.count
    }

    var disconnectedSessionCount: Int {
        activeSessions.filter { $0.state == .disconnected }.count
    }

    /// Get all sessions for a specific host (supports multiple sessions per host)
    func sessions(for host: Host) -> [Session] {
        activeSessions.filter { $0.host.id == host.id }
    }

    /// Check if any session is connected to this host
    func isConnected(to host: Host) -> Bool {
        sessions(for: host).contains { $0.state == .connected }
    }

    /// Check if there's a disconnected session to this host that can be reconnected
    func hasDisconnectedSession(for host: Host) -> Bool {
        sessions(for: host).contains { $0.state == .disconnected }
    }
}

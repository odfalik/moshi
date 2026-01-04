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
    }

    // MARK: - Session Lifecycle

    func createSession(for host: Host) async throws -> Session {
        let session = Session(host: host)

        await MainActor.run {
            activeSessions.append(session)
            currentSessionId = session.id
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

    func closeSession(_ session: Session) {
        // End Live Activity
        LiveActivityManager.shared.endActivity(for: session)

        session.disconnect()

        activeSessions.removeAll { $0.id == session.id }

        if currentSessionId == session.id {
            currentSessionId = activeSessions.first?.id
        }
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
            // Remove from active sessions after a delay
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                await MainActor.run {
                    if session.state == .disconnected {
                        activeSessions.removeAll { $0.id == session.id }
                    }
                }
            }

        default:
            break
        }
    }

    // MARK: - Session Restoration

    func saveSessionState() {
        let sessionStates = activeSessions.map { session -> SavedSessionState in
            SavedSessionState(
                hostId: session.host.id,
                tmuxSessionName: session.tmuxSession?.name
            )
        }

        if let data = try? JSONEncoder().encode(sessionStates) {
            UserDefaults.standard.set(data, forKey: "savedSessions")
        }
    }

    func restoreSessions(hostManager: HostManager) async {
        guard let data = UserDefaults.standard.data(forKey: "savedSessions"),
              let states = try? JSONDecoder().decode([SavedSessionState].self, from: data) else {
            return
        }

        for state in states {
            if let host = hostManager.hosts.first(where: { $0.id == state.hostId }) {
                var restoredHost = host
                if let tmuxName = state.tmuxSessionName {
                    restoredHost.tmuxSessionName = tmuxName
                }

                do {
                    _ = try await createSession(for: restoredHost)
                } catch {
                    Logger.session.error("Failed to restore session: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Saved Session State

struct SavedSessionState: Codable {
    let hostId: UUID
    let tmuxSessionName: String?
}

// MARK: - Session Manager Extensions

extension SessionManager {
    var hasActiveSessions: Bool {
        !activeSessions.isEmpty
    }

    var connectedSessionCount: Int {
        activeSessions.filter { $0.state == .connected }.count
    }

    func session(for host: Host) -> Session? {
        activeSessions.first { $0.host.id == host.id }
    }

    func isConnected(to host: Host) -> Bool {
        session(for: host)?.state == .connected
    }
}

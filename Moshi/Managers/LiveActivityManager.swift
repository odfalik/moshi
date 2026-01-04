import Foundation
@preconcurrency import ActivityKit

@MainActor
final class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()

    private var activities: [UUID: Activity<SessionActivityAttributes>] = [:]
    private var updateTimers: [UUID: Timer] = [:]

    private init() {}

    // MARK: - Start Activity

    func startActivity(for session: Session) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Logger.session.warning("Live Activities are not enabled")
            return
        }

        let attributes = SessionActivityAttributes(
            hostname: session.host.hostname,
            username: session.host.username,
            useMosh: session.host.useMosh,
            hasTmux: session.host.autoTmux,
            sessionName: session.tmuxSession?.name
        )

        let initialState = SessionActivityAttributes.ContentState(
            connectionState: session.state.activityString,
            duration: 0,
            bytesSent: 0,
            bytesReceived: 0,
            lastActivity: Date()
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )

            activities[session.id] = activity
            startUpdateTimer(for: session)

            Logger.session.info("Started Live Activity for \(session.host.hostname)")
        } catch {
            Logger.session.error("Failed to start Live Activity: \(error.localizedDescription)")
        }
    }

    // MARK: - Update Activity

    func updateActivity(for session: Session, bytesSent: Int = 0, bytesReceived: Int = 0) {
        guard let activity = activities[session.id] else { return }

        let duration = Date().timeIntervalSince(session.createdAt)

        let updatedState = SessionActivityAttributes.ContentState(
            connectionState: session.state.activityString,
            duration: duration,
            bytesSent: bytesSent,
            bytesReceived: bytesReceived,
            lastActivity: session.lastActivity
        )

        Task {
            await activity.update(
                ActivityContent(state: updatedState, staleDate: Date().addingTimeInterval(60))
            )
        }
    }

    // MARK: - End Activity

    func endActivity(for session: Session) {
        guard let activity = activities[session.id] else { return }

        // Stop update timer
        updateTimers[session.id]?.invalidate()
        updateTimers.removeValue(forKey: session.id)

        let finalState = SessionActivityAttributes.ContentState(
            connectionState: "disconnected",
            duration: Date().timeIntervalSince(session.createdAt),
            bytesSent: 0,
            bytesReceived: 0,
            lastActivity: Date()
        )

        Task {
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .after(Date().addingTimeInterval(5))
            )

            await MainActor.run {
                activities.removeValue(forKey: session.id)
            }

            Logger.session.info("Ended Live Activity for \(session.host.hostname)")
        }
    }

    // MARK: - Timer

    private func startUpdateTimer(for session: Session) {
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateActivity(for: session)
            }
        }

        updateTimers[session.id] = timer
    }

    // MARK: - End All

    func endAllActivities() {
        for (sessionId, activity) in activities {
            updateTimers[sessionId]?.invalidate()

            let finalState = SessionActivityAttributes.ContentState(
                connectionState: "disconnected",
                duration: 0,
                bytesSent: 0,
                bytesReceived: 0,
                lastActivity: Date()
            )

            Task {
                await activity.end(
                    ActivityContent(state: finalState, staleDate: nil),
                    dismissalPolicy: .immediate
                )
            }
        }

        activities.removeAll()
        updateTimers.removeAll()
    }
}

// MARK: - ConnectionState Extension

extension ConnectionState {
    var activityString: String {
        switch self {
        case .disconnected: return "disconnected"
        case .connecting: return "connecting"
        case .authenticating: return "authenticating"
        case .connected: return "connected"
        case .reconnecting: return "reconnecting"
        case .disconnecting: return "disconnecting"
        case .error: return "error"
        }
    }
}

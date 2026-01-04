import ActivityKit
import WidgetKit
import SwiftUI

struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            // Lock Screen / Banner UI
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: context.attributes.useMosh ? "antenna.radiowaves.left.and.right" : "lock.fill")
                            .font(.caption)
                        Text(context.attributes.hostname)
                            .font(.caption.bold())
                            .lineLimit(1)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    ConnectionStatusBadge(state: context.state.connectionState)
                }

                DynamicIslandExpandedRegion(.center) {
                    HStack {
                        if let sessionName = context.attributes.sessionName {
                            Label(sessionName, systemImage: "square.split.2x2")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        // Duration
                        Label {
                            Text(formatDuration(context.state.duration))
                                .monospacedDigit()
                        } icon: {
                            Image(systemName: "clock")
                        }
                        .font(.caption)

                        Spacer()

                        // Traffic
                        HStack(spacing: 8) {
                            Label(formatBytes(context.state.bytesSent), systemImage: "arrow.up")
                            Label(formatBytes(context.state.bytesReceived), systemImage: "arrow.down")
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: context.attributes.useMosh ? "antenna.radiowaves.left.and.right" : "terminal")
                    .foregroundColor(colorForState(context.state.connectionState))
            } compactTrailing: {
                Text(context.attributes.hostname.prefix(8))
                    .font(.caption2.bold())
                    .lineLimit(1)
            } minimal: {
                Image(systemName: "terminal.fill")
                    .foregroundColor(colorForState(context.state.connectionState))
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes)B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1fK", Double(bytes) / 1024)
        } else {
            return String(format: "%.1fM", Double(bytes) / (1024 * 1024))
        }
    }

    private func colorForState(_ state: String) -> Color {
        switch state {
        case "connected": return .green
        case "connecting", "reconnecting": return .orange
        default: return .red
        }
    }
}

// MARK: - Lock Screen View

struct LockScreenView: View {
    let context: ActivityViewContext<SessionActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            // Left: Connection icon and status
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: context.attributes.useMosh ? "antenna.radiowaves.left.and.right" : "lock.fill")
                        .font(.title3)
                        .foregroundColor(colorForState(context.state.connectionState))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.hostname)
                            .font(.headline)
                            .lineLimit(1)

                        Text("\(context.attributes.username)@")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let sessionName = context.attributes.sessionName {
                    HStack(spacing: 4) {
                        Image(systemName: "square.split.2x2")
                            .font(.caption2)
                        Text("tmux: \(sessionName)")
                            .font(.caption2)
                    }
                    .foregroundColor(.green)
                }
            }

            Spacer()

            // Right: Stats
            VStack(alignment: .trailing, spacing: 4) {
                ConnectionStatusBadge(state: context.state.connectionState)

                Text(formatDuration(context.state.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)

                HStack(spacing: 6) {
                    Label(formatBytes(context.state.bytesSent), systemImage: "arrow.up")
                    Label(formatBytes(context.state.bytesReceived), systemImage: "arrow.down")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .activityBackgroundTint(.black.opacity(0.8))
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes)B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1fK", Double(bytes) / 1024)
        } else {
            return String(format: "%.1fM", Double(bytes) / (1024 * 1024))
        }
    }

    private func colorForState(_ state: String) -> Color {
        switch state {
        case "connected": return .green
        case "connecting", "reconnecting": return .orange
        default: return .red
        }
    }
}

// MARK: - Status Badge

struct ConnectionStatusBadge: View {
    let state: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(colorForState)
                .frame(width: 6, height: 6)

            Text(state.capitalized)
                .font(.caption2.bold())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(colorForState.opacity(0.2))
        .cornerRadius(8)
    }

    private var colorForState: Color {
        switch state {
        case "connected": return .green
        case "connecting", "reconnecting": return .orange
        default: return .red
        }
    }
}

// MARK: - Widget Bundle

@main
struct MoshiWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SessionLiveActivity()
    }
}

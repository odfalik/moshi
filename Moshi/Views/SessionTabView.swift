import SwiftUI

struct SessionTabView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var appSettings: AppSettings

    @State private var selectedSessionId: UUID?
    @State private var showingSessionPicker = false

    var body: some View {
        GeometryReader { geometry in
            if sessionManager.activeSessions.isEmpty {
                EmptyStateView()
            } else {
                VStack(spacing: 0) {
                    // Session tabs
                    if sessionManager.activeSessions.count > 1 {
                        SessionTabBar(
                            sessions: sessionManager.activeSessions,
                            selectedId: $selectedSessionId,
                            onClose: { session in
                                sessionManager.closeSession(session)
                            }
                        )
                    }

                    // Terminal view for selected session
                    if let session = currentSession {
                        TerminalView(session: session)
                            .id(session.id)
                    }
                }
            }
        }
        .onAppear {
            selectedSessionId = sessionManager.currentSessionId
        }
        .onChange(of: sessionManager.currentSessionId) { _, newId in
            selectedSessionId = newId
        }
        .onChange(of: selectedSessionId) { _, newId in
            if let id = newId {
                sessionManager.currentSessionId = id
            }
        }
    }

    private var currentSession: Session? {
        if let id = selectedSessionId {
            return sessionManager.activeSessions.first { $0.id == id }
        }
        return sessionManager.activeSessions.first
    }
}

// MARK: - Session Tab Bar

struct SessionTabBar: View {
    let sessions: [Session]
    @Binding var selectedId: UUID?
    let onClose: (Session) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(sessions) { session in
                    SessionTab(
                        session: session,
                        isSelected: session.id == selectedId,
                        onSelect: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedId = session.id
                            }
                        },
                        onClose: {
                            onClose(session)
                        }
                    )
                }

                // New session button
                Button {
                    // Would show host picker
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                        .padding(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 36)
        .background(Color(.systemGray6))
    }
}

struct SessionTab: View {
    @ObservedObject var session: Session
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            // Status indicator
            Circle()
                .fill(session.state.color)
                .frame(width: 6, height: 6)

            // Host name
            Text(session.host.displayName)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)

            // Tmux indicator
            if session.tmuxSession != nil {
                Image(systemName: "square.split.2x2")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            // Close button
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isSelected || isHovering ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color(.systemGray5) : Color.clear)
        .cornerRadius(6)
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            Button {
                // Duplicate session
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }

            Button {
                // Reconnect
                Task {
                    try? await session.connect()
                }
            } label: {
                Label("Reconnect", systemImage: "arrow.clockwise")
            }

            Divider()

            Button(role: .destructive, action: onClose) {
                Label("Close", systemImage: "xmark")
            }
        }
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    @EnvironmentObject var hostManager: HostManager
    @State private var showingQuickConnect = false

    var body: some View {
        VStack(spacing: 32) {
            Image(systemName: "terminal")
                .font(.system(size: 80))
                .foregroundColor(.secondary.opacity(0.5))

            VStack(spacing: 12) {
                Text("No Active Sessions")
                    .font(.title2.weight(.semibold))

                Text("Connect to a host to start a terminal session")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 16) {
                Button {
                    showingQuickConnect = true
                } label: {
                    Label("Quick Connect", systemImage: "bolt")
                        .font(.headline)
                        .frame(width: 200)
                }
                .buttonStyle(.borderedProminent)

                if !hostManager.favoriteHosts.isEmpty {
                    VStack(spacing: 8) {
                        Text("Favorites")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 12) {
                            ForEach(hostManager.favoriteHosts.prefix(4)) { host in
                                QuickHostButton(host: host)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingQuickConnect) {
            QuickConnectView()
        }
    }
}

struct QuickHostButton: View {
    let host: Host
    @EnvironmentObject var sessionManager: SessionManager

    var body: some View {
        Button {
            Task {
                try? await sessionManager.createSession(for: host)
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "server.rack")
                    .font(.title2)

                Text(host.displayName)
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(width: 60, height: 60)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SessionTabView()
        .environmentObject(SessionManager.shared)
        .environmentObject(HostManager.shared)
        .environmentObject(AppSettings.shared)
}

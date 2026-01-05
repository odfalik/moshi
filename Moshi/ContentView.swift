import SwiftUI

struct ContentView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var hostManager: HostManager
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var networkMonitor: NetworkMonitor

    @State private var selectedTab: ContentTab = .hosts
    @State private var showingQuickConnect = false
    @State private var showingAddHost = false
    @State private var showingSettings = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var sessionNavigationPath = NavigationPath()

    enum ContentTab: String, CaseIterable {
        case hosts = "Hosts"
        case sessions = "Sessions"
        case keys = "Keys"
    }

    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .sheet(isPresented: $showingQuickConnect) {
            QuickConnectView()
        }
        .sheet(isPresented: $showingAddHost) {
            NavigationStack {
                HostEditView(host: nil)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .overlay(alignment: .top) {
            if !networkMonitor.isConnected {
                NetworkWarningBanner()
            }
        }
    }

    // MARK: - iPad Layout

    private var iPadLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent
        } detail: {
            if sessionManager.activeSessions.isEmpty {
                EmptySessionView(showingQuickConnect: $showingQuickConnect)
            } else {
                SessionTabView()
            }
        }
    }

    // MARK: - iPhone Layout

    private var iPhoneLayout: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HostListView()
                    .toolbar {
                        toolbarContent
                    }
            }
            .tabItem {
                Label("Hosts", systemImage: "server.rack")
            }
            .tag(ContentTab.hosts)

            NavigationStack(path: $sessionNavigationPath) {
                SessionListView()
                    .navigationDestination(for: UUID.self) { sessionId in
                        if let session = sessionManager.activeSessions.first(where: { $0.id == sessionId }) {
                            TerminalContainerView(session: session)
                        }
                    }
            }
            .tabItem {
                Label("Sessions", systemImage: "terminal")
            }
            .tag(ContentTab.sessions)
            .badge(sessionManager.activeSessions.count)

            NavigationStack {
                KeyGeneratorView()
            }
            .tabItem {
                Label("Keys", systemImage: "key")
            }
            .tag(ContentTab.keys)
        }
        .onChange(of: sessionManager.pendingNavigationSessionId) { _, sessionId in
            if let sessionId = sessionId {
                // Switch to sessions tab and navigate to the session
                selectedTab = .sessions
                // Small delay to ensure tab switch completes before navigation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    sessionNavigationPath.append(sessionId)
                    // Clear the pending navigation
                    sessionManager.pendingNavigationSessionId = nil
                }
            }
        }
    }

    // MARK: - Sidebar Content

    private var sidebarContent: some View {
        List {
            Section("Hosts") {
                HostListView()
            }

            Section("Active Sessions") {
                ForEach(sessionManager.activeSessions) { session in
                    SessionRowView(session: session)
                }
            }

            Section("Tools") {
                NavigationLink {
                    KeyGeneratorView()
                } label: {
                    Label("SSH Keys", systemImage: "key")
                }

                NavigationLink {
                    MacroEditorView()
                } label: {
                    Label("Macros", systemImage: "command")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Moshi")
        .toolbar {
            toolbarContent
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    showingQuickConnect = true
                } label: {
                    Label("Quick Connect", systemImage: "bolt")
                }

                Button {
                    showingAddHost = true
                } label: {
                    Label("Add Host", systemImage: "plus")
                }
            } label: {
                Image(systemName: "plus")
            }
        }

        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gear")
            }
        }
    }
}

// MARK: - Supporting Views

struct NetworkWarningBanner: View {
    var body: some View {
        HStack {
            Image(systemName: "wifi.slash")
            Text("No Network Connection")
                .font(.footnote.weight(.medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange)
        .cornerRadius(20)
        .padding(.top, 4)
    }
}

struct EmptySessionView: View {
    @Binding var showingQuickConnect: Bool

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "terminal")
                .font(.system(size: 72))
                .foregroundColor(.secondary)

            Text("No Active Sessions")
                .font(.title2.weight(.semibold))

            Text("Connect to a host to start a terminal session")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showingQuickConnect = true
            } label: {
                Label("Quick Connect", systemImage: "bolt")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

struct SessionListView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var reconnectingSessionId: UUID?

    var body: some View {
        Group {
            if sessionManager.activeSessions.isEmpty {
                ContentUnavailableView(
                    "No Active Sessions",
                    systemImage: "terminal",
                    description: Text("Connect to a host to start a session")
                )
            } else {
                List {
                    ForEach(sessionManager.activeSessions) { session in
                        SessionRowView(
                            session: session,
                            isReconnecting: reconnectingSessionId == session.id,
                            onReconnect: {
                                reconnectSession(session)
                            }
                        )
                        .contextMenu {
                            sessionContextMenu(for: session)
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let session = sessionManager.activeSessions[index]
                            sessionManager.closeSession(session)
                        }
                    }
                }
            }
        }
        .navigationTitle("Sessions")
    }

    private func reconnectSession(_ session: Session) {
        reconnectingSessionId = session.id
        Task {
            do {
                try await sessionManager.reconnectSession(session)
            } catch {
                Logger.session.error("Reconnect failed: \(error.localizedDescription)")
            }
            await MainActor.run {
                reconnectingSessionId = nil
            }
        }
    }

    @ViewBuilder
    private func sessionContextMenu(for session: Session) -> some View {
        if session.state == .disconnected {
            Button {
                reconnectSession(session)
            } label: {
                Label("Reconnect", systemImage: "arrow.clockwise")
            }
        } else if session.state == .connected {
            Button {
                sessionManager.disconnectSession(session)
            } label: {
                Label("Disconnect", systemImage: "pause.circle")
            }
        }

        Divider()

        Button(role: .destructive) {
            sessionManager.closeSession(session)
        } label: {
            Label("Close Session", systemImage: "xmark.circle")
        }
    }
}

struct SessionRowView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @ObservedObject var session: Session
    var isReconnecting: Bool = false
    var onReconnect: (() -> Void)?

    var body: some View {
        Group {
            if session.state == .connected {
                // Connected sessions navigate to terminal
                NavigationLink(value: session.id) {
                    rowContent
                }
            } else if session.state == .disconnected {
                // Disconnected sessions show reconnect button
                Button {
                    onReconnect?()
                } label: {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                // Other states (connecting, etc.) - just show info
                rowContent
            }
        }
    }

    private var rowContent: some View {
        HStack {
            // Status indicator
            if isReconnecting || session.state == .connecting {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 12, height: 12)
            } else {
                Circle()
                    .fill(session.state.color)
                    .frame(width: 8, height: 8)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.host.displayName)
                        .font(.headline)
                        .foregroundColor(session.state == .disconnected ? .secondary : .primary)

                    // Show reconnect hint for disconnected sessions
                    if session.state == .disconnected && !isReconnecting {
                        Text("Tap to reconnect")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }

                HStack(spacing: 4) {
                    Text(session.host.connectionString)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Tmux session name
                    if session.tmuxStatus == .attached {
                        Text("[\(session.tmuxSessionName)]")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }

                    // Tmux status indicator
                    if session.tmuxStatus != .disabled && session.tmuxStatus != .unknown {
                        TmuxStatusBadge(status: session.tmuxStatus)
                    }
                }
            }

            Spacer()

            // Action indicator
            if session.state == .disconnected {
                Image(systemName: "arrow.clockwise.circle")
                    .foregroundColor(.blue)
                    .font(.body)
            } else if session.tmuxSession != nil {
                Image(systemName: "square.split.2x2")
                    .foregroundColor(.blue)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
        .opacity(session.state == .disconnected ? 0.8 : 1.0)
    }
}

struct TmuxStatusBadge: View {
    let status: TmuxStatus

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: status.icon)
            if status == .attached {
                Text("tmux")
            }
        }
        .font(.caption2)
        .foregroundColor(status.color)
        .help(status.description)
    }
}

struct TerminalContainerView: View {
    let session: Session

    var body: some View {
        TerminalView(session: session)
            .navigationTitle(session.host.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
    }
}

#Preview {
    ContentView()
        .environmentObject(SessionManager.shared)
        .environmentObject(HostManager.shared)
        .environmentObject(AppSettings.shared)
        .environmentObject(NetworkMonitor.shared)
}

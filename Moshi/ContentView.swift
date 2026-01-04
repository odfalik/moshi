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

            NavigationStack {
                SessionListView()
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
                        NavigationLink {
                            TerminalContainerView(session: session)
                        } label: {
                            SessionRowView(session: session)
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
}

struct SessionRowView: View {
    let session: Session

    var body: some View {
        HStack {
            Circle()
                .fill(session.state.color)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.host.displayName)
                    .font(.headline)

                Text(session.host.connectionString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if session.tmuxSession != nil {
                Image(systemName: "square.split.2x2")
                    .foregroundColor(.blue)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TerminalContainerView: View {
    let session: Session

    var body: some View {
        TerminalView(session: session)
            .navigationTitle(session.host.displayName)
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    ContentView()
        .environmentObject(SessionManager.shared)
        .environmentObject(HostManager.shared)
        .environmentObject(AppSettings.shared)
        .environmentObject(NetworkMonitor.shared)
}

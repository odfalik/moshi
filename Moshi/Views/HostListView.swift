import SwiftUI

struct HostListView: View {
    @EnvironmentObject var hostManager: HostManager
    @EnvironmentObject var sessionManager: SessionManager

    @State private var searchText = ""
    @State private var showingAddHost = false
    @State private var selectedHost: Host?
    @State private var showingHostActions = false

    var filteredHosts: [Host] {
        if searchText.isEmpty {
            return hostManager.hosts
        }
        return hostManager.searchHosts(searchText)
    }

    var body: some View {
        List {
            // Favorites section
            if !hostManager.favoriteHosts.isEmpty && searchText.isEmpty {
                Section("Favorites") {
                    ForEach(hostManager.favoriteHosts) { host in
                        HostRow(host: host, isConnected: sessionManager.isConnected(to: host))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                connectToHost(host)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    hostManager.deleteHost(host)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }

                                Button {
                                    selectedHost = host
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    hostManager.toggleFavorite(host)
                                } label: {
                                    Label("Unfavorite", systemImage: "star.slash")
                                }
                                .tint(.yellow)
                            }
                    }
                }
            }

            // Recent connections
            if !sessionManager.recentConnections.isEmpty && searchText.isEmpty {
                Section("Recent") {
                    ForEach(sessionManager.recentConnections.prefix(5)) { host in
                        HostRow(host: host, isConnected: sessionManager.isConnected(to: host))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                connectToHost(host)
                            }
                    }
                }
            }

            // All hosts or search results
            Section(searchText.isEmpty ? "All Hosts" : "Search Results") {
                if filteredHosts.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Hosts" : "No Results",
                        systemImage: searchText.isEmpty ? "server.rack" : "magnifyingglass",
                        description: Text(searchText.isEmpty ? "Add a host to get started" : "Try a different search term")
                    )
                } else {
                    ForEach(filteredHosts) { host in
                        HostRow(host: host, isConnected: sessionManager.isConnected(to: host))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                connectToHost(host)
                            }
                            .contextMenu {
                                hostContextMenu(for: host)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    hostManager.deleteHost(host)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }

                                Button {
                                    selectedHost = host
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    hostManager.toggleFavorite(host)
                                } label: {
                                    Label(
                                        host.isFavorite ? "Unfavorite" : "Favorite",
                                        systemImage: host.isFavorite ? "star.slash" : "star"
                                    )
                                }
                                .tint(.yellow)
                            }
                    }
                    .onDelete { offsets in
                        hostManager.deleteHosts(at: offsets)
                    }
                    .onMove { source, destination in
                        hostManager.moveHost(from: source, to: destination)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search hosts")
        .navigationTitle("Hosts")
        .sheet(isPresented: $showingAddHost) {
            NavigationStack {
                HostEditView(host: nil)
            }
        }
        .sheet(item: $selectedHost) { host in
            NavigationStack {
                HostEditView(host: host)
            }
        }
    }

    private func connectToHost(_ host: Host) {
        Task {
            do {
                _ = try await sessionManager.createSession(for: host)
            } catch {
                Logger.session.error("Failed to connect: \(error.localizedDescription)")
            }
        }
    }

    @ViewBuilder
    private func hostContextMenu(for host: Host) -> some View {
        Button {
            connectToHost(host)
        } label: {
            Label("Connect", systemImage: "arrow.right.circle")
        }

        Button {
            var sshHost = host
            sshHost.useMosh = false
            connectToHost(sshHost)
        } label: {
            Label("Connect with SSH", systemImage: "lock")
        }

        Divider()

        Button {
            hostManager.toggleFavorite(host)
        } label: {
            Label(
                host.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                systemImage: host.isFavorite ? "star.slash" : "star"
            )
        }

        Button {
            selectedHost = host
        } label: {
            Label("Edit", systemImage: "pencil")
        }

        Divider()

        Button {
            UIPasteboard.general.string = host.connectionString
        } label: {
            Label("Copy Connection String", systemImage: "doc.on.doc")
        }

        Divider()

        Button(role: .destructive) {
            hostManager.deleteHost(host)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

// MARK: - Host Row

struct HostRow: View {
    let host: Host
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Color tag
            if let colorTag = host.colorTag {
                Circle()
                    .fill(colorTag.color)
                    .frame(width: 8, height: 8)
            }

            // Connection indicator
            if isConnected {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
            }

            // Host info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(host.displayName)
                        .font(.headline)

                    if host.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                }

                Text(host.connectionString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Protocol indicators
            HStack(spacing: 8) {
                if host.useMosh {
                    Label("Mosh", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }

                if host.autoTmux {
                    Label("tmux", systemImage: "square.split.2x2")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
            .labelStyle(.iconOnly)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        HostListView()
            .environmentObject(HostManager.shared)
            .environmentObject(SessionManager.shared)
    }
}

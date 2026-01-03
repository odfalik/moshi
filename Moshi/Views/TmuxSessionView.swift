import SwiftUI

struct TmuxSessionView: View {
    @ObservedObject var session: Session
    @State private var showingNewWindow = false
    @State private var showingSessionPicker = false

    var body: some View {
        VStack(spacing: 0) {
            if let tmuxSession = session.tmuxSession {
                // Window tabs
                TmuxWindowTabs(
                    session: session,
                    tmuxSession: tmuxSession,
                    onNewWindow: { showingNewWindow = true }
                )

                Divider()

                // Pane layout
                if let activeWindow = tmuxSession.windows.first(where: { $0.isActive }) {
                    TmuxPaneLayout(session: session, window: activeWindow)
                }
            } else {
                // Not attached to tmux
                TmuxNotAttachedView(session: session)
            }
        }
        .sheet(isPresented: $showingNewWindow) {
            TmuxNewWindowSheet(session: session)
        }
        .sheet(isPresented: $showingSessionPicker) {
            TmuxSessionPickerSheet(session: session)
        }
    }
}

// MARK: - Window Tabs

struct TmuxWindowTabs: View {
    @ObservedObject var session: Session
    let tmuxSession: TmuxSession
    let onNewWindow: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(tmuxSession.windows) { window in
                    TmuxWindowTabButton(
                        window: window,
                        isActive: window.isActive
                    ) {
                        session.switchTmuxWindow(window.index)
                    } onClose: {
                        session.sendCommand("tmux kill-window -t \(window.index)")
                    }
                }

                Button(action: onNewWindow) {
                    Image(systemName: "plus")
                        .font(.caption)
                        .padding(8)
                        .background(Color(.systemGray5))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGray6))
    }
}

struct TmuxWindowTabButton: View {
    let window: TmuxWindow
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("\(window.index):")
                .font(.caption2)
                .foregroundColor(.secondary)

            Text(window.name)
                .font(.caption.weight(isActive ? .semibold : .regular))

            if window.panes.count > 1 {
                Text("[\(window.panes.count)]")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isActive ? Color.accentColor.opacity(0.15) : Color(.systemGray5))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 1)
        )
        .onTapGesture(perform: onSelect)
    }
}

// MARK: - Pane Layout

struct TmuxPaneLayout: View {
    @ObservedObject var session: Session
    let window: TmuxWindow

    var body: some View {
        GeometryReader { geometry in
            if window.panes.count == 1 {
                // Single pane - full screen
                PaneView(pane: window.panes[0], isActive: true)
            } else {
                // Multiple panes - simplified layout
                // In a full implementation, this would parse tmux layout string
                HStack(spacing: 1) {
                    ForEach(window.panes) { pane in
                        PaneView(pane: pane, isActive: pane.isActive)
                            .onTapGesture {
                                session.sendCommand("tmux select-pane -t \(pane.index)")
                            }
                    }
                }
            }
        }
    }
}

struct PaneView: View {
    let pane: TmuxPane
    let isActive: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Pane content would be rendered here
            // In practice, this connects to the terminal emulator

            Rectangle()
                .fill(Color(.systemBackground))
                .overlay(alignment: .topLeading) {
                    if let command = pane.currentCommand {
                        Text(command)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(4)
                    }
                }
        }
        .border(isActive ? Color.accentColor : Color(.systemGray4), width: isActive ? 2 : 1)
    }
}

// MARK: - Not Attached View

struct TmuxNotAttachedView: View {
    @ObservedObject var session: Session
    @State private var sessions: [TmuxSession] = []
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 24) {
            if isLoading {
                ProgressView()
                Text("Loading tmux sessions...")
                    .foregroundColor(.secondary)
            } else if sessions.isEmpty {
                Image(systemName: "square.split.2x2")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)

                Text("No Tmux Sessions")
                    .font(.title3.weight(.semibold))

                Text("Create a new tmux session to get started")
                    .foregroundColor(.secondary)

                Button {
                    createNewSession()
                } label: {
                    Label("New Session", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("Available Sessions")
                    .font(.headline)

                ForEach(sessions) { tmuxSession in
                    TmuxSessionCard(tmuxSession: tmuxSession) {
                        attachToSession(tmuxSession)
                    }
                }

                Button {
                    createNewSession()
                } label: {
                    Label("New Session", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .task {
            await loadSessions()
        }
    }

    private func loadSessions() async {
        let tmux = TmuxIntegration(session: session)
        do {
            sessions = try await tmux.listSessions()
        } catch {
            sessions = []
        }
        isLoading = false
    }

    private func attachToSession(_ tmuxSession: TmuxSession) {
        Task {
            let tmux = TmuxIntegration(session: session)
            try? await tmux.attachSession(tmuxSession)
        }
    }

    private func createNewSession() {
        Task {
            let tmux = TmuxIntegration(session: session)
            _ = try? await tmux.createSession()
        }
    }
}

struct TmuxSessionCard: View {
    let tmuxSession: TmuxSession
    let onAttach: () -> Void

    var body: some View {
        Button(action: onAttach) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(tmuxSession.name)
                            .font(.headline)

                        if tmuxSession.attached {
                            Text("attached")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
                                .cornerRadius(4)
                        }
                    }

                    Text("\(tmuxSession.windows.count) windows")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.right.circle")
                    .foregroundColor(.accentColor)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - New Window Sheet

struct TmuxNewWindowSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: Session

    @State private var windowName = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Window Name (optional)", text: $windowName)
            }
            .navigationTitle("New Window")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            try? await session.createTmuxWindow(name: windowName.isEmpty ? nil : windowName)
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Session Picker Sheet

struct TmuxSessionPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: Session

    @State private var sessions: [TmuxSession] = []
    @State private var isLoading = true
    @State private var newSessionName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Create New") {
                    HStack {
                        TextField("Session name", text: $newSessionName)

                        Button("Create") {
                            createSession()
                        }
                        .disabled(newSessionName.isEmpty)
                    }
                }

                Section("Existing Sessions") {
                    if isLoading {
                        ProgressView()
                    } else if sessions.isEmpty {
                        Text("No sessions found")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(sessions) { tmuxSession in
                            Button {
                                attachSession(tmuxSession)
                            } label: {
                                HStack {
                                    Text(tmuxSession.name)
                                    Spacer()
                                    if tmuxSession.attached {
                                        Text("attached")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tmux Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadSessions()
            }
        }
    }

    private func loadSessions() async {
        let tmux = TmuxIntegration(session: session)
        sessions = (try? await tmux.listSessions()) ?? []
        isLoading = false
    }

    private func createSession() {
        Task {
            let tmux = TmuxIntegration(session: session)
            _ = try? await tmux.createSession(name: newSessionName)
            dismiss()
        }
    }

    private func attachSession(_ tmuxSession: TmuxSession) {
        Task {
            let tmux = TmuxIntegration(session: session)
            try? await tmux.attachSession(tmuxSession)
            dismiss()
        }
    }
}

#Preview {
    let session = Session(host: Host(hostname: "localhost", username: "user"))
    return TmuxSessionView(session: session)
}

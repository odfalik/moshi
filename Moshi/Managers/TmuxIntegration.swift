import Foundation
import Combine

final class TmuxIntegration {
    private weak var session: Session?
    private var pendingCommands: [String: CheckedContinuation<String, Error>] = [:]

    static let detachCommand = "tmux detach"
    static let defaultSessionName = "moshi"

    init(session: Session) {
        self.session = session
    }

    // MARK: - Session Management

    func listSessions() async throws -> [TmuxSession] {
        let output = try await executeCommand("tmux list-sessions -F '#{session_id}:#{session_name}:#{session_windows}:#{session_attached}:#{session_created}'")

        guard !output.contains("no server running") && !output.contains("no sessions") else {
            return []
        }

        return output.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line -> TmuxSession? in
                let parts = line.components(separatedBy: ":")
                guard parts.count >= 5 else { return nil }

                return TmuxSession(
                    id: parts[0],
                    name: parts[1],
                    windows: [],
                    activeWindowIndex: 0,
                    attached: parts[3] == "1",
                    createdAt: Date(timeIntervalSince1970: TimeInterval(parts[4]) ?? 0)
                )
            }
    }

    func createSession(name: String? = nil) async throws -> TmuxSession {
        let sessionName = name ?? TmuxIntegration.defaultSessionName

        // Create session but don't attach (we'll attach separately)
        let output = try await executeCommand("tmux new-session -d -s '\(sessionName)' -P -F '#{session_id}'")
        let sessionId = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Now attach to the session
        try await attachSession(TmuxSession(id: sessionId, name: sessionName))

        return TmuxSession(
            id: sessionId,
            name: sessionName,
            windows: [TmuxWindow(id: "0", index: 0, name: "bash", isActive: true)],
            activeWindowIndex: 0,
            attached: true,
            createdAt: Date()
        )
    }

    func attachSession(_ tmuxSession: TmuxSession) async throws {
        // Attach to existing session
        session?.sendCommand("tmux attach-session -t '\(tmuxSession.name)'")
    }

    func killSession(_ tmuxSession: TmuxSession) async throws {
        _ = try await executeCommand("tmux kill-session -t '\(tmuxSession.name)'")
    }

    func renameSession(_ tmuxSession: TmuxSession, to newName: String) async throws {
        _ = try await executeCommand("tmux rename-session -t '\(tmuxSession.name)' '\(newName)'")
    }

    // MARK: - Window Management

    func listWindows(in tmuxSession: TmuxSession? = nil) async throws -> [TmuxWindow] {
        let targetFlag = tmuxSession.map { "-t '\($0.name)'" } ?? ""
        let output = try await executeCommand("tmux list-windows \(targetFlag) -F '#{window_id}:#{window_index}:#{window_name}:#{window_active}:#{window_panes}'")

        return output.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line -> TmuxWindow? in
                let parts = line.components(separatedBy: ":")
                guard parts.count >= 5 else { return nil }

                return TmuxWindow(
                    id: parts[0],
                    index: Int(parts[1]) ?? 0,
                    name: parts[2],
                    panes: [],
                    isActive: parts[3] == "1"
                )
            }
    }

    func createWindow(name: String? = nil) async throws {
        var command = "tmux new-window"
        if let name = name {
            command += " -n '\(name)'"
        }
        session?.sendCommand(command)
    }

    func closeWindow(index: Int) async throws {
        session?.sendCommand("tmux kill-window -t \(index)")
    }

    func selectWindow(index: Int) async throws {
        session?.sendCommand("tmux select-window -t \(index)")
    }

    func renameWindow(index: Int, to name: String) async throws {
        session?.sendCommand("tmux rename-window -t \(index) '\(name)'")
    }

    func moveWindow(from: Int, to: Int) async throws {
        session?.sendCommand("tmux move-window -s \(from) -t \(to)")
    }

    // MARK: - Pane Management

    func listPanes(in window: TmuxWindow? = nil) async throws -> [TmuxPane] {
        let targetFlag = window.map { "-t \($0.id)" } ?? ""
        let output = try await executeCommand("tmux list-panes \(targetFlag) -F '#{pane_id}:#{pane_index}:#{pane_width}:#{pane_height}:#{pane_active}:#{pane_current_command}'")

        return output.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line -> TmuxPane? in
                let parts = line.components(separatedBy: ":")
                guard parts.count >= 6 else { return nil }

                return TmuxPane(
                    id: parts[0],
                    index: Int(parts[1]) ?? 0,
                    width: Int(parts[2]) ?? 80,
                    height: Int(parts[3]) ?? 24,
                    isActive: parts[4] == "1",
                    currentCommand: parts[5].isEmpty ? nil : parts[5]
                )
            }
    }

    func splitPane(horizontal: Bool, percentage: Int? = nil) {
        var command = "tmux split-window"
        command += horizontal ? " -h" : " -v"

        if let percentage = percentage {
            command += " -p \(percentage)"
        }

        session?.sendCommand(command)
    }

    func selectPane(direction: PaneDirection) {
        let flag: String
        switch direction {
        case .left: flag = "-L"
        case .right: flag = "-R"
        case .up: flag = "-U"
        case .down: flag = "-D"
        case .next: flag = "-t :.+"
        case .previous: flag = "-t :.-"
        }

        session?.sendCommand("tmux select-pane \(flag)")
    }

    func resizePane(direction: PaneDirection, amount: Int) {
        let flag: String
        switch direction {
        case .left: flag = "-L"
        case .right: flag = "-R"
        case .up: flag = "-U"
        case .down: flag = "-D"
        default: return
        }

        session?.sendCommand("tmux resize-pane \(flag) \(amount)")
    }

    func zoomPane() {
        session?.sendCommand("tmux resize-pane -Z")
    }

    func closePane() {
        session?.sendCommand("tmux kill-pane")
    }

    func swapPane(with direction: PaneDirection) {
        let flag: String
        switch direction {
        case .up: flag = "-U"
        case .down: flag = "-D"
        default: return
        }

        session?.sendCommand("tmux swap-pane \(flag)")
    }

    // MARK: - Copy Mode

    func enterCopyMode() {
        session?.sendCommand("tmux copy-mode")
    }

    func exitCopyMode() {
        session?.sendSpecialKey(.escape)
    }

    func paste() {
        session?.sendCommand("tmux paste-buffer")
    }

    // MARK: - Layout

    func selectLayout(_ layout: TmuxLayout) {
        session?.sendCommand("tmux select-layout \(layout.rawValue)")
    }

    // MARK: - Command Execution

    private func executeCommand(_ command: String) async throws -> String {
        // For commands that need output, we use a marker system
        let marker = UUID().uuidString

        return try await withCheckedThrowingContinuation { continuation in
            pendingCommands[marker] = continuation

            // Execute command and echo marker when done
            session?.sendCommand("\(command); echo 'MOSHI_MARKER:\(marker):'$?")

            // Timeout after 5 seconds
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if let cont = pendingCommands.removeValue(forKey: marker) {
                    cont.resume(throwing: TmuxError.timeout)
                }
            }
        }
    }

    func processOutput(_ output: String) {
        // Look for our markers in the output
        let pattern = "MOSHI_MARKER:([^:]+):([0-9]+)"

        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

        let range = NSRange(output.startIndex..., in: output)
        let matches = regex.matches(in: output, range: range)

        for match in matches {
            guard let markerRange = Range(match.range(at: 1), in: output),
                  let exitCodeRange = Range(match.range(at: 2), in: output) else { continue }

            let marker = String(output[markerRange])

            if let continuation = pendingCommands.removeValue(forKey: marker) {
                // Extract output before the marker
                let outputEnd = output.range(of: "MOSHI_MARKER:\(marker)")?.lowerBound ?? output.endIndex
                let commandOutput = String(output[..<outputEnd]).trimmingCharacters(in: .whitespacesAndNewlines)

                continuation.resume(returning: commandOutput)
            }
        }
    }
}

// MARK: - Types

enum PaneDirection {
    case left, right, up, down, next, previous
}

enum TmuxLayout: String, CaseIterable {
    case evenHorizontal = "even-horizontal"
    case evenVertical = "even-vertical"
    case mainHorizontal = "main-horizontal"
    case mainVertical = "main-vertical"
    case tiled = "tiled"
}

enum TmuxError: LocalizedError {
    case timeout
    case notAttached
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .timeout:
            return "Tmux command timed out"
        case .notAttached:
            return "Not attached to a tmux session"
        case .commandFailed(let message):
            return "Tmux command failed: \(message)"
        }
    }
}

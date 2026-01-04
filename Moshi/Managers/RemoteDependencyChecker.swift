import Foundation

struct RemoteDependency: Identifiable {
    let id = UUID()
    let name: String
    let command: String
    let required: Bool
    let installCommands: [String: String] // package manager -> command

    var isInstalled: Bool = false
    var version: String?
}

final class RemoteDependencyChecker {
    private weak var session: Session?

    static let dependencies: [RemoteDependency] = [
        RemoteDependency(
            name: "tmux",
            command: "tmux",
            required: false,
            installCommands: [
                "apt": "sudo apt-get install -y tmux",
                "yum": "sudo yum install -y tmux",
                "dnf": "sudo dnf install -y tmux",
                "brew": "brew install tmux",
                "pacman": "sudo pacman -S --noconfirm tmux",
                "apk": "sudo apk add tmux"
            ]
        ),
        RemoteDependency(
            name: "mosh-server",
            command: "mosh-server",
            required: false,
            installCommands: [
                "apt": "sudo apt-get install -y mosh",
                "yum": "sudo yum install -y mosh",
                "dnf": "sudo dnf install -y mosh",
                "brew": "brew install mosh",
                "pacman": "sudo pacman -S --noconfirm mosh",
                "apk": "sudo apk add mosh"
            ]
        )
    ]

    init(session: Session) {
        self.session = session
    }

    // MARK: - Check Dependencies

    func checkAll() async -> [RemoteDependency] {
        var results: [RemoteDependency] = []

        for dep in Self.dependencies {
            var checkedDep = dep
            let result = await checkDependency(dep)
            checkedDep.isInstalled = result.installed
            checkedDep.version = result.version
            results.append(checkedDep)
        }

        return results
    }

    func checkDependency(_ dep: RemoteDependency) async -> (installed: Bool, version: String?) {
        guard let output = await executeCommand("which \(dep.command) && \(dep.command) --version 2>/dev/null | head -1") else {
            return (false, nil)
        }

        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }

        // If 'which' found the command, first line will be the path
        if lines.first?.hasPrefix("/") == true {
            let version = lines.count > 1 ? lines[1] : nil
            return (true, version)
        }

        return (false, nil)
    }

    // MARK: - Detect Package Manager

    func detectPackageManager() async -> String? {
        let managers = [
            ("apt", "which apt-get"),
            ("yum", "which yum"),
            ("dnf", "which dnf"),
            ("brew", "which brew"),
            ("pacman", "which pacman"),
            ("apk", "which apk")
        ]

        for (name, command) in managers {
            if let output = await executeCommand(command), output.contains("/") {
                return name
            }
        }

        return nil
    }

    // MARK: - Install Dependency

    func installDependency(_ dep: RemoteDependency) async -> Bool {
        guard let packageManager = await detectPackageManager(),
              let installCommand = dep.installCommands[packageManager] else {
            Logger.session.error("Could not determine package manager for installing \(dep.name)")
            return false
        }

        // Send the install command
        session?.sendCommand(installCommand)

        // Wait a bit and verify
        try? await Task.sleep(nanoseconds: 3_000_000_000)

        let result = await checkDependency(dep)
        return result.installed
    }

    // MARK: - Quick Checks

    func hasTmux() async -> Bool {
        let result = await checkDependency(Self.dependencies.first { $0.name == "tmux" }!)
        return result.installed
    }

    func hasMoshServer() async -> Bool {
        let result = await checkDependency(Self.dependencies.first { $0.name == "mosh-server" }!)
        return result.installed
    }

    // MARK: - Command Execution

    private func executeCommand(_ command: String) async -> String? {
        // Use a marker-based approach to capture output
        let marker = "MOSHI_DEP_CHECK_\(UUID().uuidString.prefix(8))"

        return await withCheckedContinuation { continuation in
            var output = ""
            var completed = false

            // Set up a temporary observer for output
            let observation = session?.$terminalOutput.sink { newOutput in
                if newOutput.contains(marker) {
                    // Extract output between command and marker
                    if let range = newOutput.range(of: marker) {
                        let beforeMarker = String(newOutput[..<range.lowerBound])
                        // Get last chunk of output (after our command)
                        let lines = beforeMarker.components(separatedBy: "\n")
                        output = lines.suffix(10).joined(separator: "\n")
                    }

                    if !completed {
                        completed = true
                        continuation.resume(returning: output)
                    }
                }
            }

            // Execute the command with a marker
            session?.sendCommand("\(command); echo '\(marker)'")

            // Timeout after 5 seconds
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                observation?.cancel()
                if !completed {
                    completed = true
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

// MARK: - Missing Dependencies View

import SwiftUI

struct MissingDependenciesView: View {
    let dependencies: [RemoteDependency]
    let onInstall: (RemoteDependency) -> Void
    let onSkip: () -> Void

    var missingDependencies: [RemoteDependency] {
        dependencies.filter { !$0.isInstalled }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(missingDependencies) { dep in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(dep.name)
                                    .font(.headline)
                                Text(dep.required ? "Required" : "Recommended")
                                    .font(.caption)
                                    .foregroundColor(dep.required ? .red : .orange)
                            }

                            Spacer()

                            Button("Install") {
                                onInstall(dep)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                } header: {
                    Text("Missing Dependencies")
                } footer: {
                    Text("Some features may not work without these tools installed on the remote server.")
                }
            }
            .navigationTitle("Setup Required")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        onSkip()
                    }
                }
            }
        }
    }
}

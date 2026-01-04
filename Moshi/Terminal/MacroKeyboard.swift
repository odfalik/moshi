import SwiftUI

struct MacroKeyboard: View {
    @ObservedObject var session: Session
    @EnvironmentObject var appSettings: AppSettings
    @StateObject private var macroManager = MacroManager.shared
    @ObservedObject private var dictationManager = DictationManager.shared

    @State private var activeRow: MacroRow = .special
    @State private var showingMacroEditor = false
    @State private var isRecordingDictation = false

    enum MacroRow: String, CaseIterable {
        case special = "Special"
        case bash = "Bash"
        case git = "Git"
        case claude = "Claude"
        case tmux = "Tmux"
        case custom = "Custom"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Row selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(MacroRow.allCases, id: \.self) { row in
                        RowTab(title: row.rawValue, isActive: activeRow == row) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                activeRow = row
                            }
                        }
                    }

                    Spacer()

                    // Dictation button
                    Button {
                        toggleDictation()
                    } label: {
                        Image(systemName: isRecordingDictation ? "mic.fill" : "mic")
                            .foregroundColor(isRecordingDictation ? .red : .primary)
                            .padding(.horizontal, 12)
                    }

                    // Edit macros button
                    Button {
                        showingMacroEditor = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .padding(.horizontal, 8)
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 32)
            .background(Color(.systemGray5))

            // Macro buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(macrosForRow(activeRow)) { macro in
                        MacroButton(macro: macro) {
                            executeMacro(macro)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(height: 44)
            .background(Color(.systemGray6))
        }
        .sheet(isPresented: $showingMacroEditor) {
            MacroEditorView()
        }
        .onReceive(dictationManager.$transcribedText) { text in
            if !text.isEmpty {
                session.sendInput(text)
                dictationManager.transcribedText = ""
            }
        }
    }

    private func macrosForRow(_ row: MacroRow) -> [Macro] {
        switch row {
        case .special:
            return Macro.specialKeys
        case .bash:
            return Macro.bashMacros
        case .git:
            return Macro.gitMacros
        case .claude:
            return Macro.claudeMacros
        case .tmux:
            return Macro.tmuxMacros
        case .custom:
            return macroManager.customMacros
        }
    }

    private func executeMacro(_ macro: Macro) {
        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()

        switch macro.action {
        case .sendText(let text):
            session.sendInput(text)

        case .sendCommand(let command):
            session.sendCommand(command)

        case .specialKey(let key):
            session.sendSpecialKey(key)

        case .composite(let actions):
            for action in actions {
                executeMacroAction(action)
            }

        case .tmuxPrefix:
            session.sendInput(appSettings.tmuxPrefix.sequence)

        case .custom(let handler):
            handler(session)
        }
    }

    private func executeMacroAction(_ action: MacroAction) {
        switch action {
        case .sendText(let text):
            session.sendInput(text)
        case .sendCommand(let command):
            session.sendCommand(command)
        case .specialKey(let key):
            session.sendSpecialKey(key)
        case .tmuxPrefix:
            session.sendInput(appSettings.tmuxPrefix.sequence)
        default:
            break
        }
    }

    private func toggleDictation() {
        if isRecordingDictation {
            dictationManager.stopRecording()
        } else {
            dictationManager.ensureAuthorized()
            dictationManager.startRecording()
        }
        isRecordingDictation.toggle()
    }
}

// MARK: - Row Tab

struct RowTab: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(isActive ? .semibold : .regular))
                .foregroundColor(isActive ? .primary : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isActive ? Color(.systemGray4) : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Macro Button

struct MacroButton: View {
    let macro: Macro
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                if let icon = macro.icon {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                }
                Text(macro.label)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .lineLimit(1)
            }
            .foregroundColor(macro.color ?? .primary)
            .frame(minWidth: 44, minHeight: 32)
            .padding(.horizontal, 8)
            .background(Color(.systemGray5))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Macro Model

struct Macro: Identifiable {
    let id = UUID()
    let label: String
    let icon: String?
    let action: MacroAction
    let color: Color?
    let category: String

    init(label: String, icon: String? = nil, action: MacroAction, color: Color? = nil, category: String = "custom") {
        self.label = label
        self.icon = icon
        self.action = action
        self.color = color
        self.category = category
    }
}

enum MacroAction {
    case sendText(String)
    case sendCommand(String)
    case specialKey(SpecialKey)
    case composite([MacroAction])
    case tmuxPrefix
    case custom((Session) -> Void)
}

// MARK: - Built-in Macro Sets

extension Macro {
    // Special Keys Row
    static let specialKeys: [Macro] = [
        Macro(label: "ENTER", icon: "return", action: .sendText("\r"), color: .green, category: "special"),
        Macro(label: "ESC", icon: "escape", action: .specialKey(.escape), category: "special"),
        Macro(label: "TAB", icon: "arrow.right.to.line", action: .specialKey(.tab), category: "special"),
        Macro(label: "^C", icon: "xmark.circle", action: .specialKey(.ctrlC), color: .red, category: "special"),
        Macro(label: "^D", icon: "arrow.down.to.line", action: .specialKey(.ctrlD), category: "special"),
        Macro(label: "^Z", icon: "pause", action: .specialKey(.ctrlZ), color: .orange, category: "special"),
        Macro(label: "^L", icon: "arrow.counterclockwise", action: .specialKey(.ctrlL), category: "special"),
        Macro(label: "↑", icon: "arrow.up", action: .specialKey(.up), category: "special"),
        Macro(label: "↓", icon: "arrow.down", action: .specialKey(.down), category: "special"),
        Macro(label: "←", icon: "arrow.left", action: .specialKey(.left), category: "special"),
        Macro(label: "→", icon: "arrow.right", action: .specialKey(.right), category: "special"),
        Macro(label: "DEL", icon: "delete.left", action: .sendText("\u{7F}"), category: "special"),
        Macro(label: "HOME", action: .specialKey(.home), category: "special"),
        Macro(label: "END", action: .specialKey(.end), category: "special"),
        Macro(label: "PGUP", action: .specialKey(.pageUp), category: "special"),
        Macro(label: "PGDN", action: .specialKey(.pageDown), category: "special"),
    ]

    // Bash/CLI Macros - Optimized for shell workflows
    static let bashMacros: [Macro] = [
        Macro(label: "sudo !!", icon: "lock.shield", action: .sendCommand("sudo !!"), color: .red, category: "bash"),
        Macro(label: "cd ..", icon: "folder.badge.minus", action: .sendCommand("cd .."), category: "bash"),
        Macro(label: "cd -", icon: "arrow.uturn.left", action: .sendCommand("cd -"), category: "bash"),
        Macro(label: "ls -la", icon: "list.bullet", action: .sendCommand("ls -la"), category: "bash"),
        Macro(label: "pwd", icon: "folder", action: .sendCommand("pwd"), category: "bash"),
        Macro(label: "clear", icon: "trash", action: .sendCommand("clear"), category: "bash"),
        Macro(label: "history", icon: "clock.arrow.circlepath", action: .sendCommand("history"), category: "bash"),
        Macro(label: "!!:p", icon: "doc.text", action: .sendCommand("!!:p"), category: "bash"),
        Macro(label: "$?", icon: "questionmark.circle", action: .sendCommand("echo $?"), category: "bash"),
        Macro(label: "jobs", icon: "list.number", action: .sendCommand("jobs"), category: "bash"),
        Macro(label: "fg", icon: "play.fill", action: .sendCommand("fg"), category: "bash"),
        Macro(label: "bg", icon: "play.circle", action: .sendCommand("bg"), category: "bash"),
        Macro(label: "|grep", icon: "magnifyingglass", action: .sendText(" | grep "), category: "bash"),
        Macro(label: "|less", icon: "text.page", action: .sendText(" | less"), category: "bash"),
        Macro(label: "|head", icon: "arrow.up.doc", action: .sendText(" | head -n "), category: "bash"),
        Macro(label: "|tail", icon: "arrow.down.doc", action: .sendText(" | tail -f "), category: "bash"),
        Macro(label: "|wc -l", icon: "number", action: .sendText(" | wc -l"), category: "bash"),
        Macro(label: "|xargs", icon: "arrow.branch", action: .sendText(" | xargs "), category: "bash"),
        Macro(label: "&&", icon: "link", action: .sendText(" && "), category: "bash"),
        Macro(label: "||", icon: "arrow.triangle.branch", action: .sendText(" || "), category: "bash"),
        Macro(label: "> /dev/null", icon: "trash.slash", action: .sendText(" > /dev/null 2>&1"), category: "bash"),
        Macro(label: "2>&1", icon: "arrow.merge", action: .sendText(" 2>&1"), category: "bash"),
    ]

    // Git Macros
    static let gitMacros: [Macro] = [
        Macro(label: "status", icon: "questionmark.folder", action: .sendCommand("git status"), category: "git"),
        Macro(label: "diff", icon: "plus.forwardslash.minus", action: .sendCommand("git diff"), category: "git"),
        Macro(label: "add .", icon: "plus.circle", action: .sendCommand("git add ."), color: .green, category: "git"),
        Macro(label: "add -p", icon: "plus.circle.fill", action: .sendCommand("git add -p"), color: .green, category: "git"),
        Macro(label: "commit", icon: "checkmark.circle", action: .sendText("git commit -m \""), category: "git"),
        Macro(label: "commit -a", icon: "checkmark.circle.fill", action: .sendText("git commit -am \""), category: "git"),
        Macro(label: "push", icon: "arrow.up.circle", action: .sendCommand("git push"), color: .blue, category: "git"),
        Macro(label: "pull", icon: "arrow.down.circle", action: .sendCommand("git pull"), category: "git"),
        Macro(label: "fetch", icon: "arrow.down.doc", action: .sendCommand("git fetch --all"), category: "git"),
        Macro(label: "log", icon: "clock", action: .sendCommand("git log --oneline -20"), category: "git"),
        Macro(label: "branch", icon: "arrow.triangle.branch", action: .sendCommand("git branch -a"), category: "git"),
        Macro(label: "checkout", icon: "arrow.left.arrow.right", action: .sendText("git checkout "), category: "git"),
        Macro(label: "stash", icon: "archivebox", action: .sendCommand("git stash"), color: .orange, category: "git"),
        Macro(label: "stash pop", icon: "archivebox.fill", action: .sendCommand("git stash pop"), color: .orange, category: "git"),
        Macro(label: "reset HEAD", icon: "arrow.uturn.backward", action: .sendCommand("git reset HEAD"), color: .red, category: "git"),
        Macro(label: "rebase -i", icon: "arrow.3.trianglepath", action: .sendText("git rebase -i "), category: "git"),
    ]

    // Claude Code Macros - Optimized for Claude Code workflows
    static let claudeMacros: [Macro] = [
        // Session Management
        Macro(label: "claude", icon: "bubble.left.and.bubble.right", action: .sendCommand("claude"), color: .purple, category: "claude"),
        Macro(label: "claude -c", icon: "arrow.clockwise", action: .sendCommand("claude -c"), color: .purple, category: "claude"),
        Macro(label: "unlock", icon: "lock.open", action: .sendCommand("security unlock-keychain"), color: .orange, category: "claude"),
        Macro(label: "/login", icon: "person.badge.key", action: .sendCommand("/login"), color: .green, category: "claude"),
        Macro(label: "/exit", icon: "xmark.circle", action: .sendCommand("/exit"), category: "claude"),
        Macro(label: "/clear", icon: "trash", action: .sendCommand("/clear"), category: "claude"),

        // Editing Commands
        Macro(label: "/edit", icon: "pencil", action: .sendText("/edit "), category: "claude"),
        Macro(label: "/vim", icon: "doc.text", action: .sendText("/vim "), category: "claude"),

        // Context Commands
        Macro(label: "/add", icon: "plus.doc", action: .sendText("/add "), category: "claude"),
        Macro(label: "/context", icon: "doc.on.doc", action: .sendCommand("/context"), category: "claude"),
        Macro(label: "/compact", icon: "rectangle.compress.vertical", action: .sendCommand("/compact"), category: "claude"),

        // Task Management
        Macro(label: "/todo", icon: "checklist", action: .sendCommand("/todo"), category: "claude"),
        Macro(label: "/status", icon: "info.circle", action: .sendCommand("/status"), category: "claude"),

        // MCP & Tools
        Macro(label: "/mcp", icon: "network", action: .sendCommand("/mcp"), category: "claude"),
        Macro(label: "/tools", icon: "wrench.and.screwdriver", action: .sendCommand("/tools"), category: "claude"),

        // Help & Config
        Macro(label: "/help", icon: "questionmark.circle", action: .sendCommand("/help"), category: "claude"),
        Macro(label: "/config", icon: "gear", action: .sendCommand("/config"), category: "claude"),

        // Common Prompts
        Macro(label: "explain", icon: "text.bubble", action: .sendText("Please explain "), category: "claude"),
        Macro(label: "fix", icon: "wrench", action: .sendText("Please fix "), category: "claude"),
        Macro(label: "test", icon: "checkmark.seal", action: .sendText("Please write tests for "), category: "claude"),
        Macro(label: "refactor", icon: "arrow.triangle.2.circlepath", action: .sendText("Please refactor "), category: "claude"),
        Macro(label: "review", icon: "eye", action: .sendText("Please review "), category: "claude"),
    ]

    // Tmux Macros
    static let tmuxMacros: [Macro] = [
        Macro(label: "PREFIX", icon: "command", action: .tmuxPrefix, color: .blue, category: "tmux"),
        Macro(label: "new-win", icon: "plus.square", action: .sendCommand("tmux new-window"), category: "tmux"),
        Macro(label: "prev", icon: "chevron.left", action: .sendCommand("tmux previous-window"), category: "tmux"),
        Macro(label: "next", icon: "chevron.right", action: .sendCommand("tmux next-window"), category: "tmux"),
        Macro(label: "split-h", icon: "square.split.2x1", action: .sendCommand("tmux split-window -h"), category: "tmux"),
        Macro(label: "split-v", icon: "square.split.1x2", action: .sendCommand("tmux split-window -v"), category: "tmux"),
        Macro(label: "pane ←", icon: "arrow.left.square", action: .sendCommand("tmux select-pane -L"), category: "tmux"),
        Macro(label: "pane →", icon: "arrow.right.square", action: .sendCommand("tmux select-pane -R"), category: "tmux"),
        Macro(label: "pane ↑", icon: "arrow.up.square", action: .sendCommand("tmux select-pane -U"), category: "tmux"),
        Macro(label: "pane ↓", icon: "arrow.down.square", action: .sendCommand("tmux select-pane -D"), category: "tmux"),
        Macro(label: "zoom", icon: "arrow.up.left.and.arrow.down.right", action: .sendCommand("tmux resize-pane -Z"), category: "tmux"),
        Macro(label: "rename", icon: "pencil", action: .sendText("tmux rename-window "), category: "tmux"),
        Macro(label: "list", icon: "list.bullet", action: .sendCommand("tmux list-sessions"), category: "tmux"),
        Macro(label: "detach", icon: "arrow.right.square", action: .sendCommand("tmux detach"), color: .orange, category: "tmux"),
        Macro(label: "kill-pane", icon: "xmark.square", action: .sendCommand("tmux kill-pane"), color: .red, category: "tmux"),
        Macro(label: "copy-mode", icon: "doc.on.clipboard", action: .composite([.tmuxPrefix, .sendText("[")]), category: "tmux"),
        Macro(label: "paste", icon: "doc.on.doc.fill", action: .composite([.tmuxPrefix, .sendText("]")]), category: "tmux"),
    ]
}

#Preview {
    MacroKeyboard(session: Session(host: Host(hostname: "localhost", username: "user")))
        .environmentObject(AppSettings.shared)
}

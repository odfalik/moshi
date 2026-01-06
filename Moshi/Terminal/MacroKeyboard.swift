import SwiftUI

// MARK: - Modifier State

class ModifierState: ObservableObject {
    static let shared = ModifierState()

    @Published var ctrl = false
    @Published var shift = false
    @Published var alt = false

    var hasActiveModifier: Bool {
        ctrl || shift || alt
    }

    func reset() {
        ctrl = false
        shift = false
        alt = false
    }

    /// Returns the CSI modifier parameter (1-based, bit-encoded)
    /// Shift=1, Alt=2, Ctrl=4 -> parameter = 1 + sum of active bits
    var modifierParam: Int {
        var param = 0
        if shift { param |= 1 }
        if alt { param |= 2 }
        if ctrl { param |= 4 }
        return param + 1  // CSI uses 1-based encoding
    }

    /// Apply modifiers to a character and return the modified string
    func applyToCharacter(_ char: String) -> String {
        guard let firstChar = char.lowercased().first else { return char }

        var result = char

        if ctrl {
            // Ctrl+letter sends control character (Ctrl+A = 0x01, Ctrl+C = 0x03, etc.)
            if let ascii = firstChar.asciiValue, ascii >= 97 && ascii <= 122 {
                let controlCode = ascii - 96  // 'a' is 97, Ctrl+A is 1
                result = String(UnicodeScalar(controlCode))
            }
        } else if shift {
            result = char.uppercased()
        }

        // Alt typically sends ESC prefix
        if alt {
            result = "\u{1B}" + result
        }

        reset()
        return result
    }
}

struct MacroKeyboard: View {
    @ObservedObject var session: Session
    @EnvironmentObject var appSettings: AppSettings
    @StateObject private var macroManager = MacroManager.shared
    @ObservedObject private var modifiers = ModifierState.shared

    @State private var activeRow: MacroRow = .special
    @State private var showingMacroEditor = false

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
            // Combined control + row selector bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // Modifier toggles
                    CompactModifier(label: "^", isActive: $modifiers.ctrl)
                    CompactModifier(label: "⇧", isActive: $modifiers.shift)
                    CompactModifier(label: "⌥", isActive: $modifiers.alt)

                    Divider().frame(height: 20)

                    // Quick keys
                    CompactKey(label: "esc") { sendKey(.escape) }
                    CompactKey(label: "tab") { sendKey(.tab) }

                    Divider().frame(height: 20)

                    // Arrows
                    CompactArrow(icon: "chevron.left") { sendArrow("D") }
                    VStack(spacing: 0) {
                        CompactArrow(icon: "chevron.up") { sendArrow("A") }
                        CompactArrow(icon: "chevron.down") { sendArrow("B") }
                    }
                    CompactArrow(icon: "chevron.right") { sendArrow("C") }

                    Divider().frame(height: 20)

                    // Row tabs
                    ForEach(MacroRow.allCases, id: \.self) { row in
                        RowTab(title: row.rawValue, isActive: activeRow == row) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                activeRow = row
                            }
                        }
                    }

                    Spacer()

                    // Edit macros button
                    Button {
                        showingMacroEditor = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .frame(height: 36)
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
                .padding(.vertical, 4)
            }
            .frame(height: 36)
            .background(Color(.systemGray6))
        }
        .sheet(isPresented: $showingMacroEditor) {
            MacroEditorView()
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

    private func sendArrow(_ code: String) {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()

        let sequence: String
        if modifiers.hasActiveModifier {
            sequence = "\u{1B}[1;\(modifiers.modifierParam)\(code)"
            modifiers.reset()
        } else {
            sequence = "\u{1B}[\(code)"
        }
        session.sendInput(sequence)
    }

    private func sendKey(_ key: SpecialKey) {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        session.sendSpecialKey(key)
        modifiers.reset()
    }
}

// MARK: - Compact Modifier Button

struct CompactModifier: View {
    let label: String
    @Binding var isActive: Bool

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            isActive.toggle()
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isActive ? .white : .primary)
                .frame(width: 28, height: 28)
                .background(isActive ? Color.accentColor : Color(.systemGray4))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compact Key Button

struct CompactKey: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)
                .frame(height: 28)
                .padding(.horizontal, 6)
                .background(Color(.systemGray4))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compact Arrow Button

struct CompactArrow: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.primary)
                .frame(width: 24, height: 14)
                .background(Color(.systemGray4))
                .cornerRadius(3)
        }
        .buttonStyle(.plain)
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
        Macro(label: "S-TAB", icon: "arrow.left.to.line", action: .sendText("\u{1B}[Z"), color: .blue, category: "claude"),
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

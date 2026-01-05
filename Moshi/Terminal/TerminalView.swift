import SwiftUI
import Combine

struct TerminalView: View {
    @ObservedObject var session: Session
    @EnvironmentObject var appSettings: AppSettings

    @StateObject private var emulator = TerminalEmulator()
    @State private var showingMacroKeyboard = true
    @State private var showingTmuxBar = true
    @State private var inputText = ""
    @State private var keyboardHeight: CGFloat = 0
    @State private var lastProcessedLength: Int = 0

    @FocusState private var isInputFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Tmux status bar
                if showingTmuxBar, let tmuxSession = session.tmuxSession {
                    TmuxStatusBar(session: session, tmuxSession: tmuxSession)
                }

                // Terminal content
                TerminalRenderer(
                    emulator: emulator,
                    theme: appSettings.currentTheme,
                    font: appSettings.terminalFont
                )
                .onTapGesture {
                    isInputFocused = true
                }
                .gesture(
                    DragGesture()
                        .onEnded { value in
                            handleSwipe(value)
                        }
                )

                // Hidden text input for keyboard
                HiddenInput(
                    text: $inputText,
                    isFocused: $isInputFocused,
                    onTextInput: { text in
                        session.sendInput(text)
                    },
                    onSpecialKey: { key in
                        session.sendSpecialKey(key)
                    }
                )
                .frame(height: 0)

                // Macro keyboard bar
                if showingMacroKeyboard {
                    MacroKeyboard(session: session)
                        .transition(.move(edge: .bottom))
                }
            }
            .background(appSettings.currentTheme.swiftUIBackground)
            .onChange(of: session.terminalOutput) { _, newOutput in
                // Only process new content, not the entire buffer
                if newOutput.count > lastProcessedLength {
                    let startIndex = newOutput.index(newOutput.startIndex, offsetBy: lastProcessedLength)
                    let newContent = String(newOutput[startIndex...])
                    emulator.processOutput(newContent)
                    lastProcessedLength = newOutput.count
                }
            }
            .onAppear {
                isInputFocused = true
                updateTerminalSize(geometry.size)
            }
            .onChange(of: geometry.size) { _, newSize in
                updateTerminalSize(newSize)
            }
            .onChange(of: session.state) { _, newState in
                // Re-send terminal size when connection is established
                if case .connected = newState {
                    Logger.terminal.debug("Connection established, re-sending terminal size")
                    // Small delay to ensure shell is ready
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        updateTerminalSize(geometry.size)
                    }
                }
            }
            .toolbar {
                terminalToolbar
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var terminalToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            ConnectionStatusView(state: session.state, tmuxStatus: session.tmuxStatus)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button {
                    session.splitTmuxPane(horizontal: true)
                } label: {
                    Label("Split Horizontal", systemImage: "square.split.2x1")
                }

                Button {
                    session.splitTmuxPane(horizontal: false)
                } label: {
                    Label("Split Vertical", systemImage: "square.split.1x2")
                }

                Divider()

                Button {
                    Task { try? await session.createTmuxWindow() }
                } label: {
                    Label("New Window", systemImage: "plus.square")
                }
            } label: {
                Image(systemName: "square.split.2x2")
            }

            Button {
                showingMacroKeyboard.toggle()
            } label: {
                Image(systemName: showingMacroKeyboard ? "keyboard.fill" : "keyboard")
            }

            Menu {
                Button {
                    session.disconnect()
                } label: {
                    Label("Disconnect", systemImage: "pause.circle")
                }

                Button(role: .destructive) {
                    Task { await session.close() }
                } label: {
                    Label("Close Session", systemImage: "xmark.circle")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - Gesture Handling

    private func handleSwipe(_ gesture: DragGesture.Value) {
        let horizontal = gesture.translation.width
        let vertical = gesture.translation.height

        if abs(horizontal) > abs(vertical) {
            // Horizontal swipe - switch tmux windows
            if horizontal > 50 {
                session.sendCommand("tmux previous-window")
            } else if horizontal < -50 {
                session.sendCommand("tmux next-window")
            }
        } else {
            // Vertical swipe - scroll
            if vertical > 50 {
                session.sendSpecialKey(.pageUp)
            } else if vertical < -50 {
                session.sendSpecialKey(.pageDown)
            }
        }
    }

    private func updateTerminalSize(_ size: CGSize) {
        let charWidth = appSettings.terminalFont.characterWidth
        let charHeight = appSettings.terminalFont.lineHeight

        // Account for safe areas and UI elements
        let macroKeyboardHeight: CGFloat = showingMacroKeyboard ? 120 : 0  // Increased from 50
        let tmuxBarHeight: CGFloat = showingTmuxBar ? 30 : 0
        let toolbarHeight: CGFloat = 44  // Navigation bar

        let availableWidth = size.width - 8  // Small horizontal padding
        let availableHeight = size.height - macroKeyboardHeight - tmuxBarHeight - toolbarHeight

        let cols = max(20, Int(availableWidth / charWidth))
        let rows = max(5, Int(availableHeight / charHeight))

        Logger.terminal.debug("Terminal size: \(cols)x\(rows) (width: \(size.width), charWidth: \(charWidth))")

        emulator.resize(cols: cols, rows: rows)
        session.resize(cols: cols, rows: rows)
    }
}

// MARK: - Connection Status View

struct ConnectionStatusView: View {
    let state: ConnectionState
    var tmuxStatus: TmuxStatus = .unknown

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.color)
                .frame(width: 8, height: 8)

            if state.isConnecting {
                ProgressView()
                    .scaleEffect(0.7)
            }

            Text(state.displayName)
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Show tmux status if connected and not unknown/disabled
            if case .connected = state,
               tmuxStatus != .unknown && tmuxStatus != .disabled {
                Divider()
                    .frame(height: 14)
                Image(systemName: tmuxStatus.icon)
                    .font(.caption)
                    .foregroundColor(tmuxStatus.color)
            }
        }
    }
}

// MARK: - Tmux Status Bar

struct TmuxStatusBar: View {
    @ObservedObject var session: Session
    let tmuxSession: TmuxSession

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(tmuxSession.windows) { window in
                    TmuxWindowTab(
                        window: window,
                        isActive: window.isActive
                    ) {
                        session.switchTmuxWindow(window.index)
                    }
                }

                Button {
                    Task { try? await session.createTmuxWindow() }
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 30)
        .background(Color(.systemGray6))
    }
}

struct TmuxWindowTab: View {
    let window: TmuxWindow
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text("\(window.index)")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text(window.name)
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(isActive ? Color.accentColor.opacity(0.2) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Hidden Input

struct HiddenInput: UIViewRepresentable {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let onTextInput: (String) -> Void
    let onSpecialKey: (SpecialKey) -> Void

    func makeUIView(context: Context) -> UITextField {
        let textField = TerminalTextField()
        textField.delegate = context.coordinator
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.smartQuotesType = .no
        textField.smartDashesType = .no
        textField.smartInsertDeleteType = .no
        textField.keyboardType = .asciiCapable
        textField.returnKeyType = .default
        textField.onSpecialKey = onSpecialKey
        textField.onTextInput = onTextInput

        // Become first responder on next run loop to ensure view is in hierarchy
        DispatchQueue.main.async {
            textField.becomeFirstResponder()
        }

        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        uiView.text = text
        // Update callbacks in case they changed
        if let terminalField = uiView as? TerminalTextField {
            terminalField.onSpecialKey = onSpecialKey
            terminalField.onTextInput = onTextInput
        }
        // Always try to become first responder when focused
        if isFocused && !uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        let parent: HiddenInput

        init(_ parent: HiddenInput) {
            self.parent = parent
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            if !string.isEmpty {
                // Send the text directly instead of relying on binding update
                parent.onTextInput(string)
                return false
            }
            return true
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            // Enter key sends newline/carriage return
            parent.onTextInput("\r")
            return false
        }
    }
}

class TerminalTextField: UITextField {
    var onSpecialKey: ((SpecialKey) -> Void)?
    var onTextInput: ((String) -> Void)?

    override var keyCommands: [UIKeyCommand]? {
        var commands: [UIKeyCommand] = []

        // Control key combinations
        for char in "abcdefghijklmnopqrstuvwxyz" {
            commands.append(
                UIKeyCommand(
                    input: String(char),
                    modifierFlags: .control,
                    action: #selector(handleControlKey(_:))
                )
            )
        }

        // Arrow keys
        commands.append(contentsOf: [
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(handleArrowKey(_:))),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(handleArrowKey(_:))),
            UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [], action: #selector(handleArrowKey(_:))),
            UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(handleArrowKey(_:))),
        ])

        // Function keys
        commands.append(UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(handleEscape)))

        return commands
    }

    @objc private func handleControlKey(_ command: UIKeyCommand) {
        guard let input = command.input?.lowercased().first,
              let asciiValue = input.asciiValue else { return }

        switch input {
        case "c": onSpecialKey?(.ctrlC)
        case "d": onSpecialKey?(.ctrlD)
        case "z": onSpecialKey?(.ctrlZ)
        case "l": onSpecialKey?(.ctrlL)
        default:
            // Send raw control character (Ctrl+A = 0x01, Ctrl+B = 0x02, etc.)
            let controlCode = asciiValue - 96  // 'a' is 97, Ctrl+A is 1
            let scalar = UnicodeScalar(controlCode)
            let controlChar = String(Character(scalar))
            onTextInput?(controlChar)
        }
    }

    @objc private func handleArrowKey(_ command: UIKeyCommand) {
        switch command.input {
        case UIKeyCommand.inputUpArrow: onSpecialKey?(.up)
        case UIKeyCommand.inputDownArrow: onSpecialKey?(.down)
        case UIKeyCommand.inputLeftArrow: onSpecialKey?(.left)
        case UIKeyCommand.inputRightArrow: onSpecialKey?(.right)
        default: break
        }
    }

    @objc private func handleEscape() {
        onSpecialKey?(.escape)
    }
}

#Preview {
    NavigationStack {
        TerminalView(session: Session(host: Host(name: "Test", hostname: "localhost", username: "user")))
            .environmentObject(AppSettings.shared)
    }
}

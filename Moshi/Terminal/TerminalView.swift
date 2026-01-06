import SwiftUI
import Combine

struct TerminalView: View {
    @ObservedObject var session: Session
    @EnvironmentObject var appSettings: AppSettings

    @StateObject private var emulator = TerminalEmulator()
    @StateObject private var keyboardObserver = KeyboardObserver()
    @State private var showingMacroKeyboard = true
    @State private var showingTmuxBar = true
    @State private var inputText = ""
    @State private var lastProcessedLength: Int = 0
    @State private var terminalHeight: CGFloat = 0


    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Main content
                VStack(spacing: 0) {
                    // Tmux status bar
                    if showingTmuxBar, let tmuxSession = session.tmuxSession {
                        TmuxStatusBar(session: session, tmuxSession: tmuxSession)
                    }

                    // Terminal content - constrained to exact terminal height
                    TerminalRenderer(
                        emulator: emulator,
                        theme: appSettings.currentTheme,
                        font: appSettings.terminalFont,
                        onTap: {
                            NotificationCenter.default.post(name: .terminalFocusKeyboard, object: nil)
                        }
                    )
                    .frame(height: terminalHeight > 0 ? terminalHeight : nil)
                    .gesture(
                        DragGesture()
                            .onEnded { value in
                                handleSwipe(value)
                            }
                    )

                    Spacer(minLength: 0)

                    // Hidden text input for keyboard
                    HiddenInput(
                        text: $inputText,
                        onTextInput: { text in
                            // Apply any active modifiers from the macro keyboard
                            let modifiers = ModifierState.shared
                            if modifiers.hasActiveModifier {
                                session.sendInput(modifiers.applyToCharacter(text))
                            } else {
                                session.sendInput(text)
                            }
                        },
                        onSpecialKey: { key in
                            session.sendSpecialKey(key)
                        }
                    )
                    .frame(height: 0)
                }

                // Macro keyboard overlaid at bottom, positioned above iOS keyboard
                if showingMacroKeyboard && keyboardObserver.isKeyboardVisible {
                    MacroKeyboard(session: session)
                        .environmentObject(appSettings)
                        .padding(.bottom, keyboardObserver.keyboardHeight)
                }
            }
            .ignoresSafeArea(.keyboard) // We handle keyboard positioning manually
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
                // Focus keyboard after a short delay to ensure view is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NotificationCenter.default.post(name: .terminalFocusKeyboard, object: nil)
                }
                updateTerminalSize(geometry.size)
            }
            .onChange(of: geometry.size) { _, newSize in
                updateTerminalSize(newSize)
            }
            .onChange(of: keyboardObserver.isKeyboardVisible) { _, _ in
                updateTerminalSize(geometry.size)
            }
            .onChange(of: keyboardObserver.keyboardHeight) { _, _ in
                updateTerminalSize(geometry.size)
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
                if !showingMacroKeyboard {
                    // Dismiss iOS keyboard when hiding macro keyboard
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                } else {
                    // Re-focus keyboard when showing macro keyboard
                    NotificationCenter.default.post(name: .terminalFocusKeyboard, object: nil)
                }
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

        // Account for UI elements
        let tmuxBarHeight: CGFloat = showingTmuxBar ? 30 : 0
        // Only subtract macro keyboard height (72px) when keyboard is visible
        // The iOS keyboard height is handled by ignoresSafeArea(.keyboard) + our overlay positioning
        let overlayHeight: CGFloat = (showingMacroKeyboard && keyboardObserver.isKeyboardVisible) ? 72 : 0

        let availableWidth = size.width - 8  // Small horizontal padding
        let availableHeight = size.height - tmuxBarHeight - overlayHeight

        let cols = max(20, Int(availableWidth / charWidth))
        let rows = max(5, Int(availableHeight / charHeight))

        // Set exact terminal view height to match calculated rows
        let newTerminalHeight = CGFloat(rows) * charHeight

        Logger.terminal.debug("Terminal size: \(cols)x\(rows) geometry=\(size.height) available=\(availableHeight) termHeight=\(newTerminalHeight)")

        terminalHeight = newTerminalHeight
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

        // Disable inline predictions (iOS 17+)
        if #available(iOS 17.0, *) {
            textField.inlinePredictionType = .no
        }

        // Disable the keyboard's input assistant (toolbar with globe, mic, emoji)
        textField.inputAssistantItem.leadingBarButtonGroups = []
        textField.inputAssistantItem.trailingBarButtonGroups = []

        textField.onSpecialKey = onSpecialKey
        textField.onTextInput = onTextInput

        // Store reference in coordinator for focus management
        context.coordinator.textField = textField

        // Listen for focus notifications
        context.coordinator.observeFocusNotification()

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
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        let parent: HiddenInput
        weak var textField: UITextField?
        private var focusObserver: NSObjectProtocol?

        init(_ parent: HiddenInput) {
            self.parent = parent
        }

        deinit {
            if let observer = focusObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func observeFocusNotification() {
            focusObserver = NotificationCenter.default.addObserver(
                forName: .terminalFocusKeyboard,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.textField?.becomeFirstResponder()
            }
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

    override func deleteBackward() {
        // Send backspace character (0x7F) to the terminal instead of letting iOS handle it
        onTextInput?("\u{7F}")
    }
}

#Preview {
    NavigationStack {
        TerminalView(session: Session(host: Host(name: "Test", hostname: "localhost", username: "user")))
            .environmentObject(AppSettings.shared)
    }
}

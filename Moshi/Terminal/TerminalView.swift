import SwiftUI
import Combine

struct TerminalView: View {
    @ObservedObject var session: Session
    @EnvironmentObject var appSettings: AppSettings

    @StateObject private var emulator = TerminalEmulator()
    @StateObject private var keyboardObserver = KeyboardObserver()
    @State private var showingMacroKeyboard = true
    @State private var showingTmuxBar = false  // Disabled - tmux windows managed via swipe gestures
    @State private var lastProcessedLength: Int = 0
    @State private var lastOutputRevision: Int = 0


    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Main content
                VStack(spacing: 0) {
                    // Tmux status bar
                    if showingTmuxBar, let tmuxSession = session.tmuxSession {
                        TmuxStatusBar(session: session, tmuxSession: tmuxSession)
                    }

                    // Terminal content - fills available space
                    TerminalRenderer(
                        emulator: emulator,
                        theme: appSettings.currentTheme,
                        font: appSettings.terminalFont,
                        onTap: {
                            NotificationCenter.default.post(name: .terminalFocusKeyboard, object: nil)
                        }
                    )
                    .frame(maxHeight: .infinity)

                    // Hidden input for keyboard
                    HiddenInput(
                        onTextInput: { text in
                            session.sendInput(text)
                        },
                        onSpecialKey: { key in
                            session.sendSpecialKey(key)
                        }
                    )
                    .frame(height: 1)  // Needs minimal height for keyboard
                }

                // Macro keyboard overlaid at bottom, positioned above iOS keyboard
                if showingMacroKeyboard && keyboardObserver.isKeyboardVisible {
                    VStack(spacing: 0) {
                        Spacer()
                        MacroKeyboard(session: session)
                            .environmentObject(appSettings)
                        // Fill the space behind the iOS keyboard with matching color
                        Color(.systemGray6)
                            .frame(height: keyboardObserver.keyboardHeight)
                    }
                    .ignoresSafeArea(.keyboard)
                }
            }
            .ignoresSafeArea(.keyboard) // We handle keyboard positioning manually
            .background(appSettings.currentTheme.swiftUIBackground)
            .onChange(of: session.terminalOutput) { _, newOutput in
                // Check if output was replaced (not appended) - handle reconnect
                let wasReplaced = session.outputRevision != lastOutputRevision
                if wasReplaced {
                    lastOutputRevision = session.outputRevision
                    emulator.reset()
                    lastProcessedLength = 0

                    // Suppress rendering while tmux redraws (300ms)
                    emulator.suppressRendering = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak emulator] in
                        emulator?.suppressRendering = false
                        emulator?.flushRender()
                    }
                }

                // Process new content
                if newOutput.count > lastProcessedLength {
                    let startIndex = newOutput.index(newOutput.startIndex, offsetBy: lastProcessedLength)
                    let newContent = String(newOutput[startIndex...])
                    emulator.processOutput(newContent)
                    lastProcessedLength = newOutput.count
                }
            }
            .onAppear {
                // Check if outputRevision changed (handles reconnect case)
                if session.outputRevision != lastOutputRevision {
                    lastOutputRevision = session.outputRevision
                    emulator.reset()
                    lastProcessedLength = 0
                }

                // Process any existing terminal output immediately (for reconnects)
                if !session.terminalOutput.isEmpty && lastProcessedLength == 0 {
                    emulator.processOutput(session.terminalOutput)
                    lastProcessedLength = session.terminalOutput.count
                }

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

        // Account for UI elements - macro keyboard is 72px when visible
        let overlayHeight: CGFloat = (showingMacroKeyboard && keyboardObserver.isKeyboardVisible) ? 72 : 0

        let availableWidth = size.width
        let availableHeight = size.height - overlayHeight

        let cols = max(20, Int(availableWidth / charWidth))
        let rows = max(5, Int(availableHeight / charHeight))

        Logger.terminal.debug("Terminal size: \(cols)x\(rows) geometry=\(size.height) available=\(availableHeight)")

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
    let onTextInput: (String) -> Void
    let onSpecialKey: (SpecialKey) -> Void

    func makeUIView(context: Context) -> TerminalInputView {
        let inputView = TerminalInputView(frame: .zero, textContainer: nil)
        inputView.onSpecialKey = onSpecialKey
        inputView.onTextInput = onTextInput

        // Store reference in coordinator for focus management
        context.coordinator.inputView = inputView

        // Listen for focus notifications
        context.coordinator.observeFocusNotification()

        // Listen for paste notifications from terminal text view
        context.coordinator.observePasteNotification()

        // Become first responder on next run loop to ensure view is in hierarchy
        DispatchQueue.main.async {
            inputView.becomeFirstResponder()
        }

        return inputView
    }

    func updateUIView(_ uiView: TerminalInputView, context: Context) {
        uiView.onSpecialKey = onSpecialKey
        uiView.onTextInput = onTextInput
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        let parent: HiddenInput
        weak var inputView: TerminalInputView?
        private var focusObserver: NSObjectProtocol?
        private var pasteObserver: NSObjectProtocol?

        init(_ parent: HiddenInput) {
            self.parent = parent
        }

        deinit {
            if let observer = focusObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = pasteObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func observeFocusNotification() {
            focusObserver = NotificationCenter.default.addObserver(
                forName: .terminalFocusKeyboard,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.inputView?.becomeFirstResponder()
            }
        }

        func observePasteNotification() {
            pasteObserver = NotificationCenter.default.addObserver(
                forName: .terminalPaste,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                if let text = notification.userInfo?["text"] as? String {
                    self?.parent.onTextInput(text)
                }
            }
        }
    }
}

/// UITextView-based input that preserves iOS backspace key repeat
class TerminalInputView: UITextView, UITextViewDelegate {
    var onSpecialKey: ((SpecialKey) -> Void)?
    var onTextInput: ((String) -> Void)?

    private var previousLength = 0
    private var isRefilling = false
    private let bufferSize = 1000

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        delegate = self
        autocorrectionType = .no
        autocapitalizationType = .none
        spellCheckingType = .no
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        keyboardType = .asciiCapable
        returnKeyType = .default

        // Make text invisible but view functional
        textColor = .clear
        tintColor = .clear
        backgroundColor = .clear

        // Disable input assistant bar
        inputAssistantItem.leadingBarButtonGroups = []
        inputAssistantItem.trailingBarButtonGroups = []

        if #available(iOS 17.0, *) {
            inlinePredictionType = .no
        }

        refillBuffer()
    }

    private func refillBuffer() {
        isRefilling = true
        text = String(repeating: " ", count: bufferSize)
        previousLength = bufferSize
        selectedRange = NSRange(location: bufferSize, length: 0)
        isRefilling = false
    }

    // MARK: - UITextViewDelegate

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text.isEmpty {
            // Deletion - let iOS handle it naturally (preserves key repeat)
            // We'll detect and handle it in textViewDidChange
            return true
        } else {
            // Insertion - intercept and send to terminal
            if text == "\n" {
                onTextInput?("\r")
            } else {
                let modifiers = ModifierState.shared
                if modifiers.hasActiveModifier {
                    onTextInput?(modifiers.applyToCharacter(text))
                } else {
                    onTextInput?(text)
                }
            }
            return false  // Don't add to text view
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        guard !isRefilling else { return }

        let newLength = textView.text?.count ?? 0

        // Detect deletions and send backspaces
        if newLength < previousLength {
            let deleteCount = previousLength - newLength
            for _ in 0..<deleteCount {
                onTextInput?("\u{7F}")
            }
        }

        previousLength = newLength

        // Refill buffer when running low
        if newLength < 100 {
            refillBuffer()
        }
    }

    // MARK: - Key Commands (hardware keyboard)

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

        // Escape
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
            let controlCode = asciiValue - 96
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

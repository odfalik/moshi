import SwiftUI

struct TerminalRenderer: View {
    @ObservedObject var emulator: TerminalEmulator
    let theme: TerminalTheme
    let font: TerminalFont
    var onTap: (() -> Void)? = nil

    @State private var contentSize: CGSize = .zero
    @State private var selectedRange: TerminalSelection?

    /// Get visible lines from the emulator
    /// On alternate screen (fullscreen apps), always returns exactly `rows` lines
    /// On normal screen, render at least up to the cursor row to ensure cursor is visible
    private var visibleLines: [(index: Int, line: TerminalLine)] {
        let start = emulator.screenStart
        let availableLines = emulator.lines.count - start
        // Always render at least up to cursor row + 1 to ensure cursor is visible
        let minLinesToShow = emulator.cursorRow + 1
        let linesToShow = emulator.isAlternateScreen ? emulator.rows : max(minLinesToShow, min(availableLines, emulator.rows))

        return (0..<linesToShow).map { screenRow in
            let lineIndex = start + screenRow
            if lineIndex < emulator.lines.count {
                return (index: screenRow, line: emulator.lines[lineIndex])
            } else {
                // Create empty line for display if buffer doesn't have enough lines
                return (index: screenRow, line: TerminalLine(cells: Array(repeating: TerminalCell(), count: emulator.cols)))
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            // Use a simple VStack without ScrollView to prevent scroll position issues on resize
            // Terminal content always renders from top, no scrolling within the visible area
            VStack(alignment: .leading, spacing: 0) {
                ForEach(visibleLines, id: \.line.id) { item in
                    TerminalLineView(
                        line: item.line,
                        lineIndex: item.index,
                        theme: theme,
                        font: font,
                        cursorCol: item.index == emulator.cursorRow ? emulator.cursorCol : nil,
                        selection: selectedRange
                    )
                }

                // Fill remaining space to push content to top
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(theme.swiftUIBackground)
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        updateSelection(at: value.location, in: geometry.size, isStart: value.translation == .zero)
                    }
                    .onEnded { _ in
                        // Selection persists until user taps or context menu action
                    }
            )
            .onTapGesture {
                // Clear selection on tap
                selectedRange = nil
                // Notify parent (e.g., to show keyboard)
                onTap?()
            }
            .contextMenu {
                if selectedRange != nil {
                    Button {
                        copySelection()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }

                Button {
                    paste()
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }

                Button {
                    selectAll()
                } label: {
                    Label("Select All", systemImage: "selection.pin.in.out")
                }
            }
        }
        .onPreferenceChange(ContentSizeKey.self) { size in
            contentSize = size
        }
    }

    private func updateSelection(at point: CGPoint, in size: CGSize, isStart: Bool = false) {
        // Calculate character position from point
        let charWidth = font.characterWidth
        let charHeight = font.lineHeight

        let col = Int(point.x / charWidth)
        let row = Int(point.y / charHeight)

        // Update selection range
        if selectedRange == nil || isStart {
            selectedRange = TerminalSelection(startRow: row, startCol: col, endRow: row, endCol: col)
        } else {
            selectedRange?.endRow = row
            selectedRange?.endCol = col
        }
    }

    private func copySelection() {
        guard let selection = selectedRange else { return }

        var text = ""
        let visible = visibleLines
        for screenRow in selection.startRow...selection.endRow {
            guard screenRow < visible.count else { continue }

            let line = visible[screenRow].line
            let startCol = screenRow == selection.startRow ? selection.startCol : 0
            let endCol = screenRow == selection.endRow ? selection.endCol : line.cells.count

            for col in startCol..<min(endCol, line.cells.count) {
                text.append(line.cells[col].character)
            }

            if screenRow < selection.endRow && !line.wrapped {
                text.append("\n")
            }
        }

        UIPasteboard.general.string = text.trimmingCharacters(in: .whitespaces)
        selectedRange = nil
    }

    private func paste() {
        if let text = UIPasteboard.general.string {
            // Send text to session
            NotificationCenter.default.post(
                name: .terminalPaste,
                object: nil,
                userInfo: ["text": text]
            )
        }
    }

    private func selectAll() {
        let visible = visibleLines
        selectedRange = TerminalSelection(
            startRow: 0,
            startCol: 0,
            endRow: max(0, visible.count - 1),
            endCol: visible.last?.line.cells.count ?? 0
        )
    }
}

struct TerminalSelection {
    var startRow: Int
    var startCol: Int
    var endRow: Int
    var endCol: Int

    func contains(row: Int, col: Int) -> Bool {
        if row < min(startRow, endRow) || row > max(startRow, endRow) {
            return false
        }

        if startRow == endRow {
            return col >= min(startCol, endCol) && col <= max(startCol, endCol)
        }

        if row == startRow {
            return col >= startCol
        }

        if row == endRow {
            return col <= endCol
        }

        return true
    }
}

struct TerminalLineView: View {
    let line: TerminalLine
    let lineIndex: Int
    let theme: TerminalTheme
    let font: TerminalFont
    let cursorCol: Int?
    let selection: TerminalSelection?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(line.cells.enumerated()), id: \.offset) { colIndex, cell in
                CellView(
                    cell: cell,
                    theme: theme,
                    font: font,
                    isCursor: cursorCol == colIndex,
                    isSelected: selection?.contains(row: lineIndex, col: colIndex) ?? false
                )
            }
        }
        .frame(height: font.uiFont.lineHeight)
    }
}

struct CellView: View {
    let cell: TerminalCell
    let theme: TerminalTheme
    let font: TerminalFont
    let isCursor: Bool
    let isSelected: Bool

    var body: some View {
        Text(String(cell.character))
            .font(font.font)
            .foregroundColor(foregroundColor)
            .frame(width: font.characterWidth)
            .background(backgroundColor)
            .overlay {
                if isCursor {
                    Rectangle()
                        .fill(theme.cursor.color.opacity(0.7))
                }
            }
    }

    private var foregroundColor: Color {
        if cell.attributes.contains(.inverse) {
            return colorFromTerminalColor(cell.background, isBackground: true)
        }
        return colorFromTerminalColor(cell.foreground, isBackground: false)
    }

    private var backgroundColor: Color {
        if isSelected {
            return theme.selection.color
        }
        if cell.attributes.contains(.inverse) {
            return colorFromTerminalColor(cell.foreground, isBackground: false)
        }
        return colorFromTerminalColor(cell.background, isBackground: true)
    }

    private func colorFromTerminalColor(_ color: TerminalColor, isBackground: Bool) -> Color {
        switch color {
        case .default:
            return isBackground ? theme.swiftUIBackground : theme.swiftUIForeground
        case .indexed(let index):
            return theme.colorForIndex(index)
        case .rgb(let r, let g, let b):
            return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
        }
    }
}

// MARK: - Preference Keys

struct ContentSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let terminalPaste = Notification.Name("terminalPaste")
    static let terminalFocusKeyboard = Notification.Name("terminalFocusKeyboard")
}

#Preview {
    let emulator = TerminalEmulator()
    emulator.processOutput("Hello, World!\r\n\u{1B}[32mGreen text\u{1B}[0m")

    return TerminalRenderer(
        emulator: emulator,
        theme: .dracula,
        font: TerminalFont()
    )
}

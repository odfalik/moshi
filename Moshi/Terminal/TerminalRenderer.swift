import SwiftUI

struct TerminalRenderer: View {
    @ObservedObject var emulator: TerminalEmulator
    let theme: TerminalTheme
    let font: TerminalFont

    @State private var contentSize: CGSize = .zero
    @State private var selectedRange: TerminalSelection?

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal], showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(emulator.lines.enumerated()), id: \.offset) { index, line in
                            TerminalLineView(
                                line: line,
                                lineIndex: index,
                                theme: theme,
                                font: font,
                                cursorCol: index == emulator.cursorRow ? emulator.cursorCol : nil,
                                selection: selectedRange
                            )
                            .id(index)
                        }
                    }
                    .background(
                        GeometryReader { contentGeometry in
                            Color.clear.preference(
                                key: ContentSizeKey.self,
                                value: contentGeometry.size
                            )
                        }
                    )
                }
                .onChange(of: emulator.cursorRow) { _, newRow in
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(newRow, anchor: .bottom)
                    }
                }
            }
            .background(theme.swiftUIBackground)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        updateSelection(at: value.location, in: geometry.size)
                    }
                    .onEnded { _ in
                        // Copy selection if any
                    }
            )
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

    private func updateSelection(at point: CGPoint, in size: CGSize) {
        // Calculate character position from point
        let charWidth = font.size * 0.6
        let charHeight = font.uiFont.lineHeight

        let col = Int(point.x / charWidth)
        let row = Int(point.y / charHeight)

        // Update selection range
        if selectedRange == nil {
            selectedRange = TerminalSelection(startRow: row, startCol: col, endRow: row, endCol: col)
        } else {
            selectedRange?.endRow = row
            selectedRange?.endCol = col
        }
    }

    private func copySelection() {
        guard let selection = selectedRange else { return }

        var text = ""
        for row in selection.startRow...selection.endRow {
            guard row < emulator.lines.count else { continue }

            let line = emulator.lines[row]
            let startCol = row == selection.startRow ? selection.startCol : 0
            let endCol = row == selection.endRow ? selection.endCol : line.cells.count

            for col in startCol..<min(endCol, line.cells.count) {
                text.append(line.cells[col].character)
            }

            if row < selection.endRow && !line.wrapped {
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
        selectedRange = TerminalSelection(
            startRow: 0,
            startCol: 0,
            endRow: emulator.lines.count - 1,
            endCol: emulator.lines.last?.cells.count ?? 0
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
            .frame(width: font.size * 0.6)
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

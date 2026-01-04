import Foundation
import Combine

final class TerminalEmulator: ObservableObject {
    @Published var lines: [TerminalLine] = []
    @Published var cursorRow: Int = 0
    @Published var cursorCol: Int = 0
    @Published var scrollOffset: Int = 0

    private var cols: Int = 80
    private var rows: Int = 24
    private var scrollbackLimit: Int = 10000

    private var currentAttributes = CellAttributes()
    private var currentForeground: TerminalColor = .default
    private var currentBackground: TerminalColor = .default

    private var savedCursorRow: Int = 0
    private var savedCursorCol: Int = 0

    private let parser = ANSIParser()
    private var cancellables = Set<AnyCancellable>()

    // Alternate screen buffer (for vim, less, etc.)
    private var alternateBuffer: [TerminalLine] = []
    private var isAlternateScreen = false

    init() {
        initializeBuffer()
    }

    private func initializeBuffer() {
        lines = (0..<rows).map { _ in createEmptyLine() }
    }

    private func createEmptyLine() -> TerminalLine {
        TerminalLine(cells: Array(repeating: TerminalCell(), count: cols))
    }

    func resize(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows

        // Adjust buffer to new size
        while lines.count < rows {
            lines.append(createEmptyLine())
        }

        // Adjust line widths
        for i in 0..<lines.count {
            if lines[i].cells.count < cols {
                lines[i].cells.append(contentsOf: Array(repeating: TerminalCell(), count: cols - lines[i].cells.count))
            } else if lines[i].cells.count > cols {
                lines[i].cells = Array(lines[i].cells.prefix(cols))
            }
        }

        // Clamp cursor
        cursorRow = min(cursorRow, rows - 1)
        cursorCol = min(cursorCol, cols - 1)
    }

    func processOutput(_ output: String) {
        let tokens = parser.parse(output)

        for token in tokens {
            switch token {
            case .text(let text):
                writeText(text)

            case .escape(let sequence):
                handleEscapeSequence(sequence)

            case .controlChar(let char):
                handleControlChar(char)
            }
        }
    }

    // MARK: - Text Output

    private func writeText(_ text: String) {
        for char in text {
            writeCharacter(char)
        }
    }

    private func writeCharacter(_ char: Character) {
        guard cursorRow < lines.count && cursorCol < cols else { return }

        lines[cursorRow].cells[cursorCol] = TerminalCell(
            character: char,
            foreground: currentForeground,
            background: currentBackground,
            attributes: currentAttributes
        )

        cursorCol += 1

        if cursorCol >= cols {
            lines[cursorRow].wrapped = true
            cursorCol = 0
            lineFeed()
        }
    }

    // MARK: - Control Characters

    private func handleControlChar(_ char: Character) {
        switch char {
        case "\n", "\u{0A}": // Line Feed (also resets column in newline mode)
            cursorCol = 0
            lineFeed()

        case "\r", "\u{0D}": // Carriage Return
            cursorCol = 0

        case "\t", "\u{09}": // Tab
            let nextTab = ((cursorCol / 8) + 1) * 8
            cursorCol = min(nextTab, cols - 1)

        case "\u{08}": // Backspace
            if cursorCol > 0 {
                cursorCol -= 1
            }

        case "\u{07}": // Bell
            // Could trigger haptic feedback
            break

        default:
            break
        }
    }

    private func lineFeed() {
        cursorRow += 1

        if cursorRow >= rows {
            // Scroll up - add new line at bottom
            lines.append(createEmptyLine())
            cursorRow = rows - 1

            // Trim scrollback if exceeds limit
            while lines.count > scrollbackLimit {
                lines.removeFirst()
            }
        }
    }

    // MARK: - Escape Sequences

    private func handleEscapeSequence(_ sequence: ANSIParser.EscapeSequence) {
        switch sequence {
        case .cursorUp(let n):
            cursorRow = max(0, cursorRow - n)

        case .cursorDown(let n):
            cursorRow = min(rows - 1, cursorRow + n)

        case .cursorForward(let n):
            cursorCol = min(cols - 1, cursorCol + n)

        case .cursorBack(let n):
            cursorCol = max(0, cursorCol - n)

        case .cursorPosition(let row, let col):
            cursorRow = min(rows - 1, max(0, row - 1))
            cursorCol = min(cols - 1, max(0, col - 1))

        case .cursorHorizontalAbsolute(let col):
            cursorCol = min(cols - 1, max(0, col - 1))

        case .cursorVerticalAbsolute(let row):
            cursorRow = min(rows - 1, max(0, row - 1))

        case .cursorNextLine(let n):
            cursorRow = min(rows - 1, cursorRow + n)
            cursorCol = 0

        case .cursorPreviousLine(let n):
            cursorRow = max(0, cursorRow - n)
            cursorCol = 0

        case .eraseDisplay(let mode):
            eraseDisplay(mode: mode)

        case .eraseLine(let mode):
            eraseLine(mode: mode)

        case .sgr(let params):
            handleSGR(params)

        case .saveCursor:
            savedCursorRow = cursorRow
            savedCursorCol = cursorCol

        case .restoreCursor:
            cursorRow = savedCursorRow
            cursorCol = savedCursorCol

        case .alternateScreenOn:
            if !isAlternateScreen {
                alternateBuffer = lines
                lines = (0..<rows).map { _ in createEmptyLine() }
                isAlternateScreen = true
                cursorRow = 0
                cursorCol = 0
            }

        case .alternateScreenOff:
            if isAlternateScreen {
                lines = alternateBuffer
                alternateBuffer = []
                isAlternateScreen = false
            }

        case .setScrollRegion(let top, let bottom):
            // Handle scroll region (used by tmux, vim, etc.)
            break

        case .insertLines(let n):
            insertLines(n)

        case .deleteLines(let n):
            deleteLines(n)

        case .scrollUp(let n):
            for _ in 0..<n {
                lines.removeFirst()
                lines.append(createEmptyLine())
            }

        case .scrollDown(let n):
            for _ in 0..<n {
                lines.removeLast()
                lines.insert(createEmptyLine(), at: 0)
            }

        case .setTitle(let title):
            // Could update window title
            break

        case .unknown:
            break
        }
    }

    private func eraseDisplay(mode: Int) {
        switch mode {
        case 0: // Cursor to end
            eraseLine(mode: 0)
            for i in (cursorRow + 1)..<rows {
                if i < lines.count {
                    lines[i] = createEmptyLine()
                }
            }

        case 1: // Start to cursor
            for i in 0..<cursorRow {
                if i < lines.count {
                    lines[i] = createEmptyLine()
                }
            }
            eraseLine(mode: 1)

        case 2, 3: // Entire screen
            lines = (0..<rows).map { _ in createEmptyLine() }

        default:
            break
        }
    }

    private func eraseLine(mode: Int) {
        guard cursorRow < lines.count else { return }

        switch mode {
        case 0: // Cursor to end
            for i in cursorCol..<cols {
                if i < lines[cursorRow].cells.count {
                    lines[cursorRow].cells[i] = TerminalCell()
                }
            }

        case 1: // Start to cursor
            for i in 0...cursorCol {
                if i < lines[cursorRow].cells.count {
                    lines[cursorRow].cells[i] = TerminalCell()
                }
            }

        case 2: // Entire line
            lines[cursorRow] = createEmptyLine()

        default:
            break
        }
    }

    private func insertLines(_ n: Int) {
        for _ in 0..<n {
            if cursorRow < lines.count {
                lines.insert(createEmptyLine(), at: cursorRow)
                if lines.count > rows {
                    lines.removeLast()
                }
            }
        }
    }

    private func deleteLines(_ n: Int) {
        for _ in 0..<n {
            if cursorRow < lines.count {
                lines.remove(at: cursorRow)
                lines.append(createEmptyLine())
            }
        }
    }

    // MARK: - SGR (Select Graphic Rendition)

    private func handleSGR(_ params: [Int]) {
        var i = 0
        while i < params.count {
            let param = params[i]

            switch param {
            case 0: // Reset
                currentAttributes = []
                currentForeground = .default
                currentBackground = .default

            case 1: // Bold
                currentAttributes.insert(.bold)

            case 3: // Italic
                currentAttributes.insert(.italic)

            case 4: // Underline
                currentAttributes.insert(.underline)

            case 5, 6: // Blink
                currentAttributes.insert(.blink)

            case 7: // Inverse
                currentAttributes.insert(.inverse)

            case 9: // Strikethrough
                currentAttributes.insert(.strikethrough)

            case 22: // Normal intensity
                currentAttributes.remove(.bold)

            case 23: // Not italic
                currentAttributes.remove(.italic)

            case 24: // Not underlined
                currentAttributes.remove(.underline)

            case 25: // Not blinking
                currentAttributes.remove(.blink)

            case 27: // Not inverse
                currentAttributes.remove(.inverse)

            case 29: // Not strikethrough
                currentAttributes.remove(.strikethrough)

            case 30...37: // Standard foreground colors
                currentForeground = .indexed(param - 30)

            case 38: // Extended foreground color
                if i + 2 < params.count && params[i + 1] == 5 {
                    currentForeground = .indexed(params[i + 2])
                    i += 2
                } else if i + 4 < params.count && params[i + 1] == 2 {
                    currentForeground = .rgb(
                        UInt8(params[i + 2]),
                        UInt8(params[i + 3]),
                        UInt8(params[i + 4])
                    )
                    i += 4
                }

            case 39: // Default foreground
                currentForeground = .default

            case 40...47: // Standard background colors
                currentBackground = .indexed(param - 40)

            case 48: // Extended background color
                if i + 2 < params.count && params[i + 1] == 5 {
                    currentBackground = .indexed(params[i + 2])
                    i += 2
                } else if i + 4 < params.count && params[i + 1] == 2 {
                    currentBackground = .rgb(
                        UInt8(params[i + 2]),
                        UInt8(params[i + 3]),
                        UInt8(params[i + 4])
                    )
                    i += 4
                }

            case 49: // Default background
                currentBackground = .default

            case 90...97: // Bright foreground colors
                currentForeground = .indexed(param - 90 + 8)

            case 100...107: // Bright background colors
                currentBackground = .indexed(param - 100 + 8)

            default:
                break
            }

            i += 1
        }
    }

    // MARK: - Scrollback

    func scrollToTop() {
        scrollOffset = max(0, lines.count - rows)
    }

    func scrollToBottom() {
        scrollOffset = 0
    }

    func scroll(by delta: Int) {
        scrollOffset = max(0, min(lines.count - rows, scrollOffset + delta))
    }

    // MARK: - Buffer Access

    func getVisibleLines() -> ArraySlice<TerminalLine> {
        let start = max(0, lines.count - rows - scrollOffset)
        let end = min(lines.count, start + rows)
        return lines[start..<end]
    }

    func getLine(at index: Int) -> TerminalLine? {
        let actualIndex = lines.count - rows - scrollOffset + index
        guard actualIndex >= 0 && actualIndex < lines.count else { return nil }
        return lines[actualIndex]
    }
}

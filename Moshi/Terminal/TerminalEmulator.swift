import Foundation
import Combine

final class TerminalEmulator: ObservableObject {
    // Use manual change notification to batch updates
    var lines: [TerminalLine] = []
    var cursorRow: Int = 0  // Row within the visible screen (0 to rows-1)
    var cursorCol: Int = 0
    var scrollOffset: Int = 0

    // Adaptive render throttling
    private var lastRenderTime: CFAbsoluteTime = 0
    private var renderWorkItem: DispatchWorkItem?
    private var recentOutputBytes = 0
    private var outputResetWorkItem: DispatchWorkItem?
    private let fastOutputThreshold = 300  // bytes - above this, start throttling
    private let heavyThrottleThreshold = 2000  // bytes - above this, throttle heavily

    /// Suppress rendering briefly after reconnect
    var suppressRendering = false

    private(set) var cols: Int = 80
    private(set) var rows: Int = 24

    // Deferred wrap: cursor is past the right margin but hasn't wrapped yet
    private var pendingWrap: Bool = false

    /// The starting index of the visible screen in the lines array
    var screenStart: Int {
        // Always start from 0 - scrollback can be added later
        // This ensures content always renders from the top
        return 0
    }

    /// Convert a screen-relative row to an actual index in lines array
    /// Creates lines if needed to ensure the row exists
    private func lineIndex(for screenRow: Int) -> Int {
        let targetIndex = screenStart + screenRow

        if isAlternateScreen {
            // On alternate screen, ensure we have exactly `rows` lines but never more
            while lines.count < rows {
                lines.append(createEmptyLine())
            }
            // Clamp to valid range - never grow beyond rows on alternate screen
            return min(targetIndex, rows - 1)
        } else {
            // Normal screen: create lines as needed
            while lines.count <= targetIndex {
                lines.append(createEmptyLine())
            }
            return targetIndex
        }
    }
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
    private(set) var isAlternateScreen = false

    // Scroll region (1-indexed in ANSI, 0-indexed internally)
    // Default is entire screen (0 to rows-1)
    private var scrollRegionTop: Int = 0
    private var scrollRegionBottom: Int = 23  // Will be updated on resize

    init() {
        initializeBuffer()
    }

    private func initializeBuffer() {
        lines = (0..<rows).map { _ in createEmptyLine() }
        scrollRegionTop = 0
        scrollRegionBottom = rows - 1
    }

    private func createEmptyLine() -> TerminalLine {
        TerminalLine(cells: Array(repeating: TerminalCell(), count: cols))
    }

    func resize(cols: Int, rows: Int) {
        let oldRows = self.rows
        self.cols = cols
        self.rows = rows
        print("[TERM DEBUG] resize: cols=\(cols), rows=\(rows), oldRows=\(oldRows), isAlt=\(isAlternateScreen), lines.count=\(lines.count)")

        if isAlternateScreen {
            // On alternate screen, always maintain exactly `rows` lines
            // This prevents scroll position issues when keyboard shows/hides
            if lines.count < rows {
                // Add empty lines at the bottom
                while lines.count < rows {
                    lines.append(createEmptyLine())
                }
            } else if lines.count > rows {
                // Remove lines from top (scroll up effect)
                while lines.count > rows {
                    lines.removeFirst()
                }
                // Adjust cursor if it was on a removed line
                cursorRow = min(cursorRow, rows - 1)
            }
        } else {
            // Normal screen: trim empty lines from beginning if too many
            while lines.count > rows * 2 {
                guard let firstLine = lines.first, isLineEmpty(firstLine) else {
                    break
                }
                lines.removeFirst()
            }

            // Ensure we have at least one line
            if lines.isEmpty {
                lines.append(createEmptyLine())
            }
        }

        // Adjust line widths
        for i in 0..<lines.count {
            if lines[i].cells.count < cols {
                lines[i].cells.append(contentsOf: Array(repeating: TerminalCell(), count: cols - lines[i].cells.count))
            } else if lines[i].cells.count > cols {
                lines[i].cells = Array(lines[i].cells.prefix(cols))
            }
        }

        // Clamp cursor to valid range based on actual screen size
        cursorRow = min(cursorRow, rows - 1)
        cursorCol = min(cursorCol, cols - 1)

        // Reset scroll region to full screen on resize
        scrollRegionTop = 0
        scrollRegionBottom = rows - 1
    }

    /// Reset the emulator to initial state (for reconnection)
    func reset() {
        lines = []
        cursorRow = 0
        cursorCol = 0
        scrollOffset = 0
        pendingWrap = false
        currentAttributes = CellAttributes()
        currentForeground = .default
        currentBackground = .default
        savedCursorRow = 0
        savedCursorCol = 0
        alternateBuffer = []
        isAlternateScreen = false
        scrollRegionTop = 0
        scrollRegionBottom = rows - 1
        parser.reset()
        initializeBuffer()

        // Cancel any pending render
        renderWorkItem?.cancel()
        renderWorkItem = nil
        lastRenderTime = 0
    }

    private func isLineEmpty(_ line: TerminalLine) -> Bool {
        line.cells.allSatisfy { $0.character == " " || $0.character == "\0" }
    }

    private var debugCounter = 0
    func processOutput(_ output: String) {
        let tokens = parser.parse(output)
        debugCounter += 1
        if debugCounter % 50 == 0 {
            print("[TERM DEBUG] processOutput #\(debugCounter): isAlt=\(isAlternateScreen), lines=\(lines.count), rows=\(rows), cursor=(\(cursorRow),\(cursorCol))")
        }

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

        // Track recent output for adaptive throttling
        recentOutputBytes += output.count
        outputResetWorkItem?.cancel()
        let resetWork = DispatchWorkItem { [weak self] in
            self?.recentOutputBytes = 0
        }
        outputResetWorkItem = resetWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: resetWork)

        // Adaptive rendering
        if suppressRendering {
            return  // Don't render during reconnect settling
        }
        scheduleRender()
    }

    private func scheduleRender() {
        // Cancel any pending render
        renderWorkItem?.cancel()

        let now = CFAbsoluteTimeGetCurrent()
        let timeSinceLastRender = now - lastRenderTime

        // Adaptive interval based on output volume
        let minInterval: CFAbsoluteTime
        if recentOutputBytes < fastOutputThreshold {
            minInterval = 0.016  // 60fps for typing
        } else if recentOutputBytes < heavyThrottleThreshold {
            minInterval = 0.033  // 30fps for moderate output
        } else {
            minInterval = 0.05   // 20fps for fast output
        }

        if timeSinceLastRender >= minInterval {
            // Render immediately
            lastRenderTime = now
            DispatchQueue.main.async { [weak self] in
                self?.objectWillChange.send()
            }
        } else {
            // Schedule for later - gets cancelled if more output arrives
            let delay = minInterval - timeSinceLastRender
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.lastRenderTime = CFAbsoluteTimeGetCurrent()
                self.objectWillChange.send()
            }
            renderWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    /// Force an immediate render (for reconnect)
    func flushRender() {
        renderWorkItem?.cancel()
        renderWorkItem = nil
        lastRenderTime = CFAbsoluteTimeGetCurrent()
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }

    // MARK: - Text Output

    private func writeText(_ text: String) {
        for char in text {
            writeCharacter(char)
        }
    }

    private func writeCharacter(_ char: Character) {
        // Handle deferred wrap: if pending, wrap now before writing
        if pendingWrap {
            pendingWrap = false
            let actualRow = lineIndex(for: cursorRow)
            if actualRow < lines.count {
                lines[actualRow].wrapped = true
            }
            cursorCol = 0
            lineFeed()
        }

        let actualRow = lineIndex(for: cursorRow)
        guard actualRow < lines.count && cursorCol < cols else { return }

        lines[actualRow].cells[cursorCol] = TerminalCell(
            character: char,
            foreground: currentForeground,
            background: currentBackground,
            attributes: currentAttributes
        )

        cursorCol += 1

        // Deferred wrap: don't wrap yet, just mark as pending
        if cursorCol >= cols {
            cursorCol = cols - 1  // Keep cursor at last column
            pendingWrap = true
        }
    }

    // MARK: - Control Characters

    private func handleControlChar(_ char: Character) {
        switch char {
        case "\n", "\u{0A}": // Line Feed (also resets column in newline mode)
            pendingWrap = false
            cursorCol = 0
            lineFeed()

        case "\r", "\u{0D}": // Carriage Return
            pendingWrap = false
            cursorCol = 0

        case "\t", "\u{09}": // Tab
            pendingWrap = false
            let nextTab = ((cursorCol / 8) + 1) * 8
            cursorCol = min(nextTab, cols - 1)

        case "\u{08}": // Backspace
            pendingWrap = false
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
        // Check if cursor is within the scroll region
        let inScrollRegion = cursorRow >= scrollRegionTop && cursorRow <= scrollRegionBottom

        if inScrollRegion {
            if cursorRow == scrollRegionBottom {
                // Cursor is at bottom of scroll region - scroll the region
                scrollRegionUp()
                // Cursor stays at scrollRegionBottom
            } else {
                // Within scroll region but not at bottom - just move down
                cursorRow += 1
            }
        } else {
            // Cursor is outside scroll region
            if cursorRow < rows - 1 {
                // Not at absolute bottom - just move down
                cursorRow += 1
            }
            // If at absolute bottom and outside scroll region, do nothing (cursor stays put)
            // This is important for status bars - they shouldn't cause scrolling
        }
    }

    /// Scroll the content within the scroll region up by one line
    private func scrollRegionUp() {
        // Ensure we have enough lines
        while lines.count < rows {
            lines.append(createEmptyLine())
        }

        let topIndex = lineIndex(for: scrollRegionTop)
        let bottomIndex = lineIndex(for: scrollRegionBottom)

        guard topIndex < lines.count && bottomIndex < lines.count && topIndex <= bottomIndex else { return }

        // Shift lines within the scroll region up
        for i in topIndex..<bottomIndex {
            if i + 1 < lines.count {
                lines[i] = lines[i + 1]
            }
        }
        // Clear the bottom line of the scroll region
        lines[bottomIndex] = createEmptyLine()
    }

    /// Scroll the content within the scroll region down by one line
    private func scrollRegionDown() {
        // Ensure we have enough lines
        while lines.count < rows {
            lines.append(createEmptyLine())
        }

        let topIndex = lineIndex(for: scrollRegionTop)
        let bottomIndex = lineIndex(for: scrollRegionBottom)

        guard topIndex < lines.count && bottomIndex < lines.count && topIndex <= bottomIndex else { return }

        // Shift lines within the scroll region down
        for i in stride(from: bottomIndex, to: topIndex, by: -1) {
            if i - 1 >= 0 {
                lines[i] = lines[i - 1]
            }
        }
        // Clear the top line of the scroll region
        lines[topIndex] = createEmptyLine()
    }

    // MARK: - Escape Sequences

    private func handleEscapeSequence(_ sequence: ANSIParser.EscapeSequence) {
        switch sequence {
        case .cursorUp(let n):
            pendingWrap = false
            cursorRow = max(0, cursorRow - n)

        case .cursorDown(let n):
            pendingWrap = false
            cursorRow = min(rows - 1, cursorRow + n)

        case .cursorForward(let n):
            pendingWrap = false
            cursorCol = min(cols - 1, cursorCol + n)

        case .cursorBack(let n):
            pendingWrap = false
            cursorCol = max(0, cursorCol - n)

        case .cursorPosition(let row, let col):
            pendingWrap = false
            cursorRow = min(rows - 1, max(0, row - 1))
            cursorCol = min(cols - 1, max(0, col - 1))

        case .cursorHorizontalAbsolute(let col):
            pendingWrap = false
            cursorCol = min(cols - 1, max(0, col - 1))

        case .cursorVerticalAbsolute(let row):
            pendingWrap = false
            cursorRow = min(rows - 1, max(0, row - 1))

        case .cursorNextLine(let n):
            pendingWrap = false
            cursorRow = min(rows - 1, cursorRow + n)
            cursorCol = 0

        case .cursorPreviousLine(let n):
            pendingWrap = false
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
                print("[TERM DEBUG] Switching to ALTERNATE screen, rows=\(rows), saving \(lines.count) lines")
                alternateBuffer = lines
                lines = (0..<rows).map { _ in createEmptyLine() }
                isAlternateScreen = true
                cursorRow = 0
                cursorCol = 0
                // Reset scroll region to full screen
                scrollRegionTop = 0
                scrollRegionBottom = rows - 1
                print("[TERM DEBUG] Alternate screen created with \(lines.count) lines")
            }

        case .alternateScreenOff:
            if isAlternateScreen {
                print("[TERM DEBUG] Switching to NORMAL screen, restoring \(alternateBuffer.count) lines")
                lines = alternateBuffer
                alternateBuffer = []
                isAlternateScreen = false
                // Reset scroll region to full screen
                scrollRegionTop = 0
                scrollRegionBottom = rows - 1
            }

        case .setScrollRegion(let top, let bottom):
            // DECSTBM - Set Top and Bottom Margins
            // Parameters are 1-indexed. Default is full screen.
            // CSI r with no params resets to full screen
            if top == 0 && bottom == 0 {
                // Reset to full screen
                scrollRegionTop = 0
                scrollRegionBottom = rows - 1
            } else {
                scrollRegionTop = max(0, top - 1)  // Convert to 0-indexed
                scrollRegionBottom = min(rows - 1, (bottom > 0 ? bottom - 1 : rows - 1))
            }
            // Setting scroll region moves cursor to home position
            cursorRow = 0
            cursorCol = 0
            print("[TERM DEBUG] setScrollRegion: top=\(scrollRegionTop), bottom=\(scrollRegionBottom), rows=\(rows)")

        case .insertLines(let n):
            insertLines(n)

        case .deleteLines(let n):
            deleteLines(n)

        case .insertCharacters(let n):
            insertCharacters(n)

        case .deleteCharacters(let n):
            deleteCharacters(n)

        case .eraseCharacters(let n):
            eraseCharacters(n)

        case .scrollUp(let n):
            // SU - Scroll Up: scroll content within scroll region up
            for _ in 0..<n {
                scrollRegionUp()
            }

        case .scrollDown(let n):
            // SD - Scroll Down: scroll content within scroll region down
            for _ in 0..<n {
                scrollRegionDown()
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
            for screenRow in (cursorRow + 1)..<rows {
                let actualRow = lineIndex(for: screenRow)
                if actualRow < lines.count {
                    lines[actualRow] = createEmptyLine()
                }
            }

        case 1: // Start to cursor
            for screenRow in 0..<cursorRow {
                let actualRow = lineIndex(for: screenRow)
                if actualRow < lines.count {
                    lines[actualRow] = createEmptyLine()
                }
            }
            eraseLine(mode: 1)

        case 2, 3: // Entire screen
            if isAlternateScreen {
                // On alternate screen, maintain exactly `rows` lines for fullscreen apps
                lines = (0..<rows).map { _ in createEmptyLine() }
            } else {
                // Normal screen: reset to minimal lines
                lines = [createEmptyLine()]
            }
            cursorRow = 0
            cursorCol = 0

        default:
            break
        }
    }

    private func eraseLine(mode: Int) {
        let actualRow = lineIndex(for: cursorRow)
        guard actualRow < lines.count else { return }

        switch mode {
        case 0: // Cursor to end
            for i in cursorCol..<cols {
                if i < lines[actualRow].cells.count {
                    lines[actualRow].cells[i] = TerminalCell()
                }
            }

        case 1: // Start to cursor
            for i in 0...cursorCol {
                if i < lines[actualRow].cells.count {
                    lines[actualRow].cells[i] = TerminalCell()
                }
            }

        case 2: // Entire line
            lines[actualRow] = createEmptyLine()

        default:
            break
        }
    }

    private func insertLines(_ n: Int) {
        // IL - Insert Lines within scroll region
        // Lines below cursor (within scroll region) scroll down
        // Cursor must be within scroll region for this to work
        guard cursorRow >= scrollRegionTop && cursorRow <= scrollRegionBottom else { return }

        let startRow = lineIndex(for: cursorRow)
        let bottomRow = lineIndex(for: scrollRegionBottom)

        for _ in 0..<n {
            guard startRow < lines.count && bottomRow < lines.count else { continue }

            // Remove the bottom line of scroll region
            if bottomRow < lines.count {
                lines.remove(at: bottomRow)
            }

            // Insert blank line at cursor position
            lines.insert(createEmptyLine(), at: startRow)
        }
    }

    private func deleteLines(_ n: Int) {
        // DL - Delete Lines within scroll region
        // Lines below cursor (within scroll region) scroll up
        // Cursor must be within scroll region for this to work
        guard cursorRow >= scrollRegionTop && cursorRow <= scrollRegionBottom else { return }

        let startRow = lineIndex(for: cursorRow)
        let bottomRow = lineIndex(for: scrollRegionBottom)

        for _ in 0..<n {
            guard startRow < lines.count && bottomRow < lines.count else { continue }

            // Remove line at cursor position
            lines.remove(at: startRow)

            // Insert blank line at bottom of scroll region
            let insertPos = min(bottomRow, lines.count)
            lines.insert(createEmptyLine(), at: insertPos)
        }
    }

    // MARK: - Character Operations

    private func insertCharacters(_ n: Int) {
        // ICH: Insert n blank characters at cursor, shifting existing content right
        let actualRow = lineIndex(for: cursorRow)
        guard actualRow < lines.count else { return }

        var cells = lines[actualRow].cells
        let insertCount = min(n, cols - cursorCol)

        // Insert blank cells at cursor position
        let blanks = Array(repeating: TerminalCell(), count: insertCount)
        cells.insert(contentsOf: blanks, at: cursorCol)

        // Trim to cols width (characters shifted off right edge are lost)
        lines[actualRow].cells = Array(cells.prefix(cols))
    }

    private func deleteCharacters(_ n: Int) {
        // DCH: Delete n characters at cursor, shifting content left, blanks added at right
        let actualRow = lineIndex(for: cursorRow)
        guard actualRow < lines.count else { return }

        var cells = lines[actualRow].cells
        let deleteCount = min(n, cols - cursorCol)

        // Remove characters at cursor position
        cells.removeSubrange(cursorCol..<(cursorCol + deleteCount))

        // Add blanks at the end to maintain line width
        cells.append(contentsOf: Array(repeating: TerminalCell(), count: deleteCount))

        lines[actualRow].cells = cells
    }

    private func eraseCharacters(_ n: Int) {
        // ECH: Replace n characters starting at cursor with blanks (no shift)
        let actualRow = lineIndex(for: cursorRow)
        guard actualRow < lines.count else { return }

        let eraseCount = min(n, cols - cursorCol)
        for i in 0..<eraseCount {
            let col = cursorCol + i
            if col < lines[actualRow].cells.count {
                lines[actualRow].cells[col] = TerminalCell()
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

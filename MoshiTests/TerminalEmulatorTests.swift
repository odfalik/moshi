import XCTest
@testable import Moshi

final class TerminalEmulatorTests: XCTestCase {
    var emulator: TerminalEmulator!

    override func setUp() {
        super.setUp()
        emulator = TerminalEmulator()
        emulator.resize(cols: 80, rows: 24)
    }

    override func tearDown() {
        emulator = nil
        super.tearDown()
    }

    // MARK: - Basic Output Tests

    func testProcessSimpleText() {
        emulator.processOutput("Hello")

        XCTAssertEqual(emulator.cursorCol, 5)
        XCTAssertEqual(emulator.cursorRow, 0)

        let line = emulator.lines[0]
        XCTAssertEqual(line.cells[0].character, "H")
        XCTAssertEqual(line.cells[1].character, "e")
        XCTAssertEqual(line.cells[2].character, "l")
        XCTAssertEqual(line.cells[3].character, "l")
        XCTAssertEqual(line.cells[4].character, "o")
    }

    func testProcessNewline() {
        emulator.processOutput("Line1\nLine2")

        XCTAssertEqual(emulator.cursorRow, 1)
        XCTAssertEqual(emulator.cursorCol, 5)
    }

    func testProcessCarriageReturn() {
        emulator.processOutput("Hello\rWorld")

        XCTAssertEqual(emulator.cursorCol, 5)
        XCTAssertEqual(emulator.cursorRow, 0)

        // "World" should overwrite "Hello"
        let line = emulator.lines[0]
        XCTAssertEqual(line.cells[0].character, "W")
        XCTAssertEqual(line.cells[1].character, "o")
        XCTAssertEqual(line.cells[2].character, "r")
        XCTAssertEqual(line.cells[3].character, "l")
        XCTAssertEqual(line.cells[4].character, "d")
    }

    func testProcessTab() {
        emulator.processOutput("A\tB")

        // Tab should move to next 8-column boundary
        XCTAssertEqual(emulator.cursorCol, 9)
    }

    // MARK: - Line Wrapping Tests

    func testLineWrapping() {
        let longText = String(repeating: "A", count: 85)
        emulator.processOutput(longText)

        XCTAssertEqual(emulator.cursorRow, 1)
        XCTAssertEqual(emulator.cursorCol, 5)
        XCTAssertTrue(emulator.lines[0].wrapped)
    }

    // MARK: - Cursor Movement Tests

    func testCursorUp() {
        emulator.processOutput("Line1\nLine2\nLine3")
        emulator.processOutput("\u{1B}[2A") // Move up 2

        XCTAssertEqual(emulator.cursorRow, 0)
    }

    func testCursorDown() {
        emulator.processOutput("Line1")
        emulator.processOutput("\u{1B}[5B") // Move down 5

        XCTAssertEqual(emulator.cursorRow, 5)
    }

    func testCursorForward() {
        emulator.processOutput("\u{1B}[10C") // Move forward 10

        XCTAssertEqual(emulator.cursorCol, 10)
    }

    func testCursorBack() {
        emulator.processOutput("Hello")
        emulator.processOutput("\u{1B}[3D") // Move back 3

        XCTAssertEqual(emulator.cursorCol, 2)
    }

    func testCursorPosition() {
        emulator.processOutput("\u{1B}[10;20H") // Move to row 10, col 20

        XCTAssertEqual(emulator.cursorRow, 9) // 0-indexed
        XCTAssertEqual(emulator.cursorCol, 19)
    }

    func testCursorHome() {
        emulator.processOutput("Some text")
        emulator.processOutput("\u{1B}[H") // Home

        XCTAssertEqual(emulator.cursorRow, 0)
        XCTAssertEqual(emulator.cursorCol, 0)
    }

    // MARK: - Erase Tests

    func testEraseLineToEnd() {
        emulator.processOutput("Hello World")
        emulator.processOutput("\u{1B}[5D") // Back 5
        emulator.processOutput("\u{1B}[K") // Erase to end

        let line = emulator.lines[0]
        XCTAssertEqual(line.cells[6].character, " ")
        XCTAssertEqual(line.cells[10].character, " ")
    }

    func testEraseLineToBeginning() {
        emulator.processOutput("Hello World")
        emulator.processOutput("\u{1B}[5D") // Back 5
        emulator.processOutput("\u{1B}[1K") // Erase to beginning

        let line = emulator.lines[0]
        XCTAssertEqual(line.cells[0].character, " ")
        XCTAssertEqual(line.cells[5].character, " ")
    }

    func testEraseEntireLine() {
        emulator.processOutput("Hello World")
        emulator.processOutput("\u{1B}[2K") // Erase entire line

        let line = emulator.lines[0]
        for cell in line.cells {
            XCTAssertEqual(cell.character, " ")
        }
    }

    func testEraseDisplayToEnd() {
        for i in 0..<5 {
            emulator.processOutput("Line \(i)\n")
        }
        emulator.processOutput("\u{1B}[3;1H") // Move to row 3
        emulator.processOutput("\u{1B}[J") // Erase to end

        // Lines 0-2 should have content, lines 3+ should be empty
        XCTAssertNotEqual(emulator.lines[0].cells[0].character, " ")
        XCTAssertEqual(emulator.lines[3].cells[0].character, " ")
    }

    func testEraseDisplayAll() {
        emulator.processOutput("Hello World")
        emulator.processOutput("\u{1B}[2J") // Clear screen

        for line in emulator.lines {
            for cell in line.cells {
                XCTAssertEqual(cell.character, " ")
            }
        }
    }

    // MARK: - SGR (Attributes) Tests

    func testSGRBold() {
        emulator.processOutput("\u{1B}[1mBold")

        let cell = emulator.lines[0].cells[0]
        XCTAssertTrue(cell.attributes.contains(.bold))
    }

    func testSGRItalic() {
        emulator.processOutput("\u{1B}[3mItalic")

        let cell = emulator.lines[0].cells[0]
        XCTAssertTrue(cell.attributes.contains(.italic))
    }

    func testSGRUnderline() {
        emulator.processOutput("\u{1B}[4mUnderlined")

        let cell = emulator.lines[0].cells[0]
        XCTAssertTrue(cell.attributes.contains(.underline))
    }

    func testSGRReset() {
        emulator.processOutput("\u{1B}[1;3;4mFormatted\u{1B}[0mNormal")

        let formattedCell = emulator.lines[0].cells[0]
        XCTAssertTrue(formattedCell.attributes.contains(.bold))
        XCTAssertTrue(formattedCell.attributes.contains(.italic))
        XCTAssertTrue(formattedCell.attributes.contains(.underline))

        let normalCell = emulator.lines[0].cells[9]
        XCTAssertFalse(normalCell.attributes.contains(.bold))
        XCTAssertFalse(normalCell.attributes.contains(.italic))
        XCTAssertFalse(normalCell.attributes.contains(.underline))
    }

    func testSGRForegroundColor() {
        emulator.processOutput("\u{1B}[32mGreen")

        let cell = emulator.lines[0].cells[0]
        if case .indexed(let index) = cell.foreground {
            XCTAssertEqual(index, 2) // Green is color 2
        } else {
            XCTFail("Expected indexed color")
        }
    }

    func testSGRBackgroundColor() {
        emulator.processOutput("\u{1B}[44mBlueBackground")

        let cell = emulator.lines[0].cells[0]
        if case .indexed(let index) = cell.background {
            XCTAssertEqual(index, 4) // Blue is color 4
        } else {
            XCTFail("Expected indexed color")
        }
    }

    // MARK: - Resize Tests

    func testResize() {
        emulator.processOutput("Hello")
        emulator.resize(cols: 40, rows: 12)

        XCTAssertEqual(emulator.lines.count, 12)
        XCTAssertEqual(emulator.lines[0].cells.count, 40)
    }

    func testResizeClamsCursor() {
        emulator.processOutput("\u{1B}[20;70H") // Move to row 20, col 70
        emulator.resize(cols: 40, rows: 10)

        XCTAssertEqual(emulator.cursorRow, 9)
        XCTAssertEqual(emulator.cursorCol, 39)
    }

    // MARK: - Scroll Tests

    func testScrollUp() {
        // Fill screen
        for i in 0..<24 {
            emulator.processOutput("Line \(i)\n")
        }

        // Add more content to trigger scroll
        emulator.processOutput("New Line")

        // First line should have scrolled out
        XCTAssertNotEqual(String(emulator.lines[0].cells.prefix(4).map { $0.character }), "Line")
    }

    func testScrollDown() {
        emulator.processOutput("Line1\nLine2\nLine3")
        emulator.processOutput("\u{1B}[2T") // Scroll down 2

        // Content should have shifted down
    }

    // MARK: - Alternate Screen Tests

    func testAlternateScreen() {
        emulator.processOutput("Main screen content")
        emulator.processOutput("\u{1B}[?1049h") // Enter alternate screen

        // Alternate screen should be empty
        XCTAssertEqual(emulator.lines[0].cells[0].character, " ")

        emulator.processOutput("Alternate content")
        emulator.processOutput("\u{1B}[?1049l") // Exit alternate screen

        // Should be back to main screen
        XCTAssertEqual(emulator.lines[0].cells[0].character, "M")
    }

    // MARK: - Save/Restore Cursor Tests

    func testSaveRestoreCursor() {
        emulator.processOutput("Hello")
        emulator.processOutput("\u{1B}[s") // Save cursor
        emulator.processOutput("\u{1B}[10;10H") // Move away
        emulator.processOutput("\u{1B}[u") // Restore cursor

        XCTAssertEqual(emulator.cursorRow, 0)
        XCTAssertEqual(emulator.cursorCol, 5)
    }

    // MARK: - Visible Lines Tests

    func testGetVisibleLines() {
        // Fill more than screen
        for i in 0..<30 {
            emulator.processOutput("Line \(i)\n")
        }

        let visible = emulator.getVisibleLines()
        XCTAssertEqual(visible.count, 24) // Should return screen height lines
    }

    // MARK: - Scrollback Tests

    func testScrollToTop() {
        for i in 0..<100 {
            emulator.processOutput("Line \(i)\n")
        }

        emulator.scrollToTop()
        XCTAssertGreaterThan(emulator.scrollOffset, 0)
    }

    func testScrollToBottom() {
        for i in 0..<100 {
            emulator.processOutput("Line \(i)\n")
        }

        emulator.scrollToTop()
        emulator.scrollToBottom()
        XCTAssertEqual(emulator.scrollOffset, 0)
    }
}

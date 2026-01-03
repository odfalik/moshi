import XCTest
@testable import Moshi

final class ANSIParserTests: XCTestCase {
    var parser: ANSIParser!

    override func setUp() {
        super.setUp()
        parser = ANSIParser()
    }

    override func tearDown() {
        parser = nil
        super.tearDown()
    }

    // MARK: - Plain Text Tests

    func testParsePlainText() {
        let tokens = parser.parse("Hello, World!")

        XCTAssertEqual(tokens.count, 1)
        if case .text(let text) = tokens[0] {
            XCTAssertEqual(text, "Hello, World!")
        } else {
            XCTFail("Expected text token")
        }
    }

    func testParseEmptyString() {
        let tokens = parser.parse("")
        XCTAssertEqual(tokens.count, 0)
    }

    // MARK: - Control Character Tests

    func testParseNewline() {
        let tokens = parser.parse("Line1\nLine2")

        XCTAssertEqual(tokens.count, 3)
        if case .text(let text) = tokens[0] {
            XCTAssertEqual(text, "Line1")
        }
        if case .controlChar(let char) = tokens[1] {
            XCTAssertEqual(char, "\n")
        }
        if case .text(let text) = tokens[2] {
            XCTAssertEqual(text, "Line2")
        }
    }

    func testParseCarriageReturn() {
        let tokens = parser.parse("Hello\rWorld")

        XCTAssertEqual(tokens.count, 3)
        if case .controlChar(let char) = tokens[1] {
            XCTAssertEqual(char, "\r")
        }
    }

    func testParseTab() {
        let tokens = parser.parse("Col1\tCol2")

        XCTAssertEqual(tokens.count, 3)
        if case .controlChar(let char) = tokens[1] {
            XCTAssertEqual(char, "\t")
        }
    }

    // MARK: - Cursor Movement Tests

    func testParseCursorUp() {
        let tokens = parser.parse("\u{1B}[5A")

        XCTAssertEqual(tokens.count, 1)
        if case .escape(let sequence) = tokens[0] {
            XCTAssertEqual(sequence, .cursorUp(5))
        } else {
            XCTFail("Expected escape sequence")
        }
    }

    func testParseCursorDown() {
        let tokens = parser.parse("\u{1B}[3B")

        XCTAssertEqual(tokens.count, 1)
        if case .escape(let sequence) = tokens[0] {
            XCTAssertEqual(sequence, .cursorDown(3))
        }
    }

    func testParseCursorForward() {
        let tokens = parser.parse("\u{1B}[10C")

        XCTAssertEqual(tokens.count, 1)
        if case .escape(let sequence) = tokens[0] {
            XCTAssertEqual(sequence, .cursorForward(10))
        }
    }

    func testParseCursorBack() {
        let tokens = parser.parse("\u{1B}[2D")

        XCTAssertEqual(tokens.count, 1)
        if case .escape(let sequence) = tokens[0] {
            XCTAssertEqual(sequence, .cursorBack(2))
        }
    }

    func testParseCursorPosition() {
        let tokens = parser.parse("\u{1B}[10;20H")

        XCTAssertEqual(tokens.count, 1)
        if case .escape(let sequence) = tokens[0] {
            XCTAssertEqual(sequence, .cursorPosition(10, 20))
        }
    }

    func testParseCursorPositionDefault() {
        let tokens = parser.parse("\u{1B}[H")

        XCTAssertEqual(tokens.count, 1)
        if case .escape(let sequence) = tokens[0] {
            XCTAssertEqual(sequence, .cursorPosition(1, 1))
        }
    }

    // MARK: - Erase Tests

    func testParseEraseDisplayToEnd() {
        let tokens = parser.parse("\u{1B}[0J")

        XCTAssertEqual(tokens.count, 1)
        if case .escape(let sequence) = tokens[0] {
            XCTAssertEqual(sequence, .eraseDisplay(0))
        }
    }

    func testParseEraseDisplayToBeginning() {
        let tokens = parser.parse("\u{1B}[1J")

        XCTAssertEqual(tokens.count, 1)
        if case .escape(let sequence) = tokens[0] {
            XCTAssertEqual(sequence, .eraseDisplay(1))
        }
    }

    func testParseEraseDisplayAll() {
        let tokens = parser.parse("\u{1B}[2J")

        XCTAssertEqual(tokens.count, 1)
        if case .escape(let sequence) = tokens[0] {
            XCTAssertEqual(sequence, .eraseDisplay(2))
        }
    }

    func testParseEraseLine() {
        let tokens = parser.parse("\u{1B}[K")

        XCTAssertEqual(tokens.count, 1)
        if case .escape(let sequence) = tokens[0] {
            XCTAssertEqual(sequence, .eraseLine(0))
        }
    }

    // MARK: - SGR (Colors/Attributes) Tests

    func testParseSGRReset() {
        let tokens = parser.parse("\u{1B}[0m")

        XCTAssertEqual(tokens.count, 1)
        if case .escape(let sequence) = tokens[0] {
            XCTAssertEqual(sequence, .sgr([0]))
        }
    }

    func testParseSGRBold() {
        let tokens = parser.parse("\u{1B}[1m")

        XCTAssertEqual(tokens.count, 1)
        if case .escape(let sequence) = tokens[0] {
            XCTAssertEqual(sequence, .sgr([1]))
        }
    }

    func testParseSGRForegroundColor() {
        let tokens = parser.parse("\u{1B}[32m")

        XCTAssertEqual(tokens.count, 1)
        if case .escape(let sequence) = tokens[0] {
            XCTAssertEqual(sequence, .sgr([32]))
        }
    }

    func testParseSGRMultipleAttributes() {
        let tokens = parser.parse("\u{1B}[1;32;44m")

        XCTAssertEqual(tokens.count, 1)
        if case .escape(let sequence) = tokens[0] {
            XCTAssertEqual(sequence, .sgr([1, 32, 44]))
        }
    }

    func testParseSGR256Color() {
        let tokens = parser.parse("\u{1B}[38;5;196m")

        XCTAssertEqual(tokens.count, 1)
        if case .escape(let sequence) = tokens[0] {
            XCTAssertEqual(sequence, .sgr([38, 5, 196]))
        }
    }

    func testParseSGRTrueColor() {
        let tokens = parser.parse("\u{1B}[38;2;255;100;50m")

        XCTAssertEqual(tokens.count, 1)
        if case .escape(let sequence) = tokens[0] {
            XCTAssertEqual(sequence, .sgr([38, 2, 255, 100, 50]))
        }
    }

    // MARK: - Alternate Screen Tests

    func testParseAlternateScreenOn() {
        let tokens = parser.parse("\u{1B}[?1049h")

        XCTAssertEqual(tokens.count, 1)
        if case .escape(let sequence) = tokens[0] {
            XCTAssertEqual(sequence, .alternateScreenOn)
        }
    }

    func testParseAlternateScreenOff() {
        let tokens = parser.parse("\u{1B}[?1049l")

        XCTAssertEqual(tokens.count, 1)
        if case .escape(let sequence) = tokens[0] {
            XCTAssertEqual(sequence, .alternateScreenOff)
        }
    }

    // MARK: - Mixed Content Tests

    func testParseMixedContent() {
        let tokens = parser.parse("Hello \u{1B}[32mGreen\u{1B}[0m World")

        XCTAssertEqual(tokens.count, 5)

        if case .text(let text) = tokens[0] {
            XCTAssertEqual(text, "Hello ")
        }
        if case .escape(let seq) = tokens[1] {
            XCTAssertEqual(seq, .sgr([32]))
        }
        if case .text(let text) = tokens[2] {
            XCTAssertEqual(text, "Green")
        }
        if case .escape(let seq) = tokens[3] {
            XCTAssertEqual(seq, .sgr([0]))
        }
        if case .text(let text) = tokens[4] {
            XCTAssertEqual(text, " World")
        }
    }

    // MARK: - Save/Restore Cursor Tests

    func testParseSaveCursor() {
        let tokens = parser.parse("\u{1B}[s")

        XCTAssertEqual(tokens.count, 1)
        if case .escape(let sequence) = tokens[0] {
            XCTAssertEqual(sequence, .saveCursor)
        }
    }

    func testParseRestoreCursor() {
        let tokens = parser.parse("\u{1B}[u")

        XCTAssertEqual(tokens.count, 1)
        if case .escape(let sequence) = tokens[0] {
            XCTAssertEqual(sequence, .restoreCursor)
        }
    }

    // MARK: - Line Operations Tests

    func testParseInsertLines() {
        let tokens = parser.parse("\u{1B}[3L")

        XCTAssertEqual(tokens.count, 1)
        if case .escape(let sequence) = tokens[0] {
            XCTAssertEqual(sequence, .insertLines(3))
        }
    }

    func testParseDeleteLines() {
        let tokens = parser.parse("\u{1B}[2M")

        XCTAssertEqual(tokens.count, 1)
        if case .escape(let sequence) = tokens[0] {
            XCTAssertEqual(sequence, .deleteLines(2))
        }
    }

    // MARK: - Scroll Tests

    func testParseScrollUp() {
        let tokens = parser.parse("\u{1B}[5S")

        XCTAssertEqual(tokens.count, 1)
        if case .escape(let sequence) = tokens[0] {
            XCTAssertEqual(sequence, .scrollUp(5))
        }
    }

    func testParseScrollDown() {
        let tokens = parser.parse("\u{1B}[3T")

        XCTAssertEqual(tokens.count, 1)
        if case .escape(let sequence) = tokens[0] {
            XCTAssertEqual(sequence, .scrollDown(3))
        }
    }

    // MARK: - Reset Tests

    func testParserReset() {
        // Parse partial sequence
        _ = parser.parse("\u{1B}[")

        // Reset
        parser.reset()

        // Should parse cleanly
        let tokens = parser.parse("Hello")
        XCTAssertEqual(tokens.count, 1)
        if case .text(let text) = tokens[0] {
            XCTAssertEqual(text, "Hello")
        }
    }
}

import XCTest
@testable import Moshi

final class MacroTests: XCTestCase {

    // MARK: - Macro Creation Tests

    func testMacroCreationWithTextAction() {
        let macro = Macro(
            label: "Test",
            icon: "star",
            action: .sendText("hello"),
            color: .blue,
            category: "custom"
        )

        XCTAssertEqual(macro.label, "Test")
        XCTAssertEqual(macro.icon, "star")
        XCTAssertEqual(macro.category, "custom")
    }

    func testMacroCreationWithCommandAction() {
        let macro = Macro(
            label: "List",
            action: .sendCommand("ls -la")
        )

        XCTAssertEqual(macro.label, "List")
    }

    func testMacroCreationWithSpecialKeyAction() {
        let macro = Macro(
            label: "Escape",
            action: .specialKey(.escape)
        )

        XCTAssertEqual(macro.label, "Escape")
    }

    // MARK: - Built-in Macro Sets Tests

    func testSpecialKeysMacrosNotEmpty() {
        XCTAssertFalse(Macro.specialKeys.isEmpty)
        XCTAssertTrue(Macro.specialKeys.count >= 10)
    }

    func testBashMacrosNotEmpty() {
        XCTAssertFalse(Macro.bashMacros.isEmpty)
    }

    func testGitMacrosNotEmpty() {
        XCTAssertFalse(Macro.gitMacros.isEmpty)
    }

    func testClaudeMacrosNotEmpty() {
        XCTAssertFalse(Macro.claudeMacros.isEmpty)
    }

    func testTmuxMacrosNotEmpty() {
        XCTAssertFalse(Macro.tmuxMacros.isEmpty)
    }

    // MARK: - Special Key Sequence Tests

    func testEscapeSequence() {
        XCTAssertEqual(SpecialKey.escape.sequence, "\u{1B}")
    }

    func testCtrlCSequence() {
        XCTAssertEqual(SpecialKey.ctrlC.sequence, "\u{03}")
    }

    func testCtrlDSequence() {
        XCTAssertEqual(SpecialKey.ctrlD.sequence, "\u{04}")
    }

    func testArrowUpSequence() {
        XCTAssertEqual(SpecialKey.up.sequence, "\u{1B}[A")
    }

    func testArrowDownSequence() {
        XCTAssertEqual(SpecialKey.down.sequence, "\u{1B}[B")
    }

    func testArrowRightSequence() {
        XCTAssertEqual(SpecialKey.right.sequence, "\u{1B}[C")
    }

    func testArrowLeftSequence() {
        XCTAssertEqual(SpecialKey.left.sequence, "\u{1B}[D")
    }

    func testFunctionKeyF1Sequence() {
        XCTAssertEqual(SpecialKey.f1.sequence, "\u{1B}OP")
    }

    func testFunctionKeyF5Sequence() {
        XCTAssertEqual(SpecialKey.f5.sequence, "\u{1B}[15~")
    }

    // MARK: - Macro Manager Tests

    func testMacroManagerSingleton() {
        let manager1 = MacroManager.shared
        let manager2 = MacroManager.shared
        XCTAssertTrue(manager1 === manager2)
    }

    func testMacroManagerAddMacro() {
        let manager = MacroManager.shared
        let initialCount = manager.customMacros.count

        let macro = Macro(
            label: "Test Macro",
            action: .sendText("test")
        )
        manager.addMacro(macro)

        XCTAssertEqual(manager.customMacros.count, initialCount + 1)

        // Cleanup
        manager.deleteMacro(macro)
    }

    func testMacroManagerDeleteMacro() {
        let manager = MacroManager.shared

        let macro = Macro(
            label: "To Delete",
            action: .sendText("delete me")
        )
        manager.addMacro(macro)
        let countAfterAdd = manager.customMacros.count

        manager.deleteMacro(macro)

        XCTAssertEqual(manager.customMacros.count, countAfterAdd - 1)
    }

    // MARK: - Stored Macro Tests

    func testStoredMacroEncodingDecoding() throws {
        let original = Macro(
            label: "Test",
            icon: "star",
            action: .sendCommand("ls -la"),
            color: .blue,
            category: "custom"
        )

        let stored = StoredMacro(from: original)
        let decoded = stored.toMacro()

        XCTAssertEqual(decoded.label, original.label)
        XCTAssertEqual(decoded.icon, original.icon)
        XCTAssertEqual(decoded.category, original.category)
    }

    func testStoredMacroSendTextAction() throws {
        let original = Macro(
            label: "Text",
            action: .sendText("hello world")
        )

        let stored = StoredMacro(from: original)
        let decoded = stored.toMacro()

        if case .sendText(let text) = decoded.action {
            XCTAssertEqual(text, "hello world")
        } else {
            XCTFail("Expected sendText action")
        }
    }

    func testStoredMacroSpecialKeyAction() throws {
        let original = Macro(
            label: "Escape",
            action: .specialKey(.escape)
        )

        let stored = StoredMacro(from: original)
        let decoded = stored.toMacro()

        if case .specialKey(let key) = decoded.action {
            XCTAssertEqual(key, .escape)
        } else {
            XCTFail("Expected specialKey action")
        }
    }

    // MARK: - Macro Categories Tests

    func testBashMacrosHaveCorrectCategory() {
        for macro in Macro.bashMacros {
            XCTAssertEqual(macro.category, "bash")
        }
    }

    func testGitMacrosHaveCorrectCategory() {
        for macro in Macro.gitMacros {
            XCTAssertEqual(macro.category, "git")
        }
    }

    func testClaudeMacrosHaveCorrectCategory() {
        for macro in Macro.claudeMacros {
            XCTAssertEqual(macro.category, "claude")
        }
    }

    func testTmuxMacrosHaveCorrectCategory() {
        for macro in Macro.tmuxMacros {
            XCTAssertEqual(macro.category, "tmux")
        }
    }

    // MARK: - Claude Code Macro Specifics Tests

    func testClaudeMacrosContainEssentialCommands() {
        let labels = Macro.claudeMacros.map { $0.label }

        XCTAssertTrue(labels.contains("claude"))
        XCTAssertTrue(labels.contains("/exit"))
        XCTAssertTrue(labels.contains("/help"))
    }

    // MARK: - Bash Macro Specifics Tests

    func testBashMacrosContainEssentialCommands() {
        let labels = Macro.bashMacros.map { $0.label }

        XCTAssertTrue(labels.contains("sudo !!"))
        XCTAssertTrue(labels.contains("cd .."))
        XCTAssertTrue(labels.contains("ls -la"))
        XCTAssertTrue(labels.contains("|grep"))
    }

    // MARK: - Git Macro Specifics Tests

    func testGitMacrosContainEssentialCommands() {
        let labels = Macro.gitMacros.map { $0.label }

        XCTAssertTrue(labels.contains("status"))
        XCTAssertTrue(labels.contains("diff"))
        XCTAssertTrue(labels.contains("push"))
        XCTAssertTrue(labels.contains("pull"))
        XCTAssertTrue(labels.contains("commit"))
    }

    // MARK: - Tmux Macro Specifics Tests

    func testTmuxMacrosContainEssentialCommands() {
        let labels = Macro.tmuxMacros.map { $0.label }

        XCTAssertTrue(labels.contains("PREFIX"))
        XCTAssertTrue(labels.contains("new-win"))
        XCTAssertTrue(labels.contains("split-h"))
        XCTAssertTrue(labels.contains("split-v"))
        XCTAssertTrue(labels.contains("detach"))
    }
}

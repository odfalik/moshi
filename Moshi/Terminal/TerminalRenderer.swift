import SwiftUI
import UIKit

struct TerminalRenderer: View {
    @ObservedObject var emulator: TerminalEmulator
    let theme: TerminalTheme
    let font: TerminalFont
    var onTap: (() -> Void)? = nil

    var body: some View {
        SelectableTerminalView(
            emulator: emulator,
            theme: theme,
            font: font,
            onTap: onTap
        )
        .background(theme.swiftUIBackground)
    }
}

// MARK: - Native iOS Selectable Terminal

struct SelectableTerminalView: UIViewRepresentable {
    @ObservedObject var emulator: TerminalEmulator
    let theme: TerminalTheme
    let font: TerminalFont
    var onTap: (() -> Void)?

    func makeUIView(context: Context) -> TerminalTextView {
        let textView = TerminalTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = UIColor(theme.swiftUIBackground)
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.isScrollEnabled = false
        textView.dataDetectorTypes = []  // Disable link detection
        textView.linkTextAttributes = [:]
        textView.onTap = onTap
        textView.tintColor = UIColor(theme.cursor.color)  // Selection handles color

        return textView
    }

    func updateUIView(_ textView: TerminalTextView, context: Context) {
        // Only update text if content changed to preserve selection state
        let attributedText = buildAttributedString()
        if textView.attributedText.string != attributedText.string {
            // Save selection
            let savedSelection = textView.selectedRange
            textView.attributedText = attributedText
            // Restore selection if still valid
            if savedSelection.location + savedSelection.length <= attributedText.length {
                textView.selectedRange = savedSelection
            }
        }

        textView.backgroundColor = UIColor(theme.swiftUIBackground)
        textView.cursorPosition = CGPoint(
            x: CGFloat(emulator.cursorCol) * font.characterWidth,
            y: CGFloat(emulator.cursorRow) * font.lineHeight
        )
        textView.cursorSize = CGSize(width: font.characterWidth, height: font.lineHeight)
        textView.cursorColor = UIColor(theme.cursor.color)
        textView.updateCursorPosition()
    }

    private func buildAttributedString() -> NSAttributedString {
        let result = NSMutableAttributedString()
        let visible = visibleLines

        for (index, item) in visible.enumerated() {
            let lineAttr = buildLineAttributedString(line: item.line)
            result.append(lineAttr)

            // Add newline except for last line
            if index < visible.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: [
                    .font: font.uiFont,
                    .foregroundColor: UIColor(theme.swiftUIForeground)
                ]))
            }
        }

        return result
    }

    private func buildLineAttributedString(line: TerminalLine) -> NSAttributedString {
        let result = NSMutableAttributedString()

        for cell in line.cells {
            let char = String(cell.character)
            let fgColor = colorFromTerminalColor(cell.foreground, isBackground: false, cell: cell)
            let bgColor = colorFromTerminalColor(cell.background, isBackground: true, cell: cell)

            var attributes: [NSAttributedString.Key: Any] = [
                .font: font.uiFont,
                .foregroundColor: fgColor,
                .backgroundColor: bgColor
            ]

            if cell.attributes.contains(.bold) {
                attributes[.font] = font.boldUIFont
            }

            if cell.attributes.contains(.underline) {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }

            result.append(NSAttributedString(string: char, attributes: attributes))
        }

        return result
    }

    private func colorFromTerminalColor(_ color: TerminalColor, isBackground: Bool, cell: TerminalCell) -> UIColor {
        let isInverse = cell.attributes.contains(.inverse)

        if isInverse {
            // Swap foreground and background
            if isBackground {
                return uiColorFromTerminalColor(cell.foreground, isBackground: false)
            } else {
                return uiColorFromTerminalColor(cell.background, isBackground: true)
            }
        }

        return uiColorFromTerminalColor(color, isBackground: isBackground)
    }

    private func uiColorFromTerminalColor(_ color: TerminalColor, isBackground: Bool) -> UIColor {
        switch color {
        case .default:
            return isBackground ? UIColor(theme.swiftUIBackground) : UIColor(theme.swiftUIForeground)
        case .indexed(let index):
            return UIColor(theme.colorForIndex(index))
        case .rgb(let r, let g, let b):
            return UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        }
    }

    private var visibleLines: [(index: Int, line: TerminalLine)] {
        let start = emulator.screenStart
        let availableLines = emulator.lines.count - start
        let minLinesToShow = emulator.cursorRow + 1
        let linesToShow = emulator.isAlternateScreen ? emulator.rows : max(minLinesToShow, min(availableLines, emulator.rows))

        return (0..<linesToShow).map { screenRow in
            let lineIndex = start + screenRow
            if lineIndex < emulator.lines.count {
                return (index: screenRow, line: emulator.lines[lineIndex])
            } else {
                return (index: screenRow, line: TerminalLine(cells: Array(repeating: TerminalCell(), count: emulator.cols)))
            }
        }
    }
}

// MARK: - Custom UITextView with cursor overlay

class TerminalTextView: UITextView {
    var onTap: (() -> Void)?
    var cursorPosition: CGPoint = .zero
    var cursorSize: CGSize = CGSize(width: 8, height: 16)
    var cursorColor: UIColor = .white
    private var cursorLayer: CALayer?

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // Add cursor layer
        let cursor = CALayer()
        cursor.backgroundColor = cursorColor.withAlphaComponent(0.7).cgColor
        layer.addSublayer(cursor)
        cursorLayer = cursor

        // Single tap to focus keyboard (doesn't interfere with selection)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        tap.numberOfTapsRequired = 1
        tap.delegate = self
        addGestureRecognizer(tap)
    }

    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        // Only focus keyboard if no text is selected
        if selectedRange.length == 0 {
            onTap?()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateCursorPosition()
    }

    func updateCursorPosition() {
        cursorLayer?.frame = CGRect(origin: cursorPosition, size: cursorSize)
        cursorLayer?.backgroundColor = cursorColor.withAlphaComponent(0.7).cgColor
    }

    // Allow copy/paste/select actions
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        switch action {
        case #selector(copy(_:)), #selector(selectAll(_:)), #selector(select(_:)), #selector(paste(_:)):
            return true
        default:
            return false
        }
    }

    override func paste(_ sender: Any?) {
        if let text = UIPasteboard.general.string {
            NotificationCenter.default.post(
                name: .terminalPaste,
                object: nil,
                userInfo: ["text": text]
            )
        }
    }
}

extension TerminalTextView: UIGestureRecognizerDelegate {
    // Allow our tap gesture to work alongside the text view's built-in gestures
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    // Don't let our tap gesture block the long press for selection
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // If it's a long press, let it take priority
        if otherGestureRecognizer is UILongPressGestureRecognizer {
            return true
        }
        return false
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

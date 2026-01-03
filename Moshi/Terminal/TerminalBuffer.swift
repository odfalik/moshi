import Foundation

final class TerminalBuffer {
    private var lines: [BufferLine] = []
    private let maxLines: Int

    var count: Int { lines.count }

    init(maxLines: Int = 10000) {
        self.maxLines = maxLines
    }

    func append(_ line: BufferLine) {
        lines.append(line)

        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }

    func get(at index: Int) -> BufferLine? {
        guard index >= 0 && index < lines.count else { return nil }
        return lines[index]
    }

    func getRange(from: Int, count: Int) -> [BufferLine] {
        let start = max(0, from)
        let end = min(lines.count, start + count)
        return Array(lines[start..<end])
    }

    func search(for pattern: String, options: SearchOptions = SearchOptions()) -> [SearchResult] {
        var results: [SearchResult] = []

        let searchPattern = options.caseSensitive ? pattern : pattern.lowercased()

        for (lineIndex, line) in lines.enumerated() {
            let text = options.caseSensitive ? line.text : line.text.lowercased()

            var searchRange = text.startIndex..<text.endIndex

            while let range = text.range(of: searchPattern, options: options.useRegex ? .regularExpression : [], range: searchRange) {
                let startCol = text.distance(from: text.startIndex, to: range.lowerBound)
                let endCol = text.distance(from: text.startIndex, to: range.upperBound)

                results.append(SearchResult(
                    lineIndex: lineIndex,
                    startCol: startCol,
                    endCol: endCol,
                    matchedText: String(text[range])
                ))

                searchRange = range.upperBound..<text.endIndex
            }
        }

        return results
    }

    func clear() {
        lines.removeAll()
    }

    func export() -> String {
        lines.map { $0.text }.joined(separator: "\n")
    }
}

struct BufferLine {
    var cells: [TerminalCell]
    var wrapped: Bool

    var text: String {
        String(cells.map { $0.character })
    }

    init(cells: [TerminalCell] = [], wrapped: Bool = false) {
        self.cells = cells
        self.wrapped = wrapped
    }

    init(from terminalLine: TerminalLine) {
        self.cells = terminalLine.cells
        self.wrapped = terminalLine.wrapped
    }
}

struct SearchOptions {
    var caseSensitive: Bool = false
    var useRegex: Bool = false
    var wholeWord: Bool = false
}

struct SearchResult: Identifiable {
    let id = UUID()
    let lineIndex: Int
    let startCol: Int
    let endCol: Int
    let matchedText: String
}

// MARK: - Scrollback Management

final class ScrollbackManager: ObservableObject {
    @Published var scrollPosition: Int = 0
    @Published var searchResults: [SearchResult] = []
    @Published var currentSearchIndex: Int = 0

    private let buffer: TerminalBuffer

    init(buffer: TerminalBuffer = TerminalBuffer()) {
        self.buffer = buffer
    }

    func addLine(_ line: TerminalLine) {
        buffer.append(BufferLine(from: line))
    }

    func search(for pattern: String) {
        searchResults = buffer.search(for: pattern)
        currentSearchIndex = 0
    }

    func nextSearchResult() {
        guard !searchResults.isEmpty else { return }
        currentSearchIndex = (currentSearchIndex + 1) % searchResults.count
        scrollToCurrentResult()
    }

    func previousSearchResult() {
        guard !searchResults.isEmpty else { return }
        currentSearchIndex = (currentSearchIndex - 1 + searchResults.count) % searchResults.count
        scrollToCurrentResult()
    }

    private func scrollToCurrentResult() {
        guard currentSearchIndex < searchResults.count else { return }
        scrollPosition = searchResults[currentSearchIndex].lineIndex
    }

    func export() -> String {
        buffer.export()
    }

    func clear() {
        buffer.clear()
        searchResults.removeAll()
        currentSearchIndex = 0
        scrollPosition = 0
    }
}

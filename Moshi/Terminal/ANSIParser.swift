import Foundation

final class ANSIParser {
    enum Token {
        case text(String)
        case escape(EscapeSequence)
        case controlChar(Character)
    }

    enum EscapeSequence: Equatable {
        case cursorUp(Int)
        case cursorDown(Int)
        case cursorForward(Int)
        case cursorBack(Int)
        case cursorPosition(Int, Int)
        case eraseDisplay(Int)
        case eraseLine(Int)
        case sgr([Int])
        case saveCursor
        case restoreCursor
        case alternateScreenOn
        case alternateScreenOff
        case setScrollRegion(Int, Int)
        case insertLines(Int)
        case deleteLines(Int)
        case scrollUp(Int)
        case scrollDown(Int)
        case setTitle(String)
        case unknown
    }

    private enum State {
        case ground
        case escape
        case csi
        case osc
        case oscString
    }

    private var state: State = .ground
    private var params: [Int] = []
    private var currentParam: Int = 0
    private var intermediates: String = ""
    private var oscString: String = ""

    func parse(_ input: String) -> [Token] {
        var tokens: [Token] = []
        var textBuffer = ""

        func flushText() {
            if !textBuffer.isEmpty {
                tokens.append(.text(textBuffer))
                textBuffer = ""
            }
        }

        // Iterate over unicode scalars to ensure CR and LF are handled separately
        // (Swift's Character iteration can combine \r\n into a single grapheme)
        for scalar in input.unicodeScalars {
            let char = Character(scalar)
            switch state {
            case .ground:
                if scalar.value == 0x1B { // ESC
                    flushText()
                    state = .escape
                } else if scalar.value < 32 || scalar.value == 127 { // Control character
                    flushText()
                    tokens.append(.controlChar(char))
                } else {
                    textBuffer.append(char)
                }

            case .escape:
                switch char {
                case "[":
                    state = .csi
                    params = []
                    currentParam = 0
                    intermediates = ""

                case "]":
                    state = .osc
                    oscString = ""

                case "7":
                    tokens.append(.escape(.saveCursor))
                    state = .ground

                case "8":
                    tokens.append(.escape(.restoreCursor))
                    state = .ground

                case "M": // Reverse line feed
                    tokens.append(.escape(.scrollDown(1)))
                    state = .ground

                case "D": // Line feed
                    tokens.append(.escape(.scrollUp(1)))
                    state = .ground

                case "c": // Reset
                    tokens.append(.escape(.sgr([0])))
                    state = .ground

                default:
                    // Unknown escape sequence - go back to ground and re-process this character
                    state = .ground
                    if char.isControlCharacter {
                        tokens.append(.controlChar(char))
                    } else {
                        textBuffer.append(char)
                    }
                }

            case .csi:
                if char.isNumber {
                    currentParam = currentParam * 10 + Int(String(char))!
                } else if char == ";" {
                    params.append(currentParam)
                    currentParam = 0
                } else if char == "?" || char == ">" || char == "!" {
                    intermediates.append(char)
                } else {
                    params.append(currentParam)
                    let sequence = parseCSI(char: char, params: params, intermediates: intermediates)
                    tokens.append(.escape(sequence))
                    state = .ground
                }

            case .osc:
                if char == ";" {
                    state = .oscString
                } else if char.isNumber {
                    // OSC command number - continue collecting
                } else if char == "\u{07}" { // BEL terminates OSC
                    state = .ground
                } else if char == "\u{1B}" { // ESC might be start of ST (ESC \)
                    state = .ground
                } else if char.isControlCharacter {
                    // Control char terminates OSC and should be processed
                    state = .ground
                    tokens.append(.controlChar(char))
                } else {
                    // Other characters - treat as part of OSC string or abort
                    state = .oscString
                    oscString.append(char)
                }

            case .oscString:
                if char == "\u{07}" { // BEL terminates
                    tokens.append(.escape(.setTitle(oscString)))
                    state = .ground
                } else if char == "\u{1B}" {
                    // Could be ST (ESC \) - terminate OSC
                    tokens.append(.escape(.setTitle(oscString)))
                    state = .escape  // Go to escape state to handle potential ST
                } else if char.isControlCharacter {
                    // Control char terminates OSC and should be processed
                    tokens.append(.escape(.setTitle(oscString)))
                    state = .ground
                    tokens.append(.controlChar(char))
                } else {
                    oscString.append(char)
                }
            }
        }

        flushText()
        return tokens
    }

    private func parseCSI(char: Character, params: [Int], intermediates: String) -> EscapeSequence {
        let n = params.first ?? 1
        let m = params.count > 1 ? params[1] : 1

        // Handle private mode sequences (CSI ? Ps h/l)
        if intermediates.contains("?") {
            switch char {
            case "h": // Set mode
                switch n {
                case 1049, 47, 1047: // Alternate screen buffer
                    return .alternateScreenOn
                case 25: // Show cursor
                    return .unknown
                case 1: // Application cursor keys
                    return .unknown
                default:
                    return .unknown
                }

            case "l": // Reset mode
                switch n {
                case 1049, 47, 1047: // Normal screen buffer
                    return .alternateScreenOff
                case 25: // Hide cursor
                    return .unknown
                case 1: // Normal cursor keys
                    return .unknown
                default:
                    return .unknown
                }

            default:
                return .unknown
            }
        }

        // Standard CSI sequences
        switch char {
        case "A": return .cursorUp(max(1, n))
        case "B": return .cursorDown(max(1, n))
        case "C": return .cursorForward(max(1, n))
        case "D": return .cursorBack(max(1, n))
        case "E": return .cursorDown(max(1, n)) // CNL - also moves to column 1
        case "F": return .cursorUp(max(1, n))   // CPL - also moves to column 1
        case "G": return .cursorPosition(0, max(1, n)) // CHA - cursor horizontal absolute
        case "H", "f": return .cursorPosition(n, m) // CUP - cursor position
        case "J": return .eraseDisplay(n)
        case "K": return .eraseLine(n)
        case "L": return .insertLines(max(1, n))
        case "M": return .deleteLines(max(1, n))
        case "S": return .scrollUp(max(1, n))
        case "T": return .scrollDown(max(1, n))
        case "m": return .sgr(params.isEmpty ? [0] : params)
        case "r": return .setScrollRegion(n, m)
        case "s": return .saveCursor
        case "u": return .restoreCursor
        case "d": return .cursorPosition(max(1, n), 0) // VPA - vertical position absolute
        case "@": return .unknown // ICH - insert characters
        case "P": return .unknown // DCH - delete characters
        case "X": return .unknown // ECH - erase characters
        case "c": return .unknown // DA - device attributes
        case "n": return .unknown // DSR - device status report
        case "t": return .unknown // Window manipulation

        default:
            return .unknown
        }
    }

    func reset() {
        state = .ground
        params = []
        currentParam = 0
        intermediates = ""
        oscString = ""
    }
}

// MARK: - Character Extensions

extension Character {
    var isControlCharacter: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return scalar.value < 32 || scalar.value == 127
    }
}

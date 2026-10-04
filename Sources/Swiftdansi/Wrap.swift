import DisplayWidth
import Foundation

/// Visible width ignoring ANSI escape sequences.
public func visibleWidth(_ text: String) -> Int {
    let stripped = stripANSI(text)
    return DisplayWidth()(stripped)
}

/// Strip ANSI escape sequences.
public func stripANSI(_ text: String) -> String {
    strippingANSISequences(text)
}

/// Wrap text at word boundaries, splitting long tokens when necessary to stay within width.
public func wrapText(_ text: String, width: Int, wrap: Bool) -> [String] {
    wrapText(text, width: width, wrap: wrap, ansiProtection: nil)
}

func wrapText(_ text: String, width: Int, wrap: Bool, ansiProtection: ANSISequenceProtection?) -> [String] {
    guard wrap, width > 0 else { return [text] }
    let tokens = text.matches(of: /(\s+|\S+)/).map { String($0.0) }
    var lines: [String] = []
    var current = ""
    var currentWidth = 0

    func trimEndSpaces(_ value: String) -> String {
        value.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
    }

    func orphanPhraseTail(_ value: String) -> String? {
        let trimmed = trimEndSpaces(value)
        if let range = trimmed.range(
            of: #"\b(with|in|on|of|to|for)\s+(a|an|the)$"#,
            options: [.regularExpression, .caseInsensitive])
        {
            return String(trimmed[range])
        }
        if let range = trimmed.range(
            of: #"\b(a|an|the|to|of|with|and|or|in|on|for)$"#,
            options: [.regularExpression, .caseInsensitive])
        {
            return String(trimmed[range])
        }
        return nil
    }

    for token in tokens {
        let w = visibleWidth(token)
        let isSpace = token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !current.isEmpty, currentWidth + w > width, !isSpace {
            let nextWord = token.replacingOccurrences(of: #"^\s+"#, with: "", options: .regularExpression)
            let currentNoTrail = trimEndSpaces(current)
            if let tail = orphanPhraseTail(currentNoTrail), currentNoTrail.count > tail.count {
                let base = trimEndSpaces(String(currentNoTrail.dropLast(tail.count)))
                if !base.isEmpty {
                    lines.append(base)
                    current = "\(tail) \(nextWord)"
                    currentWidth = visibleWidth(current)
                    continue
                }
            }
            lines.append(currentNoTrail)
            current = nextWord
            currentWidth = visibleWidth(current)
            continue
        }
        current += token
        currentWidth += w
    }
    if !current.isEmpty { lines.append(trimEndSpaces(current)) }
    if lines.isEmpty { lines.append("") }
    return lines.flatMap { hardWrapText($0, width: width, ansiProtection: ansiProtection) }
}

/// Wrap text accounting for a prefix width (e.g., quote marker).
public func wrapWithPrefix(_ text: String, width: Int, wrap: Bool, prefix: String = "") -> [String] {
    wrapWithPrefix(text, width: width, wrap: wrap, prefix: prefix, ansiProtection: nil)
}

func wrapWithPrefix(
    _ text: String,
    width: Int,
    wrap: Bool,
    prefix: String,
    ansiProtection: ANSISequenceProtection?) -> [String]
{
    guard wrap else { return text.split(separator: "\n", omittingEmptySubsequences: false).map { prefix + $0 } }
    let available = max(1, width - visibleWidth(prefix))
    var out: [String] = []
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        for chunk in wrapText(String(line), width: available, wrap: wrap, ansiProtection: ansiProtection) {
            out.append(prefix + chunk)
        }
    }
    return out
}

/// Split a long line at display-width boundaries while retaining active terminal styles.
/// Carry active styling and links across lines so each rendered line is self-contained.
func hardWrapText(
    _ text: String,
    width: Int,
    ansiProtection: ANSISequenceProtection?) -> [String]
{
    guard width > 0, visibleWidth(text) > width else { return [text] }
    var lines: [String] = []
    var line = ""
    var accumulator = VisibleWidthAccumulator()
    var cursor = text.startIndex
    var activeSGR = ""
    var activeHyperlink = ""
    var hyperlinkTerminator: ANSIOSCTerminator?
    var hasActiveSGR = false

    func finishLine() {
        if hasActiveSGR { line += "\u{001B}[0m" }
        if let hyperlinkTerminator { line += hyperlinkTerminator.hyperlinkClose }
        lines.append(line)
        line = activeSGR + activeHyperlink
        accumulator = VisibleWidthAccumulator()
    }

    func appendVisible(_ fragment: String) {
        if !accumulator.append(fragment, maximum: width) {
            if visibleWidth(line) > 0 {
                finishLine()
                _ = accumulator.append(fragment, maximum: width)
            }
        }
        line += fragment
    }

    func appendSequence(_ sequence: Substring, original: Substring) {
        line.append(contentsOf: sequence)
        updateANSIState(
            original,
            hasActiveSGR: &hasActiveSGR,
            activeHyperlinkTerminator: &hyperlinkTerminator)
        if original.hasSuffix("m"), original.hasPrefix("\u{001B}[") || original.hasPrefix("\u{009B}") {
            activeSGR = hasActiveSGR ? activeSGR + String(sequence) : ""
        }
        if original.hasPrefix("\u{001B}]8;") || original.hasPrefix("\u{009D}8;") {
            activeHyperlink = hyperlinkTerminator == nil ? "" : String(sequence)
        }
    }

    while cursor < text.endIndex {
        switch scanANSISequence(in: text, from: cursor) {
        case let .complete(end):
            let sequence = text[cursor..<end]
            let original = ansiProtection?.originalSequence(for: sequence)?[...] ?? sequence
            appendSequence(sequence, original: original)
            cursor = end
            continue
        case let .completeWithSuffix(end, controlEnd, suffix):
            let sequence = text[cursor..<controlEnd]
            appendSequence(sequence, original: sequence)
            appendVisible(suffix)
            cursor = end
            continue
        case let .recovered(end, suffix):
            appendVisible(suffix)
            cursor = end
            continue
        case let .malformed(recovery):
            cursor = recovery
            continue
        case .incomplete:
            cursor = text.endIndex
            continue
        case .notControl:
            break
        }
        let next = text.index(after: cursor)
        appendVisible(String(text[cursor..<next]))
        cursor = next
    }
    lines.append(line)
    return lines
}

func updateANSIState(
    _ sequence: Substring,
    hasActiveSGR: inout Bool,
    activeHyperlinkTerminator: inout ANSIOSCTerminator?)
{
    let sgrPrefixLength = if sequence.hasPrefix("\u{001B}[") {
        2
    } else if sequence.hasPrefix("\u{009B}") {
        1
    } else {
        0
    }
    if sgrPrefixLength > 0, sequence.hasSuffix("m") {
        let parameters = sequence.dropFirst(sgrPrefixLength).dropLast()
        for parameter in parameters.split(separator: ";", omittingEmptySubsequences: false) {
            hasActiveSGR = parameter != "0" && !parameter.isEmpty
        }
        return
    }

    let hyperlinkPrefixLength = if sequence.hasPrefix("\u{001B}]8;") {
        4
    } else if sequence.hasPrefix("\u{009D}8;") {
        3
    } else {
        0
    }
    guard hyperlinkPrefixLength > 0 else { return }
    var payload = sequence.dropFirst(hyperlinkPrefixLength)
    if payload.hasSuffix("\u{0007}") {
        payload = payload.dropLast()
    } else if payload.hasSuffix("\u{001B}\\") {
        payload = payload.dropLast(2)
    } else if payload.hasSuffix("\u{009C}") {
        payload = payload.dropLast()
    }
    guard let separator = payload.firstIndex(of: ";") else { return }
    let isOpen = !payload[payload.index(after: separator)...].isEmpty
    activeHyperlinkTerminator = isOpen ? ansiOSCTerminator(in: sequence) : nil
}

import Testing
@testable import Swiftdansi

struct WrapTextTests {
    @Test
    func `long words and Japanese text stay inside width`() {
        for value in ["https://example.com/averylongpathwithoutspaces", "日本語の説明を省略しない表示にする"] {
            let lines = wrapText(value, width: 10, wrap: true)
            #expect(lines.count > 1)
            #expect(lines.allSatisfy { visibleWidth($0) <= 10 })
            #expect(lines.joined() == value)
        }
    }

    @Test
    func `paragraph and quote include prefixes in width budget`() {
        let text = "日本語の説明を省略しない表示にする"
        let paragraph = strip(text, options: RenderOptions(wrap: true, width: 12))
        let quote = strip("> \(text)", options: RenderOptions(wrap: true, width: 12))
        let paragraphLines = paragraph.split(separator: "\n").map(String.init)
        let quoteLines = quote.split(separator: "\n").map(String.init)
        #expect(paragraphLines.allSatisfy { visibleWidth($0) <= 12 })
        #expect(paragraphLines.joined() == text)
        #expect(quoteLines.allSatisfy { visibleWidth($0) <= 12 })
        #expect(quoteLines.allSatisfy { $0.hasPrefix("│ ") })
        #expect(quoteLines.map { String($0.dropFirst(2)) }.joined() == text)
    }

    @Test
    func `disabled wrapping keeps long words intact`() {
        let text = "https://example.com/averylongpathwithoutspaces"
        #expect(wrapText(text, width: 10, wrap: false) == [text])
    }

    @Test
    func `long styled words close styles on each line`() {
        let styled = "\u{001B}[1mabcdefghijklmnopqrst\u{001B}[0m"
        let lines = wrapText(styled, width: 10, wrap: true)
        #expect(lines.count == 2)
        #expect(lines.allSatisfy { visibleWidth($0) <= 10 })
        #expect(lines.allSatisfy { $0.contains("\u{001B}[1m") && $0.contains("\u{001B}[0m") })
        #expect(lines.map(stripANSI).joined() == "abcdefghijklmnopqrst")
    }
}

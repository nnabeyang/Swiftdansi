import Foundation
import Testing
@testable import Swiftdansi

struct TableWrapTests {
    @Test
    func `table preserves long tokens when wrapping is disabled`() {
        let md = """
        | Value |
        | --- |
        | abcdefghijklmnopqrstuvwx |
        """
        let out = strip(md, options: RenderOptions(wrap: false, width: 12, tablePadding: 0, tableTruncate: false))
        #expect(out.contains("abcdefghijklmnopqrstuvwx"))
        #expect(!out.contains("…"))
    }

    @Test
    func `table wraps long tokens without dropping characters`() {
        let md = """
        | Path | Reason |
        | --- | --- |
        | Tests/SwiftdansiTests/TableWrapTests.swift:11 | 日本語の説明を省略しない表示にする |
        """
        let out = strip(md, options: RenderOptions(wrap: true, width: 40, tablePadding: 0, tableTruncate: false))
        let rows = out.split(separator: "\n").map(String.init)
        #expect(rows.allSatisfy { visibleWidth($0) <= 40 })
        #expect(rows.filter { $0.hasPrefix("│") }.allSatisfy { $0.hasSuffix("│") })
        let columns = rows.filter { $0.hasPrefix("│") }.map {
            $0.split(separator: "│", omittingEmptySubsequences: false).dropFirst().dropLast()
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
        #expect(columns.map { $0[0] }.joined().contains("Tests/SwiftdansiTests/TableWrapTests.swift:11"))
        #expect(columns.map { $0[1] }.joined().contains("日本語の説明を省略しない表示にする"))
    }

    @Test
    func `table long token wrapping keeps styling inside each row`() {
        let md = """
        | Value |
        | --- |
        | **日本語の説明を省略しない表示にする日本語の説明を省略しない表示にする** |
        """
        let out = render(
            md,
            options: RenderOptions(wrap: true, width: 18, color: true, tablePadding: 0, tableTruncate: false))
        let rows = out.split(separator: "\n").map(String.init)
        #expect(rows.allSatisfy { visibleWidth($0) <= 18 })
        let body = rows.filter { stripANSI($0).contains("日本語") }
        #expect(body.count > 1)
        #expect(body.allSatisfy { $0.contains("\u{001B}[1m") && $0.contains("\u{001B}[0m") })
        #expect(body.allSatisfy { !$0.contains("\u{001B}[2m") })
    }

    @Test
    func `table long linked token closes hyperlinks on every row`() {
        let md = """
        | Value |
        | --- |
        | [abcdefghijklmnopqrstuvwx](https://example.com) |
        """
        let out = render(
            md,
            options: RenderOptions(
                wrap: true, width: 12, hyperlinks: true, color: true, tablePadding: 0, tableTruncate: false))
        let rows = out.split(separator: "\n").map(String.init)
        #expect(rows.allSatisfy { visibleWidth($0) <= 12 })
        let body = rows.filter { stripANSI($0).contains("abcd") || stripANSI($0).contains("klmn") }
        #expect(body.count > 1)
        #expect(body.allSatisfy { $0.contains("\u{001B}]8;;https://example.com\u{0007}") })
        #expect(body.allSatisfy { $0.contains("\u{001B}]8;;\u{0007}") })
    }

    @Test
    func `a dim link suffix does not dim the adjacent wrapped table cell`() {
        let reason = "日本語の説明を省略しない表示にする日本語の説明を省略しない表示にする"
        let md = """
        | Path | Reason |
        | --- | --- |
        | Sources/Issue.swift:244 | \(reason) |
        | [abcdefghijklmnopqrstuvwxabcdefghijklmnopqrstuvwx](https://example.com) | **\(reason)** |
        """
        let out = render(
            md,
            options: RenderOptions(wrap: true, width: 92, color: true, tablePadding: 1, tableTruncate: false))
        let rows = out.split(separator: "\n").map(String.init)
        let body = rows.filter { stripANSI($0).contains("表示にする") }
        #expect(body.count == 4)
        #expect(body.allSatisfy { $0.contains("\u{001B}[0m│") })
        let boldBody = body.filter { $0.contains("\u{001B}[1m") }
        #expect(boldBody.count == 2)
        for line in boldBody {
            let cells = line.components(separatedBy: "│")
            #expect(cells.count == 4)
            #expect(cells[1].hasSuffix("\u{001B}[0m"))
            #expect(cells[2].contains("\u{001B}[1m"))
            #expect(!cells[2].contains("\u{001B}[2m"))
        }
    }
}

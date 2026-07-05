import Foundation

struct MarkdownSyncBlock: Identifiable, Equatable {
    let id: Int
    let markdown: String
    let startOffset: Int
    let endOffset: Int

    var length: Int {
        max(1, endOffset - startOffset)
    }
}

enum MarkdownSyncBlockParser {
    static func parse(_ text: String) -> [MarkdownSyncBlock] {
        let source = text as NSString
        let lines = makeLines(text)
        guard !lines.isEmpty else {
            return [MarkdownSyncBlock(id: 0, markdown: "", startOffset: 0, endOffset: 0)]
        }

        var blocks: [MarkdownSyncBlock] = []
        var index = 0

        while index < lines.count {
            if lines[index].isBlank {
                if let last = blocks.popLast() {
                    let end = lines[index].endOffset
                    blocks.append(
                        MarkdownSyncBlock(
                            id: last.id,
                            markdown: source.substring(with: NSRange(location: last.startOffset, length: end - last.startOffset)),
                            startOffset: last.startOffset,
                            endOffset: end
                        )
                    )
                }
                index += 1
                continue
            }

            let startLine = index
            let endLine: Int

            if let marker = fenceMarker(lines[index].trimmed) {
                endLine = consumeFence(from: index, marker: marker, lines: lines)
            } else if isHeading(lines[index].trimmed) || isThematicBreak(lines[index].trimmed) {
                endLine = index
            } else if isTableLine(lines[index].trimmed) {
                endLine = consumeTable(from: index, lines: lines)
            } else if isListLine(lines[index].trimmed) {
                endLine = consumeList(from: index, lines: lines)
            } else if isBlockquoteLine(lines[index].trimmed) {
                endLine = consumeBlockquote(from: index, lines: lines)
            } else {
                endLine = consumeParagraph(from: index, lines: lines)
            }

            let trailingEndLine = consumeTrailingBlanks(after: endLine, lines: lines)
            let start = lines[startLine].startOffset
            let end = lines[trailingEndLine].endOffset
            let markdown = source.substring(with: NSRange(location: start, length: end - start))
            blocks.append(
                MarkdownSyncBlock(
                    id: blocks.count,
                    markdown: markdown,
                    startOffset: start,
                    endOffset: end
                )
            )
            index = trailingEndLine + 1
        }

        if blocks.isEmpty {
            return [MarkdownSyncBlock(id: 0, markdown: text, startOffset: 0, endOffset: source.length)]
        }
        return blocks
    }

    private struct SourceLine {
        let text: String
        let startOffset: Int
        let endOffset: Int

        var trimmed: String {
            text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var isBlank: Bool {
            trimmed.isEmpty
        }
    }

    private static func makeLines(_ text: String) -> [SourceLine] {
        let parts = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty else { return [] }

        var lines: [SourceLine] = []
        var offset = 0
        for (index, part) in parts.enumerated() {
            let hasNewline = index < parts.count - 1
            let length = (part as NSString).length + (hasNewline ? 1 : 0)
            lines.append(SourceLine(text: part, startOffset: offset, endOffset: offset + length))
            offset += length
        }
        return lines
    }

    private static func consumeTrailingBlanks(after line: Int, lines: [SourceLine]) -> Int {
        var end = line
        var next = line + 1
        while next < lines.count, lines[next].isBlank {
            end = next
            next += 1
        }
        return end
    }

    private static func fenceMarker(_ trimmed: String) -> String? {
        if trimmed.hasPrefix("```") { return "```" }
        if trimmed.hasPrefix("~~~") { return "~~~" }
        return nil
    }

    private static func consumeFence(from index: Int, marker: String, lines: [SourceLine]) -> Int {
        var cursor = index + 1
        while cursor < lines.count {
            if lines[cursor].trimmed.hasPrefix(marker) {
                return cursor
            }
            cursor += 1
        }
        return lines.count - 1
    }

    private static func isHeading(_ trimmed: String) -> Bool {
        let hashes = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), trimmed.count > hashes else { return false }
        let afterHashes = trimmed.dropFirst(hashes)
        return afterHashes.first?.isWhitespace == true
    }

    private static func isThematicBreak(_ trimmed: String) -> Bool {
        ["---", "***", "___"].contains(trimmed)
    }

    private static func isTableLine(_ trimmed: String) -> Bool {
        trimmed.hasPrefix("|") && trimmed.dropFirst().contains("|")
    }

    private static func consumeTable(from index: Int, lines: [SourceLine]) -> Int {
        var cursor = index
        while cursor + 1 < lines.count, isTableLine(lines[cursor + 1].trimmed) {
            cursor += 1
        }
        return cursor
    }

    private static func isListLine(_ trimmed: String) -> Bool {
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return true
        }
        if trimmed.hasPrefix("- [") || trimmed.hasPrefix("* [") || trimmed.hasPrefix("+ [") {
            return true
        }

        var sawDigit = false
        var cursor = trimmed.startIndex
        while cursor < trimmed.endIndex, trimmed[cursor].isNumber {
            sawDigit = true
            cursor = trimmed.index(after: cursor)
        }
        guard sawDigit, cursor < trimmed.endIndex, trimmed[cursor] == "." else { return false }
        let afterDot = trimmed.index(after: cursor)
        return afterDot < trimmed.endIndex && trimmed[afterDot].isWhitespace
    }

    private static func consumeList(from index: Int, lines: [SourceLine]) -> Int {
        var cursor = index
        while cursor + 1 < lines.count {
            let next = lines[cursor + 1]
            if next.isBlank {
                break
            }
            if isListLine(next.trimmed) || next.text.hasPrefix(" ") || next.text.hasPrefix("\t") {
                cursor += 1
            } else {
                break
            }
        }
        return cursor
    }

    private static func isBlockquoteLine(_ trimmed: String) -> Bool {
        trimmed.hasPrefix(">")
    }

    private static func consumeBlockquote(from index: Int, lines: [SourceLine]) -> Int {
        var cursor = index
        while cursor + 1 < lines.count, isBlockquoteLine(lines[cursor + 1].trimmed) {
            cursor += 1
        }
        return cursor
    }

    private static func consumeParagraph(from index: Int, lines: [SourceLine]) -> Int {
        var cursor = index
        while cursor + 1 < lines.count {
            let next = lines[cursor + 1]
            if next.isBlank
                || isHeading(next.trimmed)
                || fenceMarker(next.trimmed) != nil
                || isTableLine(next.trimmed)
                || isListLine(next.trimmed)
                || isBlockquoteLine(next.trimmed)
                || isThematicBreak(next.trimmed) {
                break
            }
            cursor += 1
        }
        return cursor
    }
}

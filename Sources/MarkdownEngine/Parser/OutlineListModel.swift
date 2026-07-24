import Foundation

struct OutlineListItem: Equatable {
    let lineRange: NSRange
    let markerRange: NSRange
    let depth: Int
    let isBullet: Bool
    let isTask: Bool
    let hasChildren: Bool
    let descendantRange: NSRange?
    let reference: OutlineItemReference
}

enum OutlineListModel {
    static func items(
        in text: String,
        precomputedBlocks: [Block]? = nil
    ) -> [OutlineListItem] {
        let nsText = text as NSString
        let blocks = precomputedBlocks ?? BlockParser.parse(text)
        var parsedItems: [OutlineListItem] = []

        for block in blocks where block.kind == .list {
            var cursor = block.range.location
            let end = NSMaxRange(block.range)
            while cursor < end {
                let lineRange = nsText.lineRange(
                    for: NSRange(location: cursor, length: 0)
                )
                if let item = parsedItem(lineRange: lineRange, in: nsText) {
                    parsedItems.append(item)
                }
                cursor = NSMaxRange(lineRange)
            }
        }

        return parsedItems.indices.map { index in
            let item = parsedItems[index]
            guard index + 1 < parsedItems.count else { return item }
            let firstChild = parsedItems[index + 1]
            let gap = NSRange(
                location: NSMaxRange(item.lineRange),
                length: max(0, firstChild.lineRange.location - NSMaxRange(item.lineRange))
            )
            guard firstChild.depth > item.depth,
                  firstHierarchyBreak(in: gap, parentDepth: item.depth, text: nsText) == nil
            else {
                return item
            }

            var descendantEnd = nsText.length
            var previousEnd = NSMaxRange(firstChild.lineRange)
            var descendantIndex = index + 2
            while descendantIndex < parsedItems.count {
                let candidate = parsedItems[descendantIndex]
                let candidateGap = NSRange(
                    location: previousEnd,
                    length: max(0, candidate.lineRange.location - previousEnd)
                )
                if let breakLocation = firstHierarchyBreak(
                    in: candidateGap,
                    parentDepth: item.depth,
                    text: nsText
                ) {
                    descendantEnd = breakLocation
                    break
                }
                if candidate.depth <= item.depth {
                    descendantEnd = candidate.lineRange.location
                    break
                }
                previousEnd = NSMaxRange(candidate.lineRange)
                descendantIndex += 1
            }
            if descendantIndex == parsedItems.count,
               let breakLocation = firstHierarchyBreak(
                   in: NSRange(
                       location: previousEnd,
                       length: max(0, nsText.length - previousEnd)
                   ),
                   parentDepth: item.depth,
                   text: nsText
               ) {
                descendantEnd = breakLocation
            }

            let descendantStart = NSMaxRange(item.lineRange)
            return OutlineListItem(
                lineRange: item.lineRange,
                markerRange: item.markerRange,
                depth: item.depth,
                isBullet: item.isBullet,
                isTask: item.isTask,
                hasChildren: true,
                descendantRange: NSRange(
                    location: descendantStart,
                    length: max(0, descendantEnd - descendantStart)
                ),
                reference: item.reference
            )
        }
    }

    static func nestedBlankLineLocations(
        in blocks: [Block],
        outlineItems: [OutlineListItem]
    ) -> Set<Int> {
        let descendantRanges = outlineItems.compactMap(\.descendantRange)
        guard !descendantRanges.isEmpty else { return [] }
        return Set(
            blocks.compactMap { block in
                guard block.kind == .blank,
                      descendantRanges.contains(where: {
                          NSIntersectionRange($0, block.range).length > 0
                      })
                else {
                    return nil
                }
                return block.range.location
            }
        )
    }

    private static func parsedItem(
        lineRange: NSRange,
        in text: NSString
    ) -> OutlineListItem? {
        let end = NSMaxRange(lineRange)
        var cursor = lineRange.location
        while cursor < end {
            let character = text.character(at: cursor)
            guard character == 0x20 || character == 0x09 else { break }
            cursor += 1
        }
        let whitespaceRange = NSRange(
            location: lineRange.location,
            length: cursor - lineRange.location
        )
        let markerStart = cursor
        guard cursor < end else { return nil }
        let markerCharacter = text.character(at: cursor)
        let isBullet = markerCharacter == 0x2D
            || markerCharacter == 0x2A
            || markerCharacter == 0x2B
        if isBullet {
            cursor += 1
        } else {
            var digits = 0
            while cursor < end,
                  text.character(at: cursor) >= 0x30,
                  text.character(at: cursor) <= 0x39,
                  digits < 9 {
                cursor += 1
                digits += 1
            }
            guard digits > 0, cursor < end else { return nil }
            let terminator = text.character(at: cursor)
            guard terminator == 0x2E || terminator == 0x29 else { return nil }
            cursor += 1
        }
        let markerRange = NSRange(
            location: markerStart,
            length: cursor - markerStart
        )
        guard cursor < end else { return nil }
        let separator = text.character(at: cursor)
        guard separator == 0x20 || separator == 0x09 else { return nil }
        while cursor < end {
            let character = text.character(at: cursor)
            guard character == 0x20 || character == 0x09 else { break }
            cursor += 1
        }
        let isTask = isBullet
            && cursor + 2 < end
            && text.character(at: cursor) == 0x5B
            && text.character(at: cursor + 2) == 0x5D
            && [0x20, 0x78, 0x58].contains(text.character(at: cursor + 1))
        let lineText = text.substring(with: trimmedLineRange(lineRange, in: text))
        return OutlineListItem(
            lineRange: lineRange,
            markerRange: markerRange,
            depth: MarkdownLists.indentLevel(
                from: text.substring(with: whitespaceRange)
            ),
            isBullet: isBullet && !isTask,
            isTask: isTask,
            hasChildren: false,
            descendantRange: nil,
            reference: OutlineItemReference(
                markerLocation: markerStart,
                lineFingerprint: fingerprint(lineText)
            )
        )
    }

    private static func firstHierarchyBreak(
        in range: NSRange,
        parentDepth: Int,
        text: NSString
    ) -> Int? {
        var cursor = range.location
        let end = NSMaxRange(range)
        while cursor < end {
            let fullLine = text.lineRange(
                for: NSRange(location: cursor, length: 0)
            )
            let lineRange = NSIntersectionRange(fullLine, range)
            let line = text.substring(with: lineRange)
            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let leadingWhitespace = line.prefix {
                    $0 == " " || $0 == "\t"
                }
                if MarkdownLists.indentLevel(
                    from: String(leadingWhitespace)
                ) <= parentDepth {
                    return lineRange.location
                }
            }
            let next = NSMaxRange(fullLine)
            guard next > cursor else { break }
            cursor = next
        }
        return nil
    }

    private static func trimmedLineRange(_ range: NSRange, in text: NSString) -> NSRange {
        var result = range
        while result.length > 0 {
            let last = text.character(at: NSMaxRange(result) - 1)
            guard last == 0x0A || last == 0x0D else { break }
            result.length -= 1
        }
        return result
    }

    private static func fingerprint(_ value: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}

import AppKit

enum BulletItemMoveDirection {
    case up
    case down
}

enum BulletItemMoveSegment: Equatable {
    case source(NSRange)
    case dedentedSource(NSRange)
}

struct BulletItemMoveEdit: Equatable {
    let range: NSRange
    let segments: [BulletItemMoveSegment]
    let selection: NSRange

    func replacement(in text: String) -> String {
        let source = NSAttributedString(string: text)
        return attributedReplacement(from: source).string
    }

    func attributedReplacement(
        from source: NSAttributedString
    ) -> NSAttributedString {
        let replacement = NSMutableAttributedString()
        for segment in segments {
            switch segment {
            case .source(let range):
                replacement.append(source.attributedSubstring(from: range))
            case .dedentedSource(let range):
                let substring = NSMutableAttributedString(
                    attributedString: source.attributedSubstring(from: range)
                )
                for removal in Self.indentRemovalRanges(
                    in: substring.string
                ).reversed() {
                    substring.deleteCharacters(in: removal)
                }
                replacement.append(substring)
            }
        }
        return replacement
    }

    fileprivate static func mappedDedentedOffset(
        _ offset: Int,
        in text: String
    ) -> Int {
        var removedBefore = 0
        for range in indentRemovalRanges(in: text) {
            if offset <= range.location { break }
            if offset < NSMaxRange(range) {
                return range.location - removedBefore
            }
            removedBefore += range.length
        }
        return max(0, offset - removedBefore)
    }

    private static func indentRemovalRanges(in text: String) -> [NSRange] {
        let source = text as NSString
        var result: [NSRange] = []
        var lineStart = 0

        while lineStart < source.length {
            let lineRange = source.lineRange(
                for: NSRange(location: lineStart, length: 0)
            )
            var removalLength = 0
            if source.character(at: lineStart) == 0x09 {
                removalLength = 1
            } else {
                while removalLength < 2,
                      lineStart + removalLength < NSMaxRange(lineRange),
                      source.character(at: lineStart + removalLength) == 0x20 {
                    removalLength += 1
                }
            }
            if removalLength > 0 {
                result.append(
                    NSRange(location: lineStart, length: removalLength)
                )
            }
            let next = NSMaxRange(lineRange)
            guard next > lineStart else { break }
            lineStart = next
        }
        return result
    }
}

enum BulletItemMovement {
    static func edit(
        in text: String,
        selection: NSRange,
        direction: BulletItemMoveDirection
    ) -> BulletItemMoveEdit? {
        let source = text as NSString
        guard source.length > 0,
              selection.location >= 0,
              NSMaxRange(selection) <= source.length else { return nil }

        let blocks = BlockParser.parse(text)
        let items = OutlineListModel.items(
            in: text,
            precomputedBlocks: blocks
        )
        guard !items.isEmpty else { return nil }

        let parentIndices = items.indices.map {
            parentIndex(of: $0, in: items)
        }
        let blockIndices = items.map { item in
            blocks.firstIndex {
                $0.kind == .list
                    && NSLocationInRange(item.markerRange.location, $0.range)
            }
        }
        let touched = touchedItemIndices(
            selection: selection,
            documentLength: source.length,
            items: items
        )
        guard !touched.isEmpty else { return nil }

        let selectedRoots = touched.filter { index in
            var ancestor = parentIndices[index]
            while let current = ancestor {
                if touched.contains(current) { return false }
                ancestor = parentIndices[current]
            }
            return true
        }
        guard let firstRoot = selectedRoots.first,
              let lastRoot = selectedRoots.last,
              let blockIndex = blockIndices[firstRoot] else { return nil }

        let depth = items[firstRoot].depth
        let parent = parentIndices[firstRoot]
        guard selectedRoots.allSatisfy({
            items[$0].depth == depth
                && parentIndices[$0] == parent
                && blockIndices[$0] == blockIndex
        }) else { return nil }

        let siblings = items.indices.filter {
            items[$0].depth == depth
                && parentIndices[$0] == parent
                && blockIndices[$0] == blockIndex
        }
        guard let firstSiblingPosition = siblings.firstIndex(of: firstRoot),
              let lastSiblingPosition = siblings.firstIndex(of: lastRoot),
              Array(siblings[firstSiblingPosition...lastSiblingPosition])
                == selectedRoots else { return nil }

        let selectedRange = NSRange(
            location: items[firstRoot].lineRange.location,
            length: NSMaxRange(subtreeRange(of: items[lastRoot]))
                - items[firstRoot].lineRange.location
        )
        guard selection.location >= selectedRange.location,
              NSMaxRange(selection) <= NSMaxRange(selectedRange) else {
            return nil
        }

        let relativeSelection = NSRange(
            location: selection.location - selectedRange.location,
            length: selection.length
        )

        switch direction {
        case .up:
            if firstSiblingPosition > siblings.startIndex {
                let previous = siblings[firstSiblingPosition - 1]
                return sameLevelMoveUp(
                    source: source,
                    selectedRange: selectedRange,
                    previousRange: subtreeRange(of: items[previous]),
                    relativeSelection: relativeSelection
                )
            }
            guard let parent else { return nil }
            return liftedMoveUp(
                source: source,
                selectedRange: selectedRange,
                parentLineRange: items[parent].lineRange,
                relativeSelection: relativeSelection
            )

        case .down:
            if lastSiblingPosition + 1 < siblings.endIndex {
                let next = siblings[lastSiblingPosition + 1]
                return sameLevelMoveDown(
                    source: source,
                    selectedRange: selectedRange,
                    nextRange: subtreeRange(of: items[next]),
                    relativeSelection: relativeSelection
                )
            }
            guard let parent,
                  let parentBlockIndex = blockIndices[parent] else {
                return nil
            }
            let parentSiblings = items.indices.filter {
                items[$0].depth == items[parent].depth
                    && parentIndices[$0] == parentIndices[parent]
                    && blockIndices[$0] == parentBlockIndex
            }
            guard let parentPosition = parentSiblings.firstIndex(of: parent),
                  parentPosition + 1 < parentSiblings.endIndex else {
                return nil
            }
            let nextParentSibling = parentSiblings[parentPosition + 1]
            return liftedMoveDown(
                source: source,
                selectedRange: selectedRange,
                nextRange: subtreeRange(of: items[nextParentSibling]),
                relativeSelection: relativeSelection
            )
        }
    }

    private static func sameLevelMoveUp(
        source: NSString,
        selectedRange: NSRange,
        previousRange: NSRange,
        relativeSelection: NSRange
    ) -> BulletItemMoveEdit {
        let selected = splitTrailingLineTerminator(
            from: selectedRange,
            in: source
        )
        let previous = splitTrailingLineTerminator(
            from: previousRange,
            in: source
        )
        let gap = NSRange(
            location: NSMaxRange(previousRange),
            length: selectedRange.location - NSMaxRange(previousRange)
        )
        return BulletItemMoveEdit(
            range: NSRange(
                location: previousRange.location,
                length: NSMaxRange(selectedRange) - previousRange.location
            ),
            segments: compactSegments([
                .source(selected.body),
                .source(previous.terminator),
                .source(gap),
                .source(previous.body),
                .source(selected.terminator),
            ]),
            selection: NSRange(
                location: previousRange.location + relativeSelection.location,
                length: relativeSelection.length
            )
        )
    }

    private static func sameLevelMoveDown(
        source: NSString,
        selectedRange: NSRange,
        nextRange: NSRange,
        relativeSelection: NSRange
    ) -> BulletItemMoveEdit {
        let selected = splitTrailingLineTerminator(
            from: selectedRange,
            in: source
        )
        let next = splitTrailingLineTerminator(
            from: nextRange,
            in: source
        )
        let gap = NSRange(
            location: NSMaxRange(selectedRange),
            length: nextRange.location - NSMaxRange(selectedRange)
        )
        let movedStart = selectedRange.location
            + next.body.length
            + selected.terminator.length
            + gap.length
        return BulletItemMoveEdit(
            range: NSRange(
                location: selectedRange.location,
                length: NSMaxRange(nextRange) - selectedRange.location
            ),
            segments: compactSegments([
                .source(next.body),
                .source(selected.terminator),
                .source(gap),
                .source(selected.body),
                .source(next.terminator),
            ]),
            selection: NSRange(
                location: movedStart + relativeSelection.location,
                length: relativeSelection.length
            )
        )
    }

    private static func liftedMoveUp(
        source: NSString,
        selectedRange: NSRange,
        parentLineRange: NSRange,
        relativeSelection: NSRange
    ) -> BulletItemMoveEdit? {
        guard NSMaxRange(parentLineRange) <= selectedRange.location else {
            return nil
        }
        let selected = splitTrailingLineTerminator(
            from: selectedRange,
            in: source
        )
        let parentLine = splitTrailingLineTerminator(
            from: parentLineRange,
            in: source
        )
        let gap = NSRange(
            location: NSMaxRange(parentLineRange),
            length: selectedRange.location - NSMaxRange(parentLineRange)
        )
        let selectedText = source.substring(with: selectedRange)
        let mappedSelection = mappedSelection(
            relativeSelection,
            throughDedentOf: selectedText
        )
        return BulletItemMoveEdit(
            range: NSRange(
                location: parentLineRange.location,
                length: NSMaxRange(selectedRange) - parentLineRange.location
            ),
            segments: compactSegments([
                .dedentedSource(selected.body),
                .source(parentLine.terminator),
                .source(parentLine.body),
                .source(selected.terminator),
                .source(gap),
            ]),
            selection: NSRange(
                location: parentLineRange.location + mappedSelection.location,
                length: mappedSelection.length
            )
        )
    }

    private static func liftedMoveDown(
        source: NSString,
        selectedRange: NSRange,
        nextRange: NSRange,
        relativeSelection: NSRange
    ) -> BulletItemMoveEdit? {
        guard NSMaxRange(selectedRange) <= nextRange.location else {
            return nil
        }
        let selected = splitTrailingLineTerminator(
            from: selectedRange,
            in: source
        )
        let next = splitTrailingLineTerminator(
            from: nextRange,
            in: source
        )
        let gap = NSRange(
            location: NSMaxRange(selectedRange),
            length: nextRange.location - NSMaxRange(selectedRange)
        )
        let selectedText = source.substring(with: selectedRange)
        let mappedSelection = mappedSelection(
            relativeSelection,
            throughDedentOf: selectedText
        )
        let movedStart = selectedRange.location
            + next.body.length
            + selected.terminator.length
            + gap.length
        return BulletItemMoveEdit(
            range: NSRange(
                location: selectedRange.location,
                length: NSMaxRange(nextRange) - selectedRange.location
            ),
            segments: compactSegments([
                .source(next.body),
                .source(selected.terminator),
                .source(gap),
                .dedentedSource(selected.body),
                .source(next.terminator),
            ]),
            selection: NSRange(
                location: movedStart + mappedSelection.location,
                length: mappedSelection.length
            )
        )
    }

    private static func mappedSelection(
        _ selection: NSRange,
        throughDedentOf text: String
    ) -> NSRange {
        let start = BulletItemMoveEdit.mappedDedentedOffset(
            selection.location,
            in: text
        )
        let end = BulletItemMoveEdit.mappedDedentedOffset(
            NSMaxRange(selection),
            in: text
        )
        return NSRange(location: start, length: max(0, end - start))
    }

    private static func parentIndex(
        of index: Int,
        in items: [OutlineListItem]
    ) -> Int? {
        guard index > 0 else { return nil }
        let location = items[index].markerRange.location
        return items.indices[..<index].reversed().first { candidate in
            guard items[candidate].depth < items[index].depth,
                  let descendants = items[candidate].descendantRange else {
                return false
            }
            return NSLocationInRange(location, descendants)
        }
    }

    private static func touchedItemIndices(
        selection: NSRange,
        documentLength: Int,
        items: [OutlineListItem]
    ) -> [Int] {
        if selection.length == 0 {
            return items.indices.filter { index in
                let line = items[index].lineRange
                return NSLocationInRange(selection.location, line)
                    || (
                        selection.location == documentLength
                            && selection.location == NSMaxRange(line)
                    )
            }
        }
        return items.indices.filter {
            NSIntersectionRange(items[$0].lineRange, selection).length > 0
        }
    }

    private static func subtreeRange(of item: OutlineListItem) -> NSRange {
        guard let descendants = item.descendantRange else {
            return item.lineRange
        }
        return NSUnionRange(item.lineRange, descendants)
    }

    private static func splitTrailingLineTerminator(
        from range: NSRange,
        in source: NSString
    ) -> (body: NSRange, terminator: NSRange) {
        guard range.length > 0 else {
            return (range, NSRange(location: NSMaxRange(range), length: 0))
        }

        let lastLocation = NSMaxRange(range) - 1
        let last = source.character(at: lastLocation)
        let terminatorLength: Int
        if last == 0x0A,
           lastLocation > range.location,
           source.character(at: lastLocation - 1) == 0x0D {
            terminatorLength = 2
        } else if [0x0A, 0x0D, 0x0085, 0x2028, 0x2029].contains(last) {
            terminatorLength = 1
        } else {
            terminatorLength = 0
        }

        let body = NSRange(
            location: range.location,
            length: range.length - terminatorLength
        )
        return (
            body,
            NSRange(
                location: NSMaxRange(body),
                length: terminatorLength
            )
        )
    }

    private static func compactSegments(
        _ segments: [BulletItemMoveSegment]
    ) -> [BulletItemMoveSegment] {
        segments.filter { segment in
            switch segment {
            case .source(let range), .dedentedSource(let range):
                return range.length > 0
            }
        }
    }
}

import AppKit

extension NativeTextViewCoordinator {
    func loadOutlineState(for documentID: String) {
        guard collapsedOutlineItemsByDocument[documentID] == nil else { return }
        collapsedOutlineItemsByDocument[documentID] =
            configuration.services.outlineState.collapsedItems(for: documentID)
    }

    func prepareOutlineStateForEdit(
        affectedRange: NSRange,
        replacementUTF16Count: Int
    ) {
        guard let documentID = documentId,
              var references = collapsedOutlineItemsByDocument[documentID],
              !references.isEmpty else { return }
        let oldEnd = NSMaxRange(affectedRange)
        let delta = replacementUTF16Count - affectedRange.length
        references = Set(references.map { reference in
            var updated = reference
            if reference.markerLocation >= oldEnd {
                updated.markerLocation = max(0, reference.markerLocation + delta)
            } else if reference.markerLocation >= affectedRange.location {
                updated.markerLocation = max(
                    affectedRange.location,
                    reference.markerLocation + delta
                )
            }
            return updated
        })
        collapsedOutlineItemsByDocument[documentID] = references
        configuration.services.outlineState.replaceCollapsedItems(
            references,
            for: documentID
        )
    }

    func applyOutlineState(to textView: NSTextView) {
        guard !configuration.rawSourceMode,
              let storage = textView.textStorage,
              storage.length > 0 else { return }
        let documentID = documentId ?? "__default__"
        loadOutlineState(for: documentID)
        let items = OutlineListModel.items(in: storage.string)
        let collapsibleItems = items.filter { hasOutlineMarker($0) && $0.hasChildren }
        let persisted = collapsedOutlineItemsByDocument[documentID] ?? []
        let resolved = resolve(persisted, against: collapsibleItems)
        let canonicalReferences = Set(resolved.map(\.reference))
        if canonicalReferences != persisted {
            collapsedOutlineItemsByDocument[documentID] = canonicalReferences
            configuration.services.outlineState.replaceCollapsedItems(
                canonicalReferences,
                for: documentID
            )
        }

        let fullRange = NSRange(location: 0, length: storage.length)
        let expected = expectedOutlineAttributes(
            for: storage.string,
            items: items,
            collapsedItems: resolved
        )
        guard let mismatches = outlineAttributeMismatches(
            in: storage,
            fullRange: fullRange,
            expected: expected
        ) else {
            rebuildOutlineAttributes(
                in: storage,
                fullRange: fullRange,
                items: items,
                collapsedItems: resolved
            )
            return
        }
        if mismatches.isEmpty { return }

        // Collapse/expand genuinely changes what is visible (hidden spans get
        // fonts/colors beyond the outline keys), so it keeps the wholesale
        // rebuild. Metadata-only changes — a Tab/Shift-Tab re-indent updating
        // depth/guide values on a few marker ranges — rewrite exactly the
        // mismatched ranges: the old remove-all/re-add-all pass invalidated
        // every paragraph and TextKit redrew the whole note as a visible flash.
        let visibilityChanged = mismatches.keys.contains {
            $0 == .outlineCollapsed || $0 == .outlineHidden
        }
        if visibilityChanged {
            rebuildOutlineAttributes(
                in: storage,
                fullRange: fullRange,
                items: items,
                collapsedItems: resolved
            )
            return
        }

        storage.beginEditing()
        for (key, ranges) in mismatches {
            for range in ranges {
                storage.removeAttribute(key, range: range)
                expected.enumerateAttribute(key, in: range, options: []) { value, subRange, _ in
                    if let value {
                        storage.addAttribute(key, value: value, range: subRange)
                    }
                }
            }
        }
        storage.endEditing()
    }

    private func rebuildOutlineAttributes(
        in storage: NSTextStorage,
        fullRange: NSRange,
        items: [OutlineListItem],
        collapsedItems resolved: [OutlineListItem]
    ) {
        storage.beginEditing()
        storage.removeAttribute(.outlineDepth, range: fullRange)
        storage.removeAttribute(.outlineHasChildren, range: fullRange)
        storage.removeAttribute(.outlineGuideEnd, range: fullRange)
        storage.removeAttribute(.outlineGuideNextSibling, range: fullRange)
        storage.removeAttribute(.outlineCollapsed, range: fullRange)
        storage.removeAttribute(.outlineHidden, range: fullRange)

        for (index, item) in items.enumerated() {
            storage.addAttribute(
                .outlineDepth,
                value: item.depth,
                range: item.markerRange
            )
            if hasOutlineMarker(item), item.hasChildren {
                storage.addAttribute(
                    .outlineHasChildren,
                    value: true,
                    range: item.markerRange
                )
                if let descendants = item.descendantRange {
                    storage.addAttribute(
                        .outlineGuideEnd,
                        value: NSMaxRange(descendants),
                        range: item.markerRange
                    )
                }
                if let sibling = items[(index + 1)...].first(where: { $0.depth <= item.depth }),
                   sibling.depth == item.depth {
                    storage.addAttribute(
                        .outlineGuideNextSibling,
                        value: sibling.markerRange.location,
                        range: item.markerRange
                    )
                }
            }
        }

        let hiddenFont = NSFont(
            name: fontName,
            size: configuration.markers.hiddenMarkerFontSize
        ) ?? .systemFont(ofSize: configuration.markers.hiddenMarkerFontSize)
        let hiddenParagraph = NSMutableParagraphStyle()
        hiddenParagraph.minimumLineHeight = configuration.markers.hiddenMarkerFontSize
        hiddenParagraph.maximumLineHeight = configuration.markers.hiddenMarkerFontSize
        hiddenParagraph.paragraphSpacing = 0
        hiddenParagraph.paragraphSpacingBefore = 0

        for item in resolved {
            storage.addAttribute(
                .outlineCollapsed,
                value: true,
                range: item.markerRange
            )
            guard let descendants = item.descendantRange else { continue }
            storage.addAttributes(
                [
                    .outlineHidden: true,
                    .font: hiddenFont,
                    .foregroundColor: NSColor.clear,
                    .paragraphStyle: hiddenParagraph,
                ],
                range: descendants
            )
        }
        storage.endEditing()
    }

    /// The outline attributes the document SHOULD carry, computed on a
    /// detached attributed string: the diff against live storage drives both
    /// the match check and the scoped rewrite.
    private func expectedOutlineAttributes(
        for text: String,
        items: [OutlineListItem],
        collapsedItems: [OutlineListItem]
    ) -> NSAttributedString {
        let expected = NSMutableAttributedString(string: text)
        for (index, item) in items.enumerated() {
            expected.addAttribute(.outlineDepth, value: item.depth, range: item.markerRange)
            if hasOutlineMarker(item), item.hasChildren {
                expected.addAttribute(.outlineHasChildren, value: true, range: item.markerRange)
                if let descendants = item.descendantRange {
                    expected.addAttribute(
                        .outlineGuideEnd,
                        value: NSMaxRange(descendants),
                        range: item.markerRange
                    )
                }
                if let sibling = items[(index + 1)...].first(where: { $0.depth <= item.depth }),
                   sibling.depth == item.depth {
                    expected.addAttribute(
                        .outlineGuideNextSibling,
                        value: sibling.markerRange.location,
                        range: item.markerRange
                    )
                }
            }
        }
        for item in collapsedItems {
            expected.addAttribute(.outlineCollapsed, value: true, range: item.markerRange)
            if let descendants = item.descendantRange {
                expected.addAttribute(.outlineHidden, value: true, range: descendants)
            }
        }
        return expected
    }

    /// Ranges where the live storage's outline attributes differ from
    /// `expected`, per key. Empty = everything matches (ordinary edits move
    /// attributed ranges with their text, so this is the common case). `nil` =
    /// the walk could not make progress; the caller should rebuild wholesale.
    private func outlineAttributeMismatches(
        in storage: NSTextStorage,
        fullRange: NSRange,
        expected: NSAttributedString
    ) -> [NSAttributedString.Key: [NSRange]]? {
        let keys: [NSAttributedString.Key] = [
            .outlineDepth,
            .outlineHasChildren,
            .outlineGuideEnd,
            .outlineGuideNextSibling,
            .outlineCollapsed,
            .outlineHidden,
        ]
        var mismatches: [NSAttributedString.Key: [NSRange]] = [:]
        for key in keys {
            var location = 0
            while location < fullRange.length {
                var currentRange = NSRange()
                let current = storage.attribute(
                    key,
                    at: location,
                    longestEffectiveRange: &currentRange,
                    in: fullRange
                )
                var expectedRange = NSRange()
                let wanted = expected.attribute(
                    key,
                    at: location,
                    longestEffectiveRange: &expectedRange,
                    in: fullRange
                )
                let nextLocation = min(NSMaxRange(currentRange), NSMaxRange(expectedRange))
                guard nextLocation > location else { return nil }
                if !outlineValuesEqual(current, wanted) {
                    let mismatch = NSRange(
                        location: location,
                        length: nextLocation - location
                    )
                    var ranges = mismatches[key] ?? []
                    if let last = ranges.last, NSMaxRange(last) == mismatch.location {
                        ranges[ranges.count - 1] = NSUnionRange(last, mismatch)
                    } else {
                        ranges.append(mismatch)
                    }
                    mismatches[key] = ranges
                }
                location = nextLocation
            }
        }
        return mismatches
    }

    private func outlineValuesEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs as NSObject, rhs as NSObject):
            return lhs.isEqual(rhs)
        default:
            return false
        }
    }

    func redirectSelectionFromCollapsedOutline(in textView: NSTextView) -> Bool {
        guard !isAdjustingOutlineSelection,
              let storage = textView.textStorage,
              storage.length > 0 else { return false }
        let selection = textView.selectedRange()
        guard selection.length == 0, selection.location < storage.length else { return false }
        var hiddenRange = NSRange()
        guard storage.attribute(
            .outlineHidden,
            at: selection.location,
            longestEffectiveRange: &hiddenRange,
            in: NSRange(location: 0, length: storage.length)
        ) != nil else { return false }
        let movingForward = selection.location >= (previousSelectedRange?.location ?? 0)
        let target = movingForward
            ? min(NSMaxRange(hiddenRange), storage.length)
            : max(0, hiddenRange.location - 1)
        isAdjustingOutlineSelection = true
        textView.setSelectedRange(NSRange(location: target, length: 0))
        isAdjustingOutlineSelection = false
        return true
    }

    @discardableResult
    func toggleOutlineItem(at markerLocation: Int, in textView: NativeTextView) -> Bool {
        let items = OutlineListModel.items(in: textView.string)
        guard let item = items.first(where: {
            $0.markerRange.location == markerLocation
                && hasOutlineMarker($0)
                && $0.hasChildren
        }) else { return false }
        let documentID = documentId ?? "__default__"
        loadOutlineState(for: documentID)
        let resolved = resolve(
            collapsedOutlineItemsByDocument[documentID] ?? [],
            against: items.filter { hasOutlineMarker($0) && $0.hasChildren }
        )
        var references = Set(resolved.map(\.reference))
        let isCollapsing: Bool
        if references.contains(item.reference) {
            references.remove(item.reference)
            isCollapsing = false
        } else {
            references.insert(item.reference)
            isCollapsing = true
        }
        collapsedOutlineItemsByDocument[documentID] = references
        configuration.services.outlineState.replaceCollapsedItems(
            references,
            for: documentID
        )

        if isCollapsing,
           let descendants = item.descendantRange,
           NSIntersectionRange(textView.selectedRange(), descendants).length > 0 {
            textView.setSelectedRange(
                NSRange(location: NSMaxRange(item.markerRange), length: 0)
            )
        }
        if !isCollapsing,
           let descendants = item.descendantRange,
           let storage = textView.textStorage {
            // Incremental restyling deliberately preserves every attribute on
            // hidden descendants so ordinary edits do not flash a collapsed
            // subtree. Remove the presentation marker before restyling an
            // expansion; otherwise the tiny transparent font/color runs are
            // copied forward even after the collapsed state is gone.
            storage.beginEditing()
            storage.removeAttribute(.outlineHidden, range: descendants)
            storage.removeAttribute(.outlineCollapsed, range: item.markerRange)
            storage.endEditing()
        }
        let affectedRange = item.descendantRange.map {
            NSUnionRange(item.lineRange, $0)
        } ?? item.lineRange
        restyleParagraphs([affectedRange], in: textView)
        if let scrollView = textView.enclosingScrollView {
            textView.recalcOverscroll(for: scrollView, debugTag: "outlineToggle")
            (scrollView as? ClampedScrollView)?.clampToInsets()
        }
        textView.window?.makeFirstResponder(textView)
        textView.setNeedsDisplay(textView.visibleRect)
        return true
    }

    private func hasOutlineMarker(_ item: OutlineListItem) -> Bool {
        item.isBullet || (item.isTask && configuration.taskCheckbox.showsListBullet)
    }

    private func resolve(
        _ references: Set<OutlineItemReference>,
        against items: [OutlineListItem]
    ) -> [OutlineListItem] {
        var remaining = Array(items.indices)
        var result: [OutlineListItem] = []
        for reference in references.sorted(by: { $0.markerLocation < $1.markerLocation }) {
            let exact = remaining.first(where: { index in
                items[index].reference == reference
            })
            let matchingFingerprint = remaining
                .filter { items[$0].reference.lineFingerprint == reference.lineFingerprint }
                .min { first, second in
                    abs(items[first].markerRange.location - reference.markerLocation)
                        < abs(items[second].markerRange.location - reference.markerLocation)
                }
            let matchingLocation = remaining.first(where: {
                items[$0].markerRange.location == reference.markerLocation
            })
            guard let index = exact ?? matchingFingerprint ?? matchingLocation else { continue }
            result.append(items[index])
            remaining.removeAll { $0 == index }
        }
        return result
    }
}

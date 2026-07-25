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
        if outlineAttributesMatch(
            in: storage,
            fullRange: fullRange,
            items: items,
            collapsedItems: resolved
        ) {
            return
        }
        storage.beginEditing()
        storage.removeAttribute(.outlineDepth, range: fullRange)
        storage.removeAttribute(.outlineHasChildren, range: fullRange)
        storage.removeAttribute(.outlineCollapsed, range: fullRange)
        storage.removeAttribute(.outlineHidden, range: fullRange)

        for item in items {
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

    /// Ordinary edits move existing attributed ranges with their text. Avoid
    /// clearing and rebuilding outline metadata across the whole document when
    /// those ranges already describe the newly parsed outline exactly.
    private func outlineAttributesMatch(
        in storage: NSTextStorage,
        fullRange: NSRange,
        items: [OutlineListItem],
        collapsedItems: [OutlineListItem]
    ) -> Bool {
        let expected = NSMutableAttributedString(string: storage.string)
        for item in items {
            expected.addAttribute(.outlineDepth, value: item.depth, range: item.markerRange)
            if hasOutlineMarker(item), item.hasChildren {
                expected.addAttribute(.outlineHasChildren, value: true, range: item.markerRange)
            }
        }
        for item in collapsedItems {
            expected.addAttribute(.outlineCollapsed, value: true, range: item.markerRange)
            if let descendants = item.descendantRange {
                expected.addAttribute(.outlineHidden, value: true, range: descendants)
            }
        }

        let keys: [NSAttributedString.Key] = [
            .outlineDepth,
            .outlineHasChildren,
            .outlineCollapsed,
            .outlineHidden,
        ]
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
                if !outlineValuesEqual(current, wanted) {
                    return false
                }
                let nextLocation = min(NSMaxRange(currentRange), NSMaxRange(expectedRange))
                guard nextLocation > location else { return false }
                location = nextLocation
            }
        }
        return true
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

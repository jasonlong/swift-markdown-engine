import AppKit

extension NativeTextViewCoordinator {
    /// Handles the two natural wiki-link creation gestures before AppKit applies
    /// its ordinary bracket insertion:
    ///
    /// * typing the second `[` inserts the closing `]]` and leaves the caret in
    ///   the editable content;
    /// * typing `[` over a text selection wraps it in `[[…]]` and leaves the
    ///   caret at the end of that content so the same completion UI opens.
    ///
    /// The caller has already rejected raw-source, undo, and protected-prefix
    /// edits. Returning `true` means this method performed the replacement.
    func handleWikiLinkCreationInput(
        in textView: NSTextView,
        affectedRange: NSRange,
        replacementString: String?,
        text: NSString,
        codeTokens: [MarkdownToken]
    ) -> Bool {
        guard replacementString == "[",
              affectedRange.location != NSNotFound,
              NSMaxRange(affectedRange) <= text.length,
              !MarkdownDetection.isInsideCodeBlock(range: affectedRange, codeTokens: codeTokens)
        else {
            return false
        }

        let selectedText = text.substring(with: affectedRange)
        let replacement: String
        let caretLocation: Int
        if affectedRange.length > 0 {
            replacement = "[[\(selectedText)]]"
            caretLocation = affectedRange.location + 2 + (selectedText as NSString).length
        } else if affectedRange.location > 0,
                  text.character(at: affectedRange.location - 1) == 0x5B {
            replacement = "[]]"
            caretLocation = affectedRange.location + 1
        } else {
            return false
        }

        textView.breakUndoCoalescing()
        isProgrammaticEdit = true
        defer { isProgrammaticEdit = false }
        guard textView.shouldChangeText(in: affectedRange, replacementString: replacement) else {
            return false
        }
        textView.textStorage?.replaceCharacters(in: affectedRange, with: replacement)
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: caretLocation, length: 0))
        textView.undoManager?.setActionName("Insert Link")
        textView.breakUndoCoalescing()
        return true
    }

    /// Completed wiki links behave like atomic mentions. A draft `[[]]` has
    /// neither attribute, so it remains editable while autocomplete is active.
    func isAtomicWikiLink(_ token: MarkdownToken, in textView: NSTextView) -> Bool {
        guard token.kind == .wikiLink,
            token.contentRange.length > 0,
            let storage = textView.textStorage,
            NSMaxRange(token.contentRange) <= storage.length
        else {
            return false
        }
        let location = token.contentRange.location
        return storage.attribute(.link, at: location, effectiveRange: nil) != nil
            || storage.attribute(.mutedLink, at: location, effectiveRange: nil) != nil
            || storage.attribute(.wikiLinkID, at: location, effectiveRange: nil) != nil
    }

    /// Keep completed links rendered even while selected. Draft links still
    /// become active so their markers and autocomplete editing remain visible.
    func removeAtomicWikiLinks(
        from activeIndices: inout Set<Int>,
        parsed: ParsedDocument,
        in textView: NSTextView,
        treatingEveryWikiLinkAsAtomic: Bool = false
    ) {
        for index in Array(activeIndices) {
            guard parsed.tokens.indices.contains(index) else { continue }
            let token = parsed.tokens[index]
            guard token.kind == .wikiLink else { continue }
            if treatingEveryWikiLinkAsAtomic || isAtomicWikiLink(token, in: textView) {
                activeIndices.remove(index)
            }
        }
    }

    /// Expands a caret or partial selection touching a completed wiki link to
    /// the token's full display range (`[[Name]]`). The two outer boundaries
    /// remain valid caret positions so arrow navigation can enter, select, and
    /// then leave the mention in one step each.
    func atomicWikiLinkSelection(
        proposedRange: NSRange,
        in textView: NSTextView,
        parsed: ParsedDocument? = nil
    ) -> NSRange {
        guard !configuration.rawSourceMode,
            textView.isEditable,
            proposedRange.location != NSNotFound
        else {
            return proposedRange
        }

        let documentLength = (textView.string as NSString).length
        guard proposedRange.location <= documentLength,
            NSMaxRange(proposedRange) <= documentLength
        else {
            return proposedRange
        }

        let parsed = parsed ?? parsedDocument(for: textView.string)
        if proposedRange.length == 0 {
            for token in parsed.wikiLinkTokens
            where isAtomicWikiLink(token, in: textView) {
                let start = token.range.location
                let end = NSMaxRange(token.range)
                if proposedRange.location > start && proposedRange.location < end {
                    return token.range
                }
            }
            return proposedRange
        }

        var lowerBound = proposedRange.location
        var upperBound = NSMaxRange(proposedRange)
        for token in parsed.wikiLinkTokens
        where isAtomicWikiLink(token, in: textView) {
            guard
                NSIntersectionRange(
                    NSRange(location: lowerBound, length: upperBound - lowerBound),
                    token.range
                ).length > 0
            else {
                continue
            }
            lowerBound = min(lowerBound, token.range.location)
            upperBound = max(upperBound, NSMaxRange(token.range))
        }
        return NSRange(location: lowerBound, length: upperBound - lowerBound)
    }

    /// Rejects edits that would mutate only part of an atomic link. Deleting,
    /// replacing, or selecting across the entire token remains valid.
    func partiallyEditsAtomicWikiLink(
        affectedRange: NSRange,
        parsed: ParsedDocument,
        in textView: NSTextView
    ) -> Bool {
        for token in parsed.wikiLinkTokens
        where isAtomicWikiLink(token, in: textView) {
            if affectedRange.length == 0 {
                let location = affectedRange.location
                if location > token.range.location && location < NSMaxRange(token.range) {
                    return true
                }
                continue
            }

            guard NSIntersectionRange(affectedRange, token.range).length > 0 else {
                continue
            }
            let containsWholeToken =
                affectedRange.location <= token.range.location
                && NSMaxRange(affectedRange) >= NSMaxRange(token.range)
            if !containsWholeToken {
                return true
            }
        }
        return false
    }

    public func textView(
        _ textView: NSTextView,
        willChangeSelectionFromCharacterRange _: NSRange,
        toCharacterRange newSelectedCharRange: NSRange
    ) -> NSRange {
        atomicWikiLinkSelection(
            proposedRange: newSelectedCharRange,
            in: textView
        )
    }
}

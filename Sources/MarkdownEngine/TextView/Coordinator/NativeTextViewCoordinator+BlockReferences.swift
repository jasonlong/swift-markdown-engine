import AppKit

extension NativeTextViewCoordinator {
    func redirectSelectionFromProtectedBlockID(in textView: NSTextView) -> Bool {
        let selection = textView.selectedRange()
        guard selection.length == 0,
              let idRange = MarkdownBlockReferenceSyntax.protectedIDRange(
                near: selection.location,
                in: textView.string
              ),
              selection.location > idRange.location,
              selection.location < NSMaxRange(idRange)
        else { return false }

        let event = NSApp.currentEvent
        let isPlainRightArrow = event?.type == .keyDown
            && event?.keyCode == 124
            && event?.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty == true
        let movingForward = isPlainRightArrow
            && previousSelectedRange?.location == idRange.location
        let target = movingForward ? NSMaxRange(idRange) : idRange.location
        textView.setSelectedRange(NSRange(location: target, length: 0))
        return true
    }

    func redirectInsertionBeforeProtectedBlockID(
        in textView: NSTextView,
        affectedRange: NSRange,
        replacement: String?,
        source: String
    ) -> Bool {
        guard let insertion = MarkdownBlockReferenceSyntax.visibleInsertionRange(
            for: affectedRange,
            replacement: replacement,
            in: source
        ), let replacement else {
            return false
        }

        let originalLength = (textView.string as NSString).length
        MarkdownLists.performEdit(textView, replace: insertion, with: replacement)
        let replacementLength = replacement.utf16.count
        if (textView.string as NSString).length == originalLength + replacementLength {
            textView.setSelectedRange(NSRange(
                location: insertion.location + replacementLength,
                length: 0
            ))
        }
        return true
    }

    func revealSourceBlockIfRequested(_ blockID: String?, in textView: NSTextView) {
        guard let blockID,
              lastRevealedSourceBlock?.documentID != documentId || lastRevealedSourceBlock?.id != blockID,
              let range = MarkdownBlockReferenceSyntax.lineRange(forBlockID: blockID, in: textView.string)
        else { return }
        lastRevealedSourceBlock = (documentId, blockID)
        textView.scrollRangeToVisible(range)
        textView.textStorage?.addAttribute(
            .backgroundColor,
            value: NSColor.controlAccentColor.withAlphaComponent(0.18),
            range: range
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak textView] in
            textView?.textStorage?.removeAttribute(.backgroundColor, range: range)
        }
    }

    func revealBlockReferenceIfRequested(_ address: String?, in textView: NSTextView) {
        guard let address,
              lastRevealedBlockReference?.documentID != documentId || lastRevealedBlockReference?.address != address,
              let separator = address.lastIndex(of: "#")
        else { return }
        let target = String(address[..<separator])
        let suffix = address[address.index(after: separator)...]
        guard suffix.first == "^" else { return }
        let blockID = String(suffix.dropFirst())
        guard let range = MarkdownBlockReferenceSyntax.lineRange(
            forReferenceTo: target,
            blockID: blockID,
            in: textView.string
        ) else { return }
        lastRevealedBlockReference = (documentId, address)
        reveal(range, in: textView)
    }

    private func reveal(_ range: NSRange, in textView: NSTextView) {
        textView.scrollRangeToVisible(range)
        textView.textStorage?.addAttribute(
            .backgroundColor,
            value: NSColor.controlAccentColor.withAlphaComponent(0.18),
            range: range
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak textView] in
            textView?.textStorage?.removeAttribute(.backgroundColor, range: range)
        }
    }
}

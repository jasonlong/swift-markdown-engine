import AppKit

extension NativeTextViewCoordinator {
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

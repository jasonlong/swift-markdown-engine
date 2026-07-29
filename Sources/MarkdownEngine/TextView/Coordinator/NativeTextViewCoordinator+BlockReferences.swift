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
}

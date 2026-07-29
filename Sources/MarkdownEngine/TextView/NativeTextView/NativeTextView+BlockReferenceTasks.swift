import AppKit

extension NativeTextView {
    /// Handles only the compact checkbox drawn in a transclusion card. The
    /// portable reference token remains immutable; mutation belongs to the
    /// host, which owns the canonical source document and its save protocol.
    func toggleBlockReferenceTaskIfHit(event: NSEvent) -> Bool {
        guard let provider = blockReferencePresentationProvider,
              let onToggle = onBlockReferenceTaskToggle,
              let bridge = layoutBridge,
              let textContainer
        else { return false }

        let viewPoint = convert(event.locationInWindow, from: nil)
        let containerPoint = CGPoint(
            x: viewPoint.x - textContainerOrigin.x,
            y: viewPoint.y - textContainerOrigin.y
        )
        let characterIndex = characterIndexForInsertion(at: viewPoint)
        guard let reference = MarkdownBlockReferenceSyntax.tokens(in: markdownSourceWithBlockReferenceMarkers()).first(where: {
            NSLocationInRange(characterIndex, $0.range)
        }), let presentation = provider(reference), presentation.isTaskComplete != nil
        else { return false }

        let anchor = NSRange(location: reference.range.location, length: 1)
        let anchorRect = bridge.boundingRect(forCharacterRange: anchor, in: textContainer)
        let checkbox = CGRect(
            x: anchorRect.minX + 15,
            y: anchorRect.midY - 8,
            width: 16,
            height: 16
        )
        guard checkbox.contains(containerPoint) else { return false }
        onToggle(reference)
        return true
    }

    func openBlockReferenceIfHit(event: NSEvent) -> Bool {
        guard let provider = blockReferencePresentationProvider,
              let onOpen = onBlockReferenceOpen
        else { return false }
        let point = convert(event.locationInWindow, from: nil)
        let characterIndex = characterIndexForInsertion(at: point)
        guard let reference = MarkdownBlockReferenceSyntax.tokens(in: markdownSourceWithBlockReferenceMarkers()).first(where: {
            NSLocationInRange(characterIndex, $0.range)
        }), provider(reference) != nil
        else { return false }
        onOpen(reference)
        return true
    }
}

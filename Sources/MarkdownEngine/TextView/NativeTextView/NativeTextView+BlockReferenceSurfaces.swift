import AppKit

private extension NSAttributedString.Key {
    static let markdownBlockReferenceSurface = NSAttributedString.Key("MarkdownEngine.blockReferenceSurface")
    static let markdownBlockReferenceOriginalParagraph = NSAttributedString.Key("MarkdownEngine.blockReference.originalParagraph")
}

extension NativeTextView {
    /// Reconciles host-owned reference views after TextKit has styled the token.
    ///
    /// The token's string never changes. A tiny, transparent token reserves one
    /// deterministic line while the native sibling view supplies the visible UI.
    func updateBlockReferenceSurfaces() {
        guard let storage = textStorage,
              let presentationProvider = blockReferencePresentationProvider,
              let surfaceProvider = blockReferenceSurfaceProvider,
              let layoutBridge,
              let textContainer = textContainer,
              let host = superview
        else {
            removeBlockReferenceSurfaces()
            return
        }

        removeBlockReferenceSurfaces()
        let source = string
        let sourceNSString = source as NSString
        let fullRange = NSRange(location: 0, length: storage.length)
        restoreBlockReferenceParagraphs(in: storage, fullRange: fullRange)

        let availableWidth = max(1, bounds.width - textContainerInset.width * 2)
        var pending: [(token: MarkdownBlockReferenceToken, surface: MarkdownBlockReferenceSurface)] = []
        storage.beginEditing()
        for token in MarkdownBlockReferenceSyntax.tokens(in: source) where token.kind == .transclusion {
            guard let presentation = presentationProvider(token),
                  let surface = surfaceProvider(token, presentation, availableWidth),
                  token.range.length > 0
            else { continue }

            let paragraphRange = sourceNSString.paragraphRange(for: token.range)
            let existingParagraph = (storage.attribute(.paragraphStyle, at: token.range.location, effectiveRange: nil)
                as? NSParagraphStyle) ?? NSParagraphStyle.default
            let paragraph = existingParagraph.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            paragraph.minimumLineHeight = max(paragraph.minimumLineHeight, surface.height)
            paragraph.maximumLineHeight = max(paragraph.maximumLineHeight, surface.height)
            paragraph.lineBreakMode = .byClipping
            storage.addAttribute(.markdownBlockReferenceOriginalParagraph, value: existingParagraph, range: paragraphRange)
            storage.addAttribute(.paragraphStyle, value: paragraph, range: paragraphRange)
            storage.addAttributes([
                .markdownBlockReferenceSurface: true,
                .foregroundColor: NSColor.clear,
                .font: NSFont.systemFont(ofSize: 0.1),
                .kern: -0.1,
            ], range: token.range)
            pending.append((token, surface))
        }
        storage.endEditing()

        guard !pending.isEmpty else { return }
        ensureVisibleLayout()

        for entry in pending {
            let tokenRect = layoutBridge.boundingRect(forCharacterRange: entry.token.range, in: textContainer)
            guard !tokenRect.isEmpty else { continue }
            let frame = NSRect(
                x: frame.minX + textContainerOrigin.x + tokenRect.minX,
                y: frame.minY + textContainerOrigin.y + tokenRect.minY,
                width: availableWidth,
                height: entry.surface.height
            )
            entry.surface.view.frame = frame.integral
            host.addSubview(entry.surface.view, positioned: .above, relativeTo: self)
            blockReferenceSurfaceViews.append(entry.surface.view)
        }
    }

    func removeBlockReferenceSurfaces() {
        for view in blockReferenceSurfaceViews { view.removeFromSuperview() }
        blockReferenceSurfaceViews.removeAll()
    }

    private func restoreBlockReferenceParagraphs(in storage: NSTextStorage, fullRange: NSRange) {
        var paragraphRanges: [NSRange] = []
        storage.enumerateAttribute(.markdownBlockReferenceOriginalParagraph, in: fullRange) { value, range, _ in
            guard value is NSParagraphStyle else { return }
            let paragraphRange = (string as NSString).paragraphRange(for: range)
            if !paragraphRanges.contains(where: { NSEqualRanges($0, paragraphRange) }) {
                paragraphRanges.append(paragraphRange)
            }
        }
        for paragraphRange in paragraphRanges {
            guard let original = storage.attribute(
                .markdownBlockReferenceOriginalParagraph,
                at: paragraphRange.location,
                effectiveRange: nil
            ) as? NSParagraphStyle else { continue }
            storage.addAttribute(.paragraphStyle, value: original, range: paragraphRange)
            storage.removeAttribute(.markdownBlockReferenceOriginalParagraph, range: paragraphRange)
            storage.removeAttribute(.markdownBlockReferenceSurface, range: paragraphRange)
        }
    }
}

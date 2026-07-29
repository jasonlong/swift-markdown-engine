import AppKit

private extension NSAttributedString.Key {
    static let markdownBlockReferenceSurface = NSAttributedString.Key("MarkdownEngine.blockReferenceSurface")
}

extension NativeTextViewCoordinator {
    func applyBlockReferencePresentations(to textView: NSTextView) {
        guard let nativeTextView = textView as? NativeTextView,
              let provider = nativeTextView.blockReferencePresentationProvider,
              let storage = textView.textStorage
        else { return }

        let source = textView.string
        let references = MarkdownBlockReferenceSyntax.tokens(in: source)
        let availableWidth = max(180, textView.bounds.width - textView.textContainerInset.width * 2)
        storage.beginEditing()
        defer { storage.endEditing() }
        let fullRange = NSRange(location: 0, length: storage.length)
        var priorRanges: [NSRange] = []
        storage.enumerateAttribute(
            .markdownBlockReferenceSurface,
            in: fullRange
        ) { value, range, _ in
            if value != nil { priorRanges.append(range) }
        }
        for range in priorRanges {
            storage.removeAttribute(.latexImage, range: range)
            storage.removeAttribute(.latexBounds, range: range)
            storage.removeAttribute(.latexIsBlock, range: range)
            storage.removeAttribute(.attachment, range: range)
            storage.removeAttribute(.markdownBlockReferenceSurface, range: range)
        }
        for reference in references {
            guard let presentation = provider(reference), reference.range.length > 0 else { continue }
            let image = BlockReferenceAttachmentRenderer.image(
                presentation: presentation,
                width: availableWidth
            )
            let referenceText = (source as NSString).substring(with: reference.range)
            let leadingWhitespace = referenceText.utf16.prefix { $0 == 0x20 || $0 == 0x09 }.count
            let anchor = NSRange(location: reference.range.location + leadingWhitespace, length: 1)
            let imageSize = image.size
            let paragraphRange = (source as NSString).paragraphRange(for: reference.range)
            let paragraph = (storage.attribute(.paragraphStyle, at: anchor.location, effectiveRange: nil)
                as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            paragraph.minimumLineHeight = max(paragraph.minimumLineHeight, imageSize.height)
            paragraph.maximumLineHeight = max(paragraph.maximumLineHeight, imageSize.height)
            paragraph.lineBreakMode = .byClipping
            storage.addAttribute(.paragraphStyle, value: paragraph, range: paragraphRange)
            let markerFont = NSFont.systemFont(ofSize: 0.1)
            let anchorText = (source as NSString).substring(with: anchor)
            storage.addAttributes([
                .latexImage: image,
                .latexBounds: NSValue(rect: NSRect(origin: .zero, size: imageSize)),
                .latexIsBlock: true,
                .markdownBlockReferenceSurface: true,
                .foregroundColor: NSColor.clear,
                .font: markerFont,
                .kern: imageSize.width - HeadingHelpers.textWidth(anchorText, font: markerFont),
            ], range: anchor)
            let tailStart = anchor.location + 1
            let tailLength = NSMaxRange(reference.range) - tailStart
            if tailLength > 0 {
                let tail = NSRange(location: tailStart, length: tailLength)
                let tailText = (source as NSString).substring(with: tail)
                storage.addAttributes([
                    .markdownBlockReferenceSurface: true,
                    .foregroundColor: NSColor.clear,
                    .font: markerFont,
                    .kern: -HeadingHelpers.textWidth(tailText, font: markerFont),
                ], range: tail)
            }
        }
    }
}

private enum BlockReferenceAttachmentRenderer {
    static func image(
        presentation: MarkdownBlockReferencePresentation,
        width: CGFloat
    ) -> NSImage {
        let cell = BlockReferenceAttachmentCell(presentation: presentation, width: width)
        let size = cell.cellSize()
        let image = NSImage(size: size)
        image.lockFocus()
        cell.draw(withFrame: NSRect(origin: .zero, size: size), in: nil)
        image.unlockFocus()
        return image
    }
}

private final class BlockReferenceAttachmentCell: NSTextAttachmentCell {
    private let presentation: MarkdownBlockReferencePresentation
    private let width: CGFloat

    init(presentation: MarkdownBlockReferencePresentation, width: CGFloat) {
        self.presentation = presentation
        self.width = width
        super.init()
    }

    required init(coder: NSCoder) {
        fatalError("BlockReferenceAttachmentCell is created programmatically")
    }

    override func cellSize() -> NSSize {
        NSSize(width: width, height: estimatedHeight)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let rect = cellFrame.insetBy(dx: 1, dy: 2)
        let accent = color(for: presentation.state)
        NSColor.controlBackgroundColor.withAlphaComponent(0.82).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        accent.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: rect.minX, y: rect.minY, width: 2, height: rect.height),
            xRadius: 1,
            yRadius: 1
        ).fill()

        let body = displayMarkdown
        let taskOffset: CGFloat = presentation.isTaskComplete == nil ? 0 : 24
        let textRect = NSRect(
            x: rect.minX + 16 + taskOffset,
            y: rect.minY + 8,
            width: rect.width - 24 - taskOffset,
            height: rect.height - 16
        )
        if let complete = presentation.isTaskComplete {
            let checkbox = NSRect(x: rect.minX + 15, y: rect.midY - 8, width: 16, height: 16)
            accent.withAlphaComponent(0.15).setFill()
            NSBezierPath(roundedRect: checkbox, xRadius: 4, yRadius: 4).fill()
            accent.setStroke()
            let outline = NSBezierPath(roundedRect: checkbox.insetBy(dx: 0.5, dy: 0.5), xRadius: 3.5, yRadius: 3.5)
            outline.lineWidth = 1.5
            outline.stroke()
            if complete {
                let checkmark = NSBezierPath()
                checkmark.move(to: NSPoint(x: checkbox.minX + 3.5, y: checkbox.midY))
                checkmark.line(to: NSPoint(x: checkbox.midX - 0.5, y: checkbox.minY + 4))
                checkmark.line(to: NSPoint(x: checkbox.maxX - 3, y: checkbox.maxY - 4))
                checkmark.lineWidth = 1.8
                checkmark.lineCapStyle = .round
                checkmark.lineJoinStyle = .round
                checkmark.stroke()
            }
        }
        let sourceAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.labelColor,
        ]
        let heading = NSAttributedString(string: "↗  \(presentation.sourceLabel)\n", attributes: sourceAttributes)
        let content = NSMutableAttributedString(attributedString: heading)
        content.append(NSAttributedString(string: body, attributes: bodyAttributes))
        content.draw(in: textRect)
    }

    private var displayMarkdown: String {
        let stripped = presentation.markdown
            .replacingOccurrences(of: "- [ ] ", with: "")
            .replacingOccurrences(of: "- [x] ", with: "")
        return stripped.isEmpty ? statusLabel : stripped
    }

    private var statusLabel: String {
        switch presentation.state {
        case .resolved: "Referenced block"
        case .broken: "Referenced block is unavailable"
        case .ambiguous: "Referenced note is ambiguous"
        case .duplicate: "Referenced block ID is duplicated"
        case .cyclic: "Cyclic block reference"
        }
    }

    private var estimatedHeight: CGFloat {
        let lines = max(1, displayMarkdown.split(separator: "\n", omittingEmptySubsequences: false).count)
        return max(48, CGFloat(lines) * 20 + 28)
    }

    private func color(for state: MarkdownBlockReferencePresentation.State) -> NSColor {
        switch state {
        case .resolved: .controlAccentColor
        case .broken, .ambiguous, .duplicate, .cyclic: .systemOrange
        }
    }
}

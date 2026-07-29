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
        guard !references.isEmpty else { return }
        let availableWidth = max(180, textView.bounds.width - textView.textContainerInset.width * 2)
        storage.beginEditing()
        defer { storage.endEditing() }
        for reference in references {
            guard let presentation = provider(reference), reference.range.length > 0 else { continue }
            let attachment = NSTextAttachment()
            attachment.attachmentCell = BlockReferenceAttachmentCell(
                presentation: presentation,
                width: availableWidth
            )
            let anchor = NSRange(location: reference.range.location, length: 1)
            storage.addAttribute(.attachment, value: attachment, range: anchor)
            storage.addAttribute(.markdownBlockReferenceSurface, value: true, range: reference.range)
            let hiddenTail = NSRange(
                location: reference.range.location + 1,
                length: reference.range.length - 1
            )
            if hiddenTail.length > 0 {
                storage.addAttributes([
                    .font: NSFont.systemFont(ofSize: 0.1),
                    .foregroundColor: NSColor.clear,
                    .kern: -0.1,
                ], range: hiddenTail)
            }
        }
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

import AppKit

extension NativeTextView {
    /// The compact left-edge handle zone for a list row. It preserves normal
    /// selection everywhere else in the editor while providing a direct
    /// pointer affordance for source-owned reference drags.
    func beginBlockReferenceDragIfHit(event: NSEvent) -> Bool {
        guard let onBlockReferenceDrag, event.clickCount == 1 else { return false }
        let point = convert(event.locationInWindow, from: nil)
        let containerPoint = CGPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
        guard containerPoint.x <= 14,
              let selection = blockReferenceDragSelection(at: point)
        else { return false }

        Task { @MainActor [weak self] in
            guard let self, let payload = await onBlockReferenceDrag(selection) else { return }
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setData(payload.privateData, forType: NSPasteboard.PasteboardType(payload.privateType))
            pasteboardItem.setString(payload.plainText, forType: .string)
            let item = NSDraggingItem(pasteboardWriter: pasteboardItem)
            let image = NSImage(systemSymbolName: "arrowshape.turn.up.right.circle.fill", accessibilityDescription: "Block reference")
                ?? NSImage(size: NSSize(width: 28, height: 28))
            item.setDraggingFrame(NSRect(origin: point, size: image.size), contents: image)
            _ = self.beginDraggingSession(with: [item], event: event, source: self)
        }
        return true
    }

    private func blockReferenceDragSelection(at point: CGPoint) -> MarkdownBlockReferenceDragSelection? {
        let index = characterIndexForInsertion(at: point)
        let source = string as NSString
        guard index >= 0, index < source.length else { return nil }
        let line = source.lineRange(for: NSRange(location: index, length: 0))
        let text = source.substring(with: line)
        guard text.range(of: #"^[ \t]*(?:[-*+] |\d+[.)] )"#, options: .regularExpression) != nil else {
            return nil
        }
        return MarkdownBlockReferenceDragSelection(location: line.location, length: line.length)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard isEditable,
              let onPasteImage,
              onPasteImage(sender.draggingPasteboard) != nil
        else { return super.draggingEntered(sender) }
        return .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard isEditable else { return super.performDragOperation(sender) }
        let pasteboard = sender.draggingPasteboard
        let point = convert(sender.draggingLocation, from: nil)
        let insertion = characterIndexForInsertion(at: point)
        setSelectedRange(NSRange(location: insertion, length: 0))

        if NSEvent.modifierFlags.contains(.option), let plain = pasteboard.string(forType: .string) {
            insertPreservingBlockquote(plain)
            undoManager?.setActionName("Copy Block")
            return true
        }
        if let reference = onPasteImage?(pasteboard), !reference.isEmpty {
            insertBlockEmbed(reference)
            undoManager?.setActionName("Insert Block Reference")
            return true
        }
        return super.performDragOperation(sender)
    }
}

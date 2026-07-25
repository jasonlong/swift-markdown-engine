import AppKit

extension NativeTextView {
    func moveBulletItem(_ direction: BulletItemMoveDirection) -> Bool {
        guard isEditable,
              let textStorage,
              let coordinator = delegate as? NativeTextViewCoordinator,
              let edit = BulletItemMovement.edit(
                in: textStorage.string,
                selection: selectedRange(),
                direction: direction
              ) else { return false }

        let replacement = edit.attributedReplacement(from: textStorage)
        breakUndoCoalescing()
        coordinator.isProgrammaticEdit = true
        defer { coordinator.isProgrammaticEdit = false }
        guard shouldChangeText(
            in: edit.range,
            replacementString: replacement.string
        ) else { return false }

        textStorage.replaceCharacters(in: edit.range, with: replacement)
        didChangeText()
        setSelectedRange(edit.selection)
        undoManager?.setActionName(
            direction == .up ? "Move bullet up" : "Move bullet down"
        )
        breakUndoCoalescing()
        return true
    }
}

import AppKit

extension NativeTextView {
    @objc func cycleBulletTaskState(_ sender: Any?) {
        _ = cycleBulletTaskState()
    }

    func cycleBulletTaskState() -> Bool {
        guard isEditable,
              let textStorage,
              let coordinator = delegate as? NativeTextViewCoordinator,
              let edit = BulletTaskCycle.edit(
                in: textStorage.string,
                at: selectedRange().location
              ) else { return false }

        let originalSelection = selectedRange()
        breakUndoCoalescing()
        coordinator.isProgrammaticEdit = true
        defer { coordinator.isProgrammaticEdit = false }
        guard shouldChangeText(
            in: edit.range,
            replacementString: edit.replacement
        ) else { return false }

        textStorage.replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()
        setSelectedRange(adjustedSelection(originalSelection, for: edit))
        undoManager?.setActionName("Cycle task state")
        breakUndoCoalescing()
        return true
    }

    private func adjustedSelection(
        _ selection: NSRange,
        for edit: BulletTaskCycleEdit
    ) -> NSRange {
        let replacementLength = (edit.replacement as NSString).length
        let lengthDelta = replacementLength - edit.range.length

        func adjustedBoundary(_ location: Int) -> Int {
            if edit.range.length == 0, location >= edit.range.location {
                return location + lengthDelta
            }
            if location <= edit.range.location { return location }
            if location >= NSMaxRange(edit.range) { return location + lengthDelta }
            return edit.range.location + replacementLength
        }

        let start = adjustedBoundary(selection.location)
        let end = adjustedBoundary(NSMaxRange(selection))
        return NSRange(location: start, length: max(0, end - start))
    }
}

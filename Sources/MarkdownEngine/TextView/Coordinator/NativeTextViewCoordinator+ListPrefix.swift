import AppKit

extension NativeTextViewCoordinator {
    /// Backspace from the first visible character of a rendered list item should
    /// behave like ordinary line-start Backspace: remove the presentation-only
    /// prefix and join the content to the previous line. On the document's first
    /// line, the same gesture simply converts the item to a paragraph.
    func handleBackspaceAtProtectedListStart(_ textView: NSTextView) -> Bool {
        let selection = textView.selectedRange()
        guard selection.length == 0, selection.location > 0,
              let protectedRange = MarkdownStyler.listProtectedRange(
                at: selection.location - 1,
                in: textView.string
              ),
              NSMaxRange(protectedRange) == selection.location else {
            return false
        }

        let nsText = textView.string as NSString
        let originalLength = nsText.length
        let joinsPreviousLine = protectedRange.location > 0
            && nsText.character(at: protectedRange.location - 1) == 0x0A
        let removalStart = joinsPreviousLine
            ? protectedRange.location - 1
            : protectedRange.location
        let removalRange = NSRange(
            location: removalStart,
            length: selection.location - removalStart
        )

        MarkdownLists.performEdit(textView, replace: removalRange, with: "")
        guard (textView.string as NSString).length == originalLength - removalRange.length else {
            return false
        }
        textView.setSelectedRange(NSRange(location: removalStart, length: 0))
        return true
    }

    func redirectSelectionFromProtectedListPrefix(in textView: NSTextView) -> Bool {
        guard !isAdjustingListSelection else { return false }
        let selection = textView.selectedRange()
        guard selection.length == 0,
              let protectedRange = MarkdownStyler.listProtectedRange(
                at: selection.location,
                in: textView.string
              ) else { return false }

        let event = NSApp.currentEvent
        let isPlainLeftArrow = event?.type == .keyDown
            && event?.keyCode == 123
            && event?.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty == true
        let movingBackwardFromContent = isPlainLeftArrow
            && previousSelectedRange?.location == NSMaxRange(protectedRange)
        let target = movingBackwardFromContent && protectedRange.location > 0
            ? protectedRange.location - 1
            : NSMaxRange(protectedRange)

        isAdjustingListSelection = true
        textView.setSelectedRange(NSRange(location: target, length: 0))
        isAdjustingListSelection = false
        return true
    }

    func editTouchesProtectedListPrefix(
        affectedRange: NSRange,
        replacement: String?,
        in text: String
    ) -> Bool {
        let nsText = text as NSString
        guard affectedRange.location >= 0,
              NSMaxRange(affectedRange) <= nsText.length else { return false }
        let currentText = nsText.substring(with: affectedRange)
        let isCheckboxToggle = currentText.range(
            of: #"^\[[ xX]\]$"#,
            options: .regularExpression
        ) != nil && (replacement == "[ ]" || replacement == "[x]")
        if isCheckboxToggle { return false }

        let probeLocations = [
            affectedRange.location,
            max(affectedRange.location, NSMaxRange(affectedRange) - 1),
        ]
        for location in probeLocations {
            guard let protectedRange = MarkdownStyler.listProtectedRange(
                at: location,
                in: text
            ) else { continue }
            let intersects = affectedRange.length == 0
                ? NSLocationInRange(affectedRange.location, protectedRange)
                : NSIntersectionRange(affectedRange, protectedRange).length > 0
            guard intersects else { continue }
            let lineRange = nsText.lineRange(
                for: NSRange(location: protectedRange.location, length: 0)
            )
            let removesWholePrefix = affectedRange.location <= protectedRange.location
                && NSMaxRange(affectedRange) >= NSMaxRange(protectedRange)
            let removesWholeLine = affectedRange.location <= lineRange.location
                && NSMaxRange(affectedRange) >= NSMaxRange(lineRange)
            if !removesWholePrefix && !removesWholeLine { return true }
        }
        return false
    }
}

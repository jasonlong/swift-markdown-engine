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

        // Task item: Backspace from the content start demotes the task to a
        // plain bullet — remove just the `[ ] ` checkbox and keep the bullet
        // marker — rather than deleting the whole prefix and joining the
        // previous line. A second Backspace then removes the bare bullet.
        if let demotionRange = MarkdownStyler.taskCheckboxDemotionRange(
            at: selection.location - 1,
            in: textView.string
        ) {
            let originalLength = (textView.string as NSString).length
            MarkdownLists.performEdit(textView, replace: demotionRange, with: "")
            guard (textView.string as NSString).length
                == originalLength - demotionRange.length else {
                return false
            }
            textView.setSelectedRange(NSRange(location: demotionRange.location, length: 0))
            return true
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

    /// What to do with a proposed edit that touches a protected list prefix.
    enum ProtectedListPrefixEditAction {
        /// The edit leaves every prefix intact (or removes whole ones) — let
        /// it proceed as proposed.
        case allow
        /// The edit would corrupt a prefix and cannot be repaired (a caret
        /// insertion inside the prefix, or typing over a partial slice of
        /// it) — drop the keystroke.
        case block
        /// A deletion partially covering a prefix: a half-deleted `- [ ] `
        /// is never what the user meant, so grow the deletion to the full
        /// prefix and perform it programmatically.
        case expandDeletion(NSRange)
    }

    func protectedListPrefixEditAction(
        affectedRange: NSRange,
        replacement: String?,
        in text: String
    ) -> ProtectedListPrefixEditAction {
        let nsText = text as NSString
        guard affectedRange.location >= 0,
              NSMaxRange(affectedRange) <= nsText.length else { return .allow }
        let currentText = nsText.substring(with: affectedRange)
        let isCheckboxToggle = currentText.range(
            of: #"^\[[ xX]\]$"#,
            options: .regularExpression
        ) != nil && (replacement == "[ ]" || replacement == "[x]")
        if isCheckboxToggle { return .allow }

        var expandedRange = affectedRange
        var touchesPartialPrefix = false
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
            if removesWholePrefix || removesWholeLine { continue }
            touchesPartialPrefix = true
            expandedRange = NSUnionRange(expandedRange, protectedRange)
        }
        guard touchesPartialPrefix else { return .allow }
        let isDeletion = replacement?.isEmpty ?? true
        guard affectedRange.length > 0, isDeletion else { return .block }
        return .expandDeletion(expandedRange)
    }

    /// Whether the proposed edit can proceed exactly as proposed (`false`) or
    /// needs intervention (`true` — blocked or expanded).
    func editTouchesProtectedListPrefix(
        affectedRange: NSRange,
        replacement: String?,
        in text: String
    ) -> Bool {
        if case .allow = protectedListPrefixEditAction(
            affectedRange: affectedRange,
            replacement: replacement,
            in: text
        ) {
            return false
        }
        return true
    }

    /// Forward-delete at the end of a line joins the next line. When the next
    /// line is a rendered list item, its presentation-only prefix must come
    /// along with the newline — mirroring Backspace at the item's start —
    /// instead of surviving as literal `- ` text glued mid-line.
    func handleForwardDeleteBeforeProtectedListPrefix(_ textView: NSTextView) -> Bool {
        let selection = textView.selectedRange()
        let nsText = textView.string as NSString
        guard selection.length == 0,
              selection.location < nsText.length,
              nsText.character(at: selection.location) == 0x0A,
              let protectedRange = MarkdownStyler.listProtectedRange(
                at: selection.location + 1,
                in: textView.string
              ),
              protectedRange.location == selection.location + 1 else {
            return false
        }

        let originalLength = nsText.length
        let removalRange = NSRange(
            location: selection.location,
            length: 1 + protectedRange.length
        )
        MarkdownLists.performEdit(textView, replace: removalRange, with: "")
        guard (textView.string as NSString).length
            == originalLength - removalRange.length else {
            return false
        }
        textView.setSelectedRange(NSRange(location: selection.location, length: 0))
        return true
    }
}

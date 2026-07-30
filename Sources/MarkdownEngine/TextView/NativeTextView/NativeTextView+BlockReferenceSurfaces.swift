import AppKit

private extension NSAttributedString.Key {
    static let markdownBlockReferenceSurface = NSAttributedString.Key("MarkdownEngine.blockReferenceSurface")
    static let markdownBlockReferenceOriginalParagraph = NSAttributedString.Key("MarkdownEngine.blockReference.originalParagraph")
    static let markdownBlockReferenceOriginalLink = NSAttributedString.Key("MarkdownEngine.blockReference.originalLink")
    static let markdownBlockReferenceOriginalBulletMarker = NSAttributedString.Key("MarkdownEngine.blockReference.originalBulletMarker")
    static let markdownBlockReferenceOriginalTaskCheckbox = NSAttributedString.Key("MarkdownEngine.blockReference.originalTaskCheckbox")
    static let markdownBlockReferenceOriginalListMarkerPrefix = NSAttributedString.Key("MarkdownEngine.blockReference.originalListMarkerPrefix")
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

        let availableWidth = max(180, bounds.width - textContainerInset.width * 2)
        var pending: [(
            token: MarkdownBlockReferenceToken,
            surface: MarkdownBlockReferenceSurface,
            visualIndent: CGFloat,
            availableWidth: CGFloat,
            layoutHeight: CGFloat
        )] = []
        storage.beginEditing()
        for token in MarkdownBlockReferenceSyntax.tokens(in: source) where token.kind == .transclusion {
            let visualIndent = blockReferenceVisualIndent(
                for: token,
                in: sourceNSString
            )
            let surfaceWidth = max(1, availableWidth - visualIndent)
            guard let presentation = presentationProvider(token),
                  let surface = surfaceProvider(token, presentation, surfaceWidth),
                  token.range.length > 0
            else { continue }

            let paragraphRange = sourceNSString.paragraphRange(for: token.range)
            let existingParagraph = (storage.attribute(.paragraphStyle, at: token.range.location, effectiveRange: nil)
                as? NSParagraphStyle) ?? NSParagraphStyle.default
            let paragraph = existingParagraph.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            let layoutHeight = blockReferenceListLineHeight(
                including: surface.height
            )
            paragraph.minimumLineHeight = max(
                paragraph.minimumLineHeight,
                layoutHeight
            )
            paragraph.maximumLineHeight = max(
                paragraph.maximumLineHeight,
                layoutHeight
            )
            paragraph.lineSpacing = max(
                paragraph.lineSpacing,
                configuration.lists.extraLineHeight
            )
            paragraph.paragraphSpacing = max(
                paragraph.paragraphSpacing,
                blockReferenceListParagraphSpacing
            )
            paragraph.paragraphSpacingBefore = max(
                0,
                paragraph.paragraphSpacingBefore
            )
            paragraph.lineBreakMode = .byClipping
            storage.addAttribute(.markdownBlockReferenceOriginalParagraph, value: existingParagraph, range: paragraphRange)
            storage.addAttribute(.paragraphStyle, value: paragraph, range: paragraphRange)
            if let link = storage.attribute(.link, at: token.range.location, effectiveRange: nil) {
                storage.addAttribute(.markdownBlockReferenceOriginalLink, value: link, range: token.range)
            }
            storage.removeAttribute(.link, range: token.range)
            preserveAndRemoveBlockReferenceAttribute(
                .bulletMarker,
                backupKey: .markdownBlockReferenceOriginalBulletMarker,
                range: token.range,
                storage: storage
            )
            preserveAndRemoveBlockReferenceAttribute(
                .taskCheckbox,
                backupKey: .markdownBlockReferenceOriginalTaskCheckbox,
                range: token.range,
                storage: storage
            )
            preserveAndRemoveBlockReferenceAttribute(
                .listMarkerPrefix,
                backupKey:
                    .markdownBlockReferenceOriginalListMarkerPrefix,
                range: token.range,
                storage: storage
            )
            storage.addAttributes([
                .markdownBlockReferenceSurface: true,
                .foregroundColor: NSColor.clear,
                .font: NSFont.systemFont(ofSize: 0.1),
                .kern: -0.1,
            ], range: token.range)
            pending.append((
                token,
                surface,
                visualIndent,
                surfaceWidth,
                layoutHeight
            ))
        }
        storage.endEditing()

        guard !pending.isEmpty else { return }
        if let textLayoutManager {
            textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)
        }
        if let scrollView = enclosingScrollView {
            recalcOverscroll(for: scrollView, debugTag: "blockReferenceSurface")
            (scrollView as? ClampedScrollView)?.clampToInsets()
        }

        for entry in pending {
            let tokenRect = layoutBridge.boundingRect(forCharacterRange: entry.token.range, in: textContainer)
            guard !tokenRect.isEmpty else { continue }
            let surfaceX: CGFloat
            if let markerCenterOffset = entry.surface.markerCenterOffset {
                surfaceX = frame.minX + blockReferenceMarkerCenterX(
                    for: entry.visualIndent
                ) - markerCenterOffset
            } else {
                surfaceX = frame.minX + textContainerOrigin.x
                    + entry.visualIndent
            }
            let frame = NSRect(
                x: surfaceX,
                y: frame.minY + textContainerOrigin.y + tokenRect.minY,
                width: entry.availableWidth,
                height: entry.layoutHeight
            )
            entry.surface.view.frame = frame.integral
            if let interactive =
                entry.surface.view as? MarkdownBlockReferenceInteractiveView
            {
                interactive.setBlockReferenceInteractionHandler {
                    [weak self] interaction in
                    self?.handleBlockReferenceSurfaceInteraction(
                        interaction,
                        token: entry.token
                    )
                }
            }
            host.addSubview(entry.surface.view, positioned: .above, relativeTo: self)
            entry.surface.view.needsDisplay = true
            blockReferenceSurfaceViews.append(entry.surface.view)
            mountedBlockReferenceSurfaces.append(
                MountedBlockReferenceSurface(
                    token: entry.token,
                    view: entry.surface.view
                )
            )
        }
        updateBlockReferenceSurfaceSelectionStates()
    }

    /// The source token has a near-zero rendering font, so TextKit cannot be
    /// trusted to preserve the advance of leading tabs. Reconstruct the same
    /// grid indentation ordinary list rows use, then give the host surface the
    /// remaining usable width for wrapping.
    private func blockReferenceVisualIndent(
        for token: MarkdownBlockReferenceToken,
        in source: NSString
    ) -> CGFloat {
        let lineRange = source.lineRange(for: token.range)
        let line = source.substring(with: lineRange)
        let leading = String(line.prefix { $0 == " " || $0 == "\t" })
        return CGFloat(MarkdownLists.indentLevel(from: leading))
            * configuration.lists.indentPerLevel
    }

    /// Native list bullets are centered within the advance of the source `-`
    /// marker. A hosted copied node has a wider marker plus a caret gutter, so
    /// align its declared marker center to this same column explicitly.
    private func blockReferenceMarkerCenterX(for visualIndent: CGFloat) -> CGFloat {
        let font = baseFont
        let markerWidth = ("-" as NSString).size(
            withAttributes: [.font: font]
        ).width
        return textContainerOrigin.x
            + configuration.lists.firstLevelIndent
            + visualIndent
            + markerWidth / 2
    }

    /// Host rows represent outline items even when their source token is a
    /// standalone reference. Reserve the same text height and after-row gap a
    /// native list item receives, so the next row never closes up around one.
    private func blockReferenceListLineHeight(
        including surfaceHeight: CGFloat
    ) -> CGFloat {
        let nativeLineHeight = ceil(
            baseFont.ascender - baseFont.descender + baseFont.leading
        ) + configuration.paragraph.lineHeightExtraSpacing
        return max(surfaceHeight, nativeLineHeight)
    }

    private var blockReferenceListParagraphSpacing: CGFloat {
        let nativeLineHeight = ceil(
            baseFont.ascender - baseFont.descender + baseFont.leading
        )
        return ceil(nativeLineHeight * configuration.paragraph.spacingFactor)
    }

    func removeBlockReferenceSurfaces() {
        for mounted in mountedBlockReferenceSurfaces {
            (
                mounted.view as? MarkdownBlockReferenceInteractiveView
            )?.setBlockReferenceInteractionHandler(nil)
        }
        mountedBlockReferenceSurfaces.removeAll()
        for view in blockReferenceSurfaceViews { view.removeFromSuperview() }
        blockReferenceSurfaceViews.removeAll()
        guard let storage = textStorage, storage.length > 0 else { return }
        restoreBlockReferenceAttributes(
            in: storage,
            fullRange: NSRange(location: 0, length: storage.length)
        )
    }

    private func restoreBlockReferenceAttributes(in storage: NSTextStorage, fullRange: NSRange) {
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
        var links: [(value: Any, range: NSRange)] = []
        storage.enumerateAttribute(.markdownBlockReferenceOriginalLink, in: fullRange) { value, range, _ in
            guard let value else { return }
            links.append((value, range))
        }
        for (value, range) in links {
            storage.addAttribute(.link, value: value, range: range)
            storage.removeAttribute(.markdownBlockReferenceOriginalLink, range: range)
        }
        restoreBlockReferenceAttribute(
            .bulletMarker,
            backupKey: .markdownBlockReferenceOriginalBulletMarker,
            storage: storage,
            fullRange: fullRange
        )
        restoreBlockReferenceAttribute(
            .taskCheckbox,
            backupKey: .markdownBlockReferenceOriginalTaskCheckbox,
            storage: storage,
            fullRange: fullRange
        )
        restoreBlockReferenceAttribute(
            .listMarkerPrefix,
            backupKey:
                .markdownBlockReferenceOriginalListMarkerPrefix,
            storage: storage,
            fullRange: fullRange
        )
    }

    private func preserveAndRemoveBlockReferenceAttribute(
        _ attribute: NSAttributedString.Key,
        backupKey: NSAttributedString.Key,
        range: NSRange,
        storage: NSTextStorage
    ) {
        var values: [(value: Any, range: NSRange)] = []
        storage.enumerateAttribute(attribute, in: range) {
            value, effectiveRange, _ in
            guard let value else { return }
            values.append((value, effectiveRange))
        }
        for entry in values {
            storage.addAttribute(
                backupKey,
                value: entry.value,
                range: entry.range
            )
        }
        storage.removeAttribute(attribute, range: range)
    }

    private func restoreBlockReferenceAttribute(
        _ attribute: NSAttributedString.Key,
        backupKey: NSAttributedString.Key,
        storage: NSTextStorage,
        fullRange: NSRange
    ) {
        var values: [(value: Any, range: NSRange)] = []
        storage.enumerateAttribute(backupKey, in: fullRange) {
            value, range, _ in
            guard let value else { return }
            values.append((value, range))
        }
        for entry in values {
            storage.addAttribute(
                attribute,
                value: entry.value,
                range: entry.range
            )
            storage.removeAttribute(backupKey, range: entry.range)
        }
    }

    func updateBlockReferenceSurfaceSelectionStates() {
        let selection = selectedRange()
        for mounted in mountedBlockReferenceSurfaces {
            guard let interactive =
                    mounted.view as? MarkdownBlockReferenceInteractiveView
            else { continue }
            interactive.setBlockReferenceSelectionState(
                blockReferenceSelectionState(
                    for: mounted.token,
                    selection: selection
                )
            )
        }
    }

    func shouldSuppressNativeInsertionPointForBlockReference() -> Bool {
        let selection = selectedRange()
        return selection.length == 0 && blockReferenceToken(for: selection) != nil
    }

    func handleBlockReferenceSurfaceInteraction(
        _ interaction: MarkdownBlockReferenceSurfaceInteraction,
        token: MarkdownBlockReferenceToken
    ) {
        switch interaction {
        case .select:
            window?.makeFirstResponder(self)
            setSelectedRange(token.range)
            updateBlockReferenceSurfaceSelectionStates()
        case .placeCaretBefore:
            window?.makeFirstResponder(self)
            setSelectedRange(NSRange(location: token.range.location, length: 0))
            updateBlockReferenceSurfaceSelectionStates()
        case .placeCaretAfter:
            window?.makeFirstResponder(self)
            setSelectedRange(NSRange(location: NSMaxRange(token.range), length: 0))
            updateBlockReferenceSurfaceSelectionStates()
        case .indent:
            window?.makeFirstResponder(self)
            _ = adjustBlockReferenceIndentation(
                for: token,
                direction: .indent
            )
        case .outdent:
            window?.makeFirstResponder(self)
            _ = adjustBlockReferenceIndentation(
                for: token,
                direction: .outdent
            )
        }
    }

    enum BlockReferenceCommand {
        case indent
        case outdent
        case deleteBackward
        case deleteForward
    }

    func handleBlockReferenceCommand(
        _ command: BlockReferenceCommand
    ) -> Bool {
        let selection = selectedRange()
        guard let token = blockReferenceToken(for: selection) else {
            return false
        }
        let state = blockReferenceSelectionState(
            for: token,
            selection: selection
        )

        switch command {
        case .indent:
            return adjustBlockReferenceIndentation(
                for: token,
                direction: .indent
            )
        case .outdent:
            _ = adjustBlockReferenceIndentation(
                for: token,
                direction: .outdent
            )
            return true
        case .deleteBackward:
            switch state {
            case .selected:
                return performBlockReferenceDelete(for: token)
            case .caretAfter:
                setSelectedRange(token.range)
                updateBlockReferenceSurfaceSelectionStates()
                return true
            case .caretBefore:
                _ = adjustBlockReferenceIndentation(
                    for: token,
                    direction: .outdent
                )
                return true
            case .none:
                return false
            }
        case .deleteForward:
            switch state {
            case .selected:
                return performBlockReferenceDelete(for: token)
            case .caretBefore:
                setSelectedRange(token.range)
                updateBlockReferenceSurfaceSelectionStates()
                return true
            case .caretAfter:
                return true
            case .none:
                return false
            }
        }
    }

    func redirectSelectionAroundBlockReference() -> Bool {
        let selection = selectedRange()
        let tokens = MarkdownBlockReferenceSyntax.tokens(in: string)
            .filter { $0.kind == .transclusion }

        if selection.length == 0,
           let token = tokens.first(where: {
               selection.location > $0.range.location
                   && selection.location < NSMaxRange($0.range)
           })
        {
            let event = NSApp.currentEvent
            let modifiers = event?.modifierFlags.intersection(
                .deviceIndependentFlagsMask
            ) ?? []
            let plainArrow = event?.type == .keyDown && modifiers.isEmpty
            let previous = (
                delegate as? NativeTextViewCoordinator
            )?.previousSelectedRange
            let target: NSRange
            if plainArrow, event?.keyCode == 124,
               previous == NSRange(
                   location: token.range.location,
                   length: 0
               )
            {
                target = token.range
            } else if plainArrow, event?.keyCode == 123,
                      previous == NSRange(
                          location: NSMaxRange(token.range),
                          length: 0
                      )
            {
                target = token.range
            } else {
                let distanceToStart =
                    selection.location - token.range.location
                let distanceToEnd =
                    NSMaxRange(token.range) - selection.location
                target = NSRange(
                    location: distanceToStart <= distanceToEnd
                        ? token.range.location
                        : NSMaxRange(token.range),
                    length: 0
                )
            }
            setSelectedRange(target)
            return true
        }

        if selection.length > 0,
           let token = tokens.first(where: {
               NSIntersectionRange(selection, $0.range).length > 0
                   && (
                       selection.location > $0.range.location
                           || NSMaxRange(selection)
                               < NSMaxRange($0.range)
                   )
           })
        {
            let start = min(selection.location, token.range.location)
            let end = max(NSMaxRange(selection), NSMaxRange(token.range))
            setSelectedRange(
                NSRange(location: start, length: end - start)
            )
            return true
        }
        return false
    }

    private enum BlockReferenceIndentDirection {
        case indent
        case outdent
    }

    @discardableResult
    private func adjustBlockReferenceIndentation(
        for token: MarkdownBlockReferenceToken,
        direction: BlockReferenceIndentDirection
    ) -> Bool {
        let source = string as NSString
        let lineRange = source.lineRange(for: token.range)
        let line = source.substring(with: lineRange) as NSString
        let leading = line.range(
            of: #"^[ \t]*"#,
            options: .regularExpression
        )
        let leadingWhitespace = line.substring(with: leading)
        let originalState = blockReferenceSelectionState(
            for: token,
            selection: selectedRange()
        )
        let matchingTokens = MarkdownBlockReferenceSyntax.tokens(
            in: string
        ).filter {
            $0.kind == token.kind
                && $0.noteTarget == token.noteTarget
                && $0.blockID == token.blockID
        }
        guard let occurrence = matchingTokens.firstIndex(of: token) else {
            return false
        }

        let editRange: NSRange
        let replacement: String
        switch direction {
        case .indent:
            let level = MarkdownLists.indentLevel(
                from: leadingWhitespace
            )
            guard level < configuration.lists.maximumNestingLevel else {
                return true
            }
            editRange = NSRange(location: lineRange.location, length: 0)
            replacement = "\t"
        case .outdent:
            if leadingWhitespace.hasPrefix("\t") {
                editRange = NSRange(location: lineRange.location, length: 1)
            } else {
                let spaces = leadingWhitespace.prefix(2).prefix {
                    $0 == " "
                }.count
                guard spaces > 0 else { return false }
                editRange = NSRange(
                    location: lineRange.location,
                    length: spaces
                )
            }
            replacement = ""
        }

        MarkdownLists.performEdit(
            self,
            replace: editRange,
            with: replacement
        )
        let refreshed = MarkdownBlockReferenceSyntax.tokens(in: string)
            .filter {
                $0.kind == token.kind
                    && $0.noteTarget == token.noteTarget
                    && $0.blockID == token.blockID
            }
        guard refreshed.indices.contains(occurrence) else { return true }
        let updatedToken = refreshed[occurrence]
        let updatedSelection: NSRange
        switch originalState {
        case .caretBefore:
            updatedSelection = NSRange(
                location: updatedToken.range.location,
                length: 0
            )
        case .caretAfter:
            updatedSelection = NSRange(
                location: NSMaxRange(updatedToken.range),
                length: 0
            )
        case .selected, .none:
            updatedSelection = updatedToken.range
        }
        setSelectedRange(updatedSelection)
        updateBlockReferenceSurfaces()
        return true
    }

    private func blockReferenceToken(
        for selection: NSRange
    ) -> MarkdownBlockReferenceToken? {
        MarkdownBlockReferenceSyntax.tokens(in: string)
            .filter { $0.kind == .transclusion }
            .first { token in
                if selection.length == 0 {
                    return selection.location == token.range.location
                        || selection.location == NSMaxRange(token.range)
                }
                return NSIntersectionRange(
                    selection,
                    token.range
                ).length > 0
            }
    }

    private func blockReferenceSelectionState(
        for token: MarkdownBlockReferenceToken,
        selection: NSRange
    ) -> MarkdownBlockReferenceSelectionState {
        if selection.length == 0 {
            if selection.location == token.range.location {
                return .caretBefore
            }
            if selection.location == NSMaxRange(token.range) {
                return .caretAfter
            }
            return .none
        }
        return NSIntersectionRange(selection, token.range).length > 0
            ? .selected
            : .none
    }

    private func performBlockReferenceDelete(
        for token: MarkdownBlockReferenceToken
    ) -> Bool {
        guard let mounted = mountedBlockReferenceSurfaces.first(where: {
            $0.token == token
        }), let interactive =
            mounted.view as? MarkdownBlockReferenceInteractiveView
        else { return false }
        interactive.performBlockReferenceDelete()
        return true
    }
}

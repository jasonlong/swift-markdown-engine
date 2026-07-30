//
//  NativeTextView+CaretWorkarounds.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 16.03.26.
//
//  Caret-indicator workarounds: block-image hide/resize + trailing-`\n` Y-snap (FB22524198).
//

import AppKit

extension NativeTextView {
    /// Keyboard navigation treats visually collapsed Markdown separators as
    /// layout spacing, not as a destination. Mouse placement still reaches
    /// the real blank line so a user can intentionally reveal and edit it.
    override func moveDown(_ sender: Any?) {
        let selection = selectedRange()
        let compactedRun = selection.length == 0
            ? compactedBlankRun(after: selection.location)
            : nil
        super.moveDown(sender)
        skipCompactedBlankRunIfNeeded(compactedRun, movingDown: true, sender: sender)
    }

    override func moveUp(_ sender: Any?) {
        let selection = selectedRange()
        let compactedRun = selection.length == 0
            ? compactedBlankRun(before: selection.location)
            : nil
        super.moveUp(sender)
        skipCompactedBlankRunIfNeeded(compactedRun, movingDown: false, sender: sender)
    }

    private func compactedBlankRun(after location: Int) -> NSRange? {
        guard let textStorage else { return nil }
        let text = textStorage.string as NSString
        guard location >= 0, location <= text.length else { return nil }
        let currentLine = text.lineRange(
            for: NSRange(location: min(location, text.length), length: 0)
        )
        let candidate = NSMaxRange(currentLine)
        guard candidate < text.length else { return nil }
        return compactedBlankRun(at: candidate, in: textStorage)
    }

    private func compactedBlankRun(before location: Int) -> NSRange? {
        guard let textStorage else { return nil }
        let text = textStorage.string as NSString
        guard location > 0, location <= text.length else { return nil }
        let currentLine = text.lineRange(
            for: NSRange(location: min(location, text.length), length: 0)
        )
        guard currentLine.location > 0 else { return nil }
        return compactedBlankRun(
            at: currentLine.location - 1,
            in: textStorage
        )
    }

    private func compactedBlankRun(
        at location: Int,
        in textStorage: NSTextStorage
    ) -> NSRange? {
        guard let run = MarkdownStyler.blankRunRange(
            at: location,
            in: textStorage.string
        ), run.length > 0 else {
            return nil
        }
        var hasCompactedLine = false
        let compactedThreshold = max(1, baseFont.pointSize * 0.5)
        textStorage.enumerateAttribute(
            .paragraphStyle,
            in: run,
            options: []
        ) { value, _, stop in
            guard let style = value as? NSParagraphStyle,
                  style.maximumLineHeight > 0,
                  style.maximumLineHeight < compactedThreshold else {
                return
            }
            hasCompactedLine = true
            stop.pointee = true
        }
        return hasCompactedLine ? run : nil
    }

    private func skipCompactedBlankRunIfNeeded(
        _ run: NSRange?,
        movingDown: Bool,
        sender: Any?
    ) {
        guard let run else { return }
        var attempts = max(1, run.length + 1)
        while attempts > 0,
              selectedRange().length == 0,
              NSLocationInRange(selectedRange().location, run) {
            if movingDown {
                super.moveDown(sender)
            } else {
                super.moveUp(sender)
            }
            attempts -= 1
        }
    }

    override func updateInsertionPointStateAndRestartTimer(_ restartFlag: Bool) {
        super.updateInsertionPointStateAndRestartTimer(restartFlag)
        applyBlockImageCaretPolicy()
        applyVirtualListCaretPolicy()
        DispatchQueue.main.async { [weak self] in
            self?.fixPhantomTrailingCaret()
            self?.applyVirtualListCaretPolicy()
        }
    }

    func applyBlockImageCaretPolicy() {
        let indicators = subviews.filter { type(of: $0) == NSTextInsertionIndicator.self }
        guard !indicators.isEmpty else { return }

        var hide = false
        var resize = false
        if let ts = textStorage {
            let sel = selectedRange()
            if sel.length != 0 || sel.location > ts.length {
                hide = true
            } else if sel.location < ts.length {
                let paraRange = (ts.string as NSString).paragraphRange(
                    for: NSRange(location: sel.location, length: 0)
                )
                ts.enumerateAttribute(.latexIsBlock, in: paraRange, options: []) { value, range, stop in
                    guard value as? Bool == true else { return }
                    if ts.attribute(.latexBlockOffsetY, at: range.location, effectiveRange: nil) != nil {
                        resize = true
                    } else {
                        hide = true
                        stop.pointee = true
                    }
                }
            }
        }

        for sub in indicators {
            if !hide && resize { resizeIndicatorToLayoutCaret(sub) }
            if sub.isHidden != hide { sub.isHidden = hide }
        }
    }

    /// After collapsed→visible, the indicator frame stays at image height; snap it to the layout manager's actual caret rect.
    func resizeIndicatorToLayoutCaret(_ indicator: NSView) {
        guard let tlm = textLayoutManager,
              let tcs = tlm.textContentManager as? NSTextContentStorage,
              let docLoc = tcs.location(tcs.documentRange.location, offsetBy: selectedRange().location) else { return }
        var layoutRect: CGRect?
        tlm.enumerateTextSegments(in: NSTextRange(location: docLoc), type: .standard, options: [.rangeNotRequired]) { _, f, _, _ in
            layoutRect = f; return false
        }
        guard let r = layoutRect, r.height > 0,
              indicator.frame.height > r.height + 1 else { return }
        isApplyingCaretShift = true
        indicator.frame = CGRect(x: indicator.frame.origin.x, y: r.origin.y,
                                 width: indicator.frame.width, height: r.height)
        isApplyingCaretShift = false
    }

    /// FB22524198: AppKit drops the trailing-`\n` caret onto the previous line's top — snap it to `lastLineMaxY + paragraphSpacing` instead. (Companion to FB15131180; this one fixes Y, the other fixes height.)
    func fixPhantomTrailingCaret() {
        if let indicator = subviews.first(where: { type(of: $0) == NSTextInsertionIndicator.self }),
           observedCaretIndicator !== indicator {
            caretIndicatorObservation?.invalidate()
            observedCaretIndicator = indicator
            caretIndicatorObservation = indicator.observe(\.frame, options: [.new]) { [weak self] _, _ in
                guard let self, !self.isApplyingCaretShift else { return }
                self.applyBlockImageCaretPolicy()
                self.fixPhantomTrailingCaret()
                self.applyVirtualListCaretPolicy()
            }
        }
        guard let ts = textStorage, let indicator = observedCaretIndicator,
              let tlm = textLayoutManager,
              let tcs = tlm.textContentManager as? NSTextContentStorage else { return }
        let sel = selectedRange()
        let ns = ts.string as NSString
        guard sel.length == 0, sel.location == ns.length, ns.length > 0,
              ns.character(at: ns.length - 1) == 0x0A,
              let trailingLoc = tcs.location(tcs.documentRange.location, offsetBy: ns.length - 1) else {
            return
        }
        var desiredY: CGFloat?
        tlm.enumerateTextLayoutFragments(from: trailingLoc, options: [.ensuresLayout]) { fragment in
            // Use the LAST text line (length > 0) so multi-line wrapped paragraphs aren't pulled to the first line.
            let lastTextLine = fragment.textLineFragments.last { $0.characterRange.length > 0 }
                ?? fragment.textLineFragments.last
            guard let line = lastTextLine else { return false }
            let lineMaxY = fragment.layoutFragmentFrame.origin.y + line.typographicBounds.maxY
            let style = ts.attribute(.paragraphStyle, at: ns.length - 1, effectiveRange: nil) as? NSParagraphStyle
            // Layout-fragment Y is textContainer-relative; the indicator frame is textView-relative — add the textContainerInset offset so the snap stays correct when an embedder configures non-zero text insets.
            desiredY = lineMaxY + (style?.paragraphSpacing ?? 0) + self.textContainerInset.height
            return false
        }
        guard let desiredY, abs(indicator.frame.origin.y - desiredY) >= 0.5 else { return }
        isApplyingCaretShift = true
        indicator.frame.origin.y = desiredY
        isApplyingCaretShift = false
    }

    func applyVirtualListCaretPolicy() {
        guard selectedRange().length == 0,
              let metrics = virtualListPlaceholderMetrics,
              let indicator = subviews.first(where: {
                  type(of: $0) == NSTextInsertionIndicator.self
              }) else {
            return
        }
        let desiredX = textContainerOrigin.x + metrics.contentX
        guard abs(indicator.frame.origin.x - desiredX) >= 0.5 else { return }
        isApplyingCaretShift = true
        indicator.frame.origin.x = desiredX
        isApplyingCaretShift = false
    }
}

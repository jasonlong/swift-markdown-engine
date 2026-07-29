//
//  NativeTextView+CursorRects.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 27.05.26.
//
//  Cursor handling and wiki-link hover hit testing.
//

import AppKit

extension NativeTextView {

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let wikiLinkHoverTrackingArea {
            removeTrackingArea(wikiLinkHoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [
                .activeInKeyWindow,
                .inVisibleRect,
                .mouseEnteredAndExited,
                .mouseMoved,
            ],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        wikiLinkHoverTrackingArea = trackingArea
    }

    override func mouseMoved(with event: NSEvent) {
        if isInCursorExclusionZone(event) {
            // Editable+excluded = a panel over the editor (#81): own the arrow.
            // Read-only+excluded = a full-window overlay (search/transfer) owns
            // the cursor; stay silent — our tracking areas fire beneath it and
            // any set here fights the overlay's cursor (flicker).
            if isEditable { NSCursor.arrow.set() }
        } else if isEditable, isOverBlockReferenceDragHandle(event) {
            toolTip = "Drag to create a block reference"
            NSCursor.openHand.set()
        } else if isEditable, isOverOutlineBullet(event) {
            NSCursor.pointingHand.set()
        } else if isEditable, isOverTaskCheckboxBox(event) {
            // The box is a clickable control, not text. super sets the I-beam
            // on every move, so setting the arrow after it flickers — skip
            // super entirely, like the exclusion-zone branch.
            NSCursor.arrow.set()
        } else if isEditable, isOverWideTableOverlay(event) {
            // Same treatment for wide-table scroll overlays: the overlay is a
            // control surface (rendered image + horizontal scroller), not
            // text, but the text view's tracking areas are not occlusion-aware
            // and super keeps setting the I-beam through it.
            NSCursor.arrow.set()
        } else {
            toolTip = nil
            super.mouseMoved(with: event)
            applyTextCursorOverride(for: event)
        }
        updateWikiLinkHover(for: event)
    }

    override func mouseEntered(with event: NSEvent) {
        if isInCursorExclusionZone(event) {
            if isEditable { NSCursor.arrow.set() }
        } else if isEditable, isOverBlockReferenceDragHandle(event) {
            toolTip = "Drag to create a block reference"
            NSCursor.openHand.set()
        } else if isEditable, isOverOutlineBullet(event) {
            NSCursor.pointingHand.set()
        } else if isEditable, isOverTaskCheckboxBox(event) {
            NSCursor.arrow.set()
        } else if isEditable, isOverWideTableOverlay(event) {
            NSCursor.arrow.set()
        } else {
            toolTip = nil
            super.mouseEntered(with: event)
            applyTextCursorOverride(for: event)
        }
        updateWikiLinkHover(for: event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        toolTip = nil
        clearWikiLinkHover()
    }

    /// True when the pointer is over a wide-table overlay's HORIZONTAL
    /// SCROLLER (mirrors the task-checkbox suppression above; read-only mode
    /// already shows the arrow via `applyReadOnlyCursor`). Only the scroller
    /// strip is a control surface — over the rendered table image itself the
    /// normal text cursor behavior stays.
    private func isOverWideTableOverlay(_ event: NSEvent) -> Bool {
        guard !wideTableOverlays.isEmpty else { return false }
        for (_, overlay) in wideTableOverlays where overlay.superview != nil && !overlay.isHidden {
            guard let scroller = overlay.horizontalScroller, !scroller.isHidden else { continue }
            let point = scroller.convert(event.locationInWindow, from: nil)
            if scroller.bounds.contains(point) { return true }
        }
        return false
    }

    /// True inside an embedder exclusion zone — a panel over the editor or a
    /// full-window overlay (search/transfer) that owns the cursor. NOT gated on
    /// `isEditable`: overlays make the editor read-only, and gating let its
    /// cursor path keep firing beneath them (flicker in search).
    private func isInCursorExclusionZone(_ event: NSEvent) -> Bool {
        guard let excluded = isCursorExcluded else { return false }
        return excluded(event.locationInWindow)
    }

    /// Pointing hand over clickable links in both edit and read-only modes.
    /// Outside links, editable text keeps NSTextView's I-beam while read-only
    /// text uses the arrow.
    private func applyTextCursorOverride(for event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        textCursorOverride(at: viewPoint)?.set()
    }

    /// Returns only the cursor that MarkdownEngine needs to override.
    /// `nil` lets editable prose retain NSTextView's normal I-beam.
    func textCursorOverride(at viewPoint: CGPoint) -> NSCursor? {
        guard isSelectable else { return nil }
        if linkHit(at: viewPoint) != nil { return .pointingHand }
        return isEditable ? nil : .arrow
    }

    /// True when the pointer is over a drawn task-checkbox square (edit mode
    /// suppresses the I-beam there — the box is a clickable control, not text;
    /// read-only mode already shows the arrow via `applyReadOnlyCursor`).
    private func isOverTaskCheckboxBox(_ event: NSEvent) -> Bool {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let containerPoint = CGPoint(x: viewPoint.x - textContainerOrigin.x,
                                     y: viewPoint.y - textContainerOrigin.y)
        // Bound the attribute scan to the hovered line's fragment — a full-
        // document scan per mouse-move would be O(doc).
        guard let tlm = textLayoutManager,
              let tcs = tlm.textContentManager as? NSTextContentStorage,
              let fragment = tlm.textLayoutFragment(for: containerPoint) else { return false }
        let start = tcs.offset(from: tcs.documentRange.location, to: fragment.rangeInElement.location)
        let end = tcs.offset(from: tcs.documentRange.location, to: fragment.rangeInElement.endLocation)
        guard start != NSNotFound, end > start else { return false }
        let lineRange = NSRange(location: start, length: end - start)
        return taskCheckboxHit(at: containerPoint, in: lineRange) != nil
    }

    /// True when a clickable `.link` attribute exists under the given point
    /// (view coordinates). `.link` is what drives `clickedOnLink`, so this
    /// matches exactly what is clickable.
    struct WikiLinkHoverHit {
        let target: String
        let range: NSRange
        let anchorRect: CGRect
    }

    /// Returns a wiki-link target and exact visible run bounds. URL-valued
    /// Markdown links intentionally return nil: their cursor remains clickable,
    /// but they do not ask the embedder for a note preview.
    func wikiLinkHoverHit(at viewPoint: CGPoint) -> WikiLinkHoverHit? {
        guard let hit = linkHit(at: viewPoint),
              let target = hit.value as? String else { return nil }
        return WikiLinkHoverHit(
            target: target,
            range: hit.range,
            anchorRect: hit.anchorRect
        )
    }

    private struct LinkHit {
        let value: Any
        let range: NSRange
        let anchorRect: CGRect
    }

    private func linkHit(at viewPoint: CGPoint) -> LinkHit? {
        guard let tlm = textLayoutManager,
              let tcs = tlm.textContentManager,
              let textStorage = textStorage, textStorage.length > 0 else { return nil }

        let containerPoint = CGPoint(x: viewPoint.x - textContainerOrigin.x,
                                     y: viewPoint.y - textContainerOrigin.y)
        guard let fragment = tlm.textLayoutFragment(for: containerPoint) else { return nil }

        let fragFrame = fragment.layoutFragmentFrame
        let pInFrag = CGPoint(x: containerPoint.x - fragFrame.minX,
                              y: containerPoint.y - fragFrame.minY)
        // Only accept a line fragment that actually contains the point — guards
        // against clicks in trailing padding / past the end of a line.
        guard let line = fragment.textLineFragments.first(where: {
            $0.typographicBounds.contains(pInFrag)
        }) else { return nil }

        let pInLine = CGPoint(x: pInFrag.x - line.typographicBounds.minX,
                              y: pInFrag.y - line.typographicBounds.minY)
        let idx = line.characterIndex(for: pInLine)
        let lineString = line.attributedString
        guard idx >= 0, idx < lineString.length else { return nil }

        var effectiveRange = NSRange(location: NSNotFound, length: 0)
        let value =
            lineString.attribute(.link, at: idx, effectiveRange: &effectiveRange)
            ?? lineString.attribute(.mutedLink, at: idx, effectiveRange: &effectiveRange)
        guard let value, effectiveRange.location != NSNotFound else { return nil }

        let fragmentStart = tcs.offset(
            from: tcs.documentRange.location,
            to: fragment.rangeInElement.location
        )
        guard fragmentStart != NSNotFound else { return nil }
        let documentRange = NSRange(
            location: fragmentStart + line.characterRange.location + effectiveRange.location,
            length: effectiveRange.length
        )
        guard NSMaxRange(documentRange) <= textStorage.length,
              let start = tcs.location(
                tcs.documentRange.location,
                offsetBy: documentRange.location
              ),
              let end = tcs.location(start, offsetBy: documentRange.length),
              let textRange = NSTextRange(location: start, end: end) else { return nil }

        var anchorRect = CGRect.null
        tlm.enumerateTextSegments(
            in: textRange,
            type: .standard,
            options: []
        ) { _, segmentRect, _, _ in
            anchorRect = anchorRect.isNull ? segmentRect : anchorRect.union(segmentRect)
            return true
        }
        guard !anchorRect.isNull, !anchorRect.isEmpty else { return nil }
        anchorRect.origin.x += textContainerOrigin.x
        anchorRect.origin.y += textContainerOrigin.y
        return LinkHit(value: value, range: documentRange, anchorRect: anchorRect)
    }

    private func updateWikiLinkHover(for event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let hit = wikiLinkHoverHit(at: point) else {
            clearWikiLinkHover()
            return
        }
        guard hoveredWikiLinkTarget != hit.target
                || hoveredWikiLinkRange != hit.range else { return }
        hoveredWikiLinkTarget = hit.target
        hoveredWikiLinkRange = hit.range
        onWikiLinkHover?(
            WikiLinkHoverState(
                target: hit.target,
                anchorRect: hit.anchorRect,
                positioningView: self
            )
        )
    }

    private func clearWikiLinkHover() {
        guard hoveredWikiLinkTarget != nil || hoveredWikiLinkRange != nil else { return }
        hoveredWikiLinkTarget = nil
        hoveredWikiLinkRange = nil
        onWikiLinkHover?(nil)
    }
}

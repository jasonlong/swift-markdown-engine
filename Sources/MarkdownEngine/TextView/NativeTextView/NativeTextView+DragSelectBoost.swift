//
//  NativeTextView+DragSelectBoost.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 16.03.26.
//
//  Mouse-down entry point for the text view, plus the autoscroll-boost timer
//  that keeps drag-selection moving when the cursor sits near a window edge.
//

import AppKit

extension NativeTextView {
    override func mouseDown(with event: NSEvent) {
        let clickPoint = convert(event.locationInWindow, from: nil)
        let characterIndex = characterIndexForInsertion(at: clickPoint)
        if let coordinator = delegate as? NativeTextViewCoordinator,
           let image = coordinator.renderedMarkdownImage(at: characterIndex, in: self),
           let onImageClick = coordinator.onImageClick {
            onImageClick(image)
            return
        }
        // Was the click point on a link? Captured before super.mouseDown, which
        // may park the caret elsewhere. Used to rescue a dropped link click.
        let clickedLink: (location: Int, target: Any)? = {
            let idx = characterIndex
            guard let ts = textStorage, idx >= 0, idx < ts.length else {
                return nil
            }
            let target = ts.attribute(.link, at: idx, effectiveRange: nil)
                ?? ts.attribute(.mutedLink, at: idx, effectiveRange: nil)
            return target.map { (idx, $0) }
        }()
        if toggleOutlineIfHit(event: event) { return }
        if let toggled = toggleTaskCheckboxIfHit(event: event), toggled { return }
        if beginBlockReferenceDragIfHit(event: event) { return }
        if remapClickInParagraphSpacing(event: event) { return }
        dragStartMouseScreenLoc = NSEvent.mouseLocation
        let boostTimer = Timer(timeInterval: 1.0 / configuration.dragSelection.ticksPerSecond, repeats: true) { [weak self] _ in
            self?.performDragBoostTick()
        }
        RunLoop.current.add(boostTimer, forMode: .common)
        defer {
            boostTimer.invalidate()
            dragStartMouseScreenLoc = nil
        }

        linkClickDidFire = false
        linkClickDidNavigate = false
        let preClickSelection = selectedRange()
        let downLoc = NSEvent.mouseLocation
        super.mouseDown(with: event)   // modal tracking loop — returns after mouseUp
        let travel = hypot(NSEvent.mouseLocation.x - downLoc.x, NSEvent.mouseLocation.y - downLoc.y)

        // AppKit intermittently drops clickedOnLink for a stationary single click
        // on a link (selection changed, delegate never called). Re-dispatch it
        // through the same delegate path using the original hit-tested location.
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if let clickedLink,
           !linkClickDidFire, event.clickCount == 1, mods.isEmpty, travel < 2,
           let ts = textStorage, ts.length > 0 {
            if let dlg = delegate as? NativeTextViewCoordinator,
               !dlg.textView(
                self,
                clickedOnLink: clickedLink.target,
                at: clickedLink.location
               ) {
                // Web link: the delegate declines; open the URL as AppKit would.
                if let url = (clickedLink.target as? URL)
                    ?? (clickedLink.target as? String).flatMap(URL.init(string:)),
                   url.scheme != nil {
                    NSWorkspace.shared.open(url)
                }
            }
        }

        // A link click is navigation, not caret placement: restore the pre-click
        // selection (AppKit parked the caret in the link). Edit-zone clicks don't
        // navigate, so they keep their caret.
        if linkClickDidNavigate {
            let docLen = (string as NSString).length
            let loc = min(preClickSelection.location, docLen)
            let len = min(preClickSelection.length, max(0, docLen - loc))
            setSelectedRange(NSRange(location: loc, length: len))
        }
    }

    func performDragBoostTick() {
        guard let window = self.window,
              let scrollView = enclosingScrollView,
              let start = dragStartMouseScreenLoc else { return }

        let mouseScreen = NSEvent.mouseLocation
        let dragPolicy = configuration.dragSelection
        // Require real drag movement so a static click at the window edge doesn't scroll.
        guard max(abs(mouseScreen.x - start.x), abs(mouseScreen.y - start.y)) > dragPolicy.movementThreshold else { return }

        let mouseInWin = window.convertPoint(fromScreen: mouseScreen)
        let direction: CGFloat
        if mouseInWin.y <= dragPolicy.edgeTriggerDistance {
            direction = 1.0
        } else if mouseInWin.y >= window.frame.height - dragPolicy.edgeTriggerDistance {
            direction = -1.0
        } else {
            return
        }

        let origin = scrollView.contentView.bounds.origin
        scrollView.contentView.scroll(to: NSPoint(x: origin.x, y: origin.y + dragPolicy.scrollStepPerTick * direction))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        (scrollView as? ClampedScrollView)?.clampToInsets()
    }
}

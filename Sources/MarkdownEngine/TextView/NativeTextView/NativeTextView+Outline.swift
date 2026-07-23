import AppKit

extension NativeTextView {
    func outlineBulletHit(
        at containerPoint: CGPoint,
        in searchRange: NSRange? = nil
    ) -> NSRange? {
        guard let textContainer,
              let layoutBridge,
              let textStorage,
              textStorage.length > 0 else { return nil }
        let scanRange = searchRange ?? NSRange(location: 0, length: textStorage.length)
        var hitRange: NSRange?
        textStorage.enumerateAttribute(
            .outlineHasChildren,
            in: scanRange,
            options: []
        ) { value, attributeRange, stop in
            guard (value as? Bool) == true else { return }
            let anchor = layoutBridge.boundingRect(
                forCharacterRange: attributeRange,
                in: textContainer
            )
            let hitSize = max(16, anchor.height)
            let hitRect = CGRect(
                x: anchor.midX - hitSize / 2,
                y: anchor.midY - hitSize / 2,
                width: hitSize,
                height: hitSize
            )
            if hitRect.contains(containerPoint) {
                hitRange = attributeRange
                stop.pointee = true
            }
        }
        return hitRange
    }

    func toggleOutlineIfHit(event: NSEvent) -> Bool {
        guard event.clickCount == 1,
              event.type == .leftMouseDown,
              let coordinator = delegate as? NativeTextViewCoordinator else {
            return false
        }
        let localPoint = convert(event.locationInWindow, from: nil)
        let containerPoint = CGPoint(
            x: localPoint.x - textContainerOrigin.x,
            y: localPoint.y - textContainerOrigin.y
        )
        guard let markerRange = outlineBulletHit(at: containerPoint) else { return false }
        return coordinator.toggleOutlineItem(
            at: markerRange.location,
            in: self
        )
    }

    func isOverOutlineBullet(_ event: NSEvent) -> Bool {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let containerPoint = CGPoint(
            x: viewPoint.x - textContainerOrigin.x,
            y: viewPoint.y - textContainerOrigin.y
        )
        guard let textLayoutManager,
              let textContentStorage = textLayoutManager.textContentManager as? NSTextContentStorage,
              let fragment = textLayoutManager.textLayoutFragment(for: containerPoint) else {
            return false
        }
        let start = textContentStorage.offset(
            from: textContentStorage.documentRange.location,
            to: fragment.rangeInElement.location
        )
        let end = textContentStorage.offset(
            from: textContentStorage.documentRange.location,
            to: fragment.rangeInElement.endLocation
        )
        guard start != NSNotFound, end > start else { return false }
        return outlineBulletHit(
            at: containerPoint,
            in: NSRange(location: start, length: end - start)
        ) != nil
    }
}

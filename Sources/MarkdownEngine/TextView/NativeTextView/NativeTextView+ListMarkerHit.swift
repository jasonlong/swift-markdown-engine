import AppKit

extension NativeTextView {
    /// Returns the source syntax range backing a drawn unordered-list bullet or
    /// task checkbox at a point in text-container coordinates.
    func renderedListMarkerHit(at containerPoint: CGPoint) -> NSRange? {
        guard let textContainer,
              let layoutBridge,
              let textStorage,
              textStorage.length > 0,
              let textLayoutManager,
              let contentStorage = textLayoutManager.textContentManager
                as? NSTextContentStorage,
              let fragment = textLayoutManager.textLayoutFragment(
                for: containerPoint
              ) else {
            return nil
        }

        let start = contentStorage.offset(
            from: contentStorage.documentRange.location,
            to: fragment.rangeInElement.location
        )
        let end = contentStorage.offset(
            from: contentStorage.documentRange.location,
            to: fragment.rangeInElement.endLocation
        )
        guard start != NSNotFound, end > start else { return nil }
        let fragmentRange = NSRange(location: start, length: end - start)

        if let task = taskCheckboxHit(
            at: containerPoint,
            in: fragmentRange
        ) {
            return task.range
        }

        var hitRange: NSRange?
        textStorage.enumerateAttribute(
            .bulletMarker,
            in: fragmentRange,
            options: []
        ) { value, markerRange, stop in
            guard (value as? Bool) == true,
                  textStorage.attribute(
                    .outlineHidden,
                    at: markerRange.location,
                    effectiveRange: nil
                  ) == nil else {
                return
            }

            let anchor = layoutBridge.boundingRect(
                forCharacterRange: markerRange,
                in: textContainer
            )
            guard !anchor.isEmpty else { return }
            let font = (
                textStorage.attribute(
                    .font,
                    at: markerRange.location,
                    effectiveRange: nil
                ) as? NSFont
            ) ?? baseFont
            let rawMarker = (textStorage.string as NSString).substring(
                with: markerRange
            )
            let markerWidth = (rawMarker as NSString).size(
                withAttributes: [.font: font]
            ).width
            let hitSize = max(16, anchor.height)
            let hitRect = CGRect(
                x: anchor.minX + markerWidth / 2 - hitSize / 2,
                y: anchor.midY - hitSize / 2,
                width: hitSize,
                height: hitSize
            )
            if hitRect.contains(containerPoint) {
                hitRange = markerRange
                stop.pointee = true
            }
        }
        return hitRange
    }
}

//
//  NativeTextView+Placeholder.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 11.06.26.
//
//  Embedder-supplied ghost text shown while the document is empty. Lives inside
//  the text view, so it sits below the scroll-away header band, tracks its
//  animation, and scrolls with the content.
//

import AppKit

/// Transparent, click-through label drawing the placeholder at the text
/// container origin. A plain NSView — overriding `draw(_:)` here is safe
/// (unlike on the TextKit-2 backed `NativeTextView` itself).
final class PlaceholderLabelView: NSView {
    weak var textView: NativeTextView?

    var attributedText: NSAttributedString? {
        didSet { needsDisplay = true }
    }

    /// Top-left origin to match the flipped text view's first-line position.
    override var isFlipped: Bool { true }

    /// Clicks fall through to the text view (focus + caret placement).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        if let textView,
           let metrics = textView.virtualListPlaceholderMetrics {
            textView.configuration.theme.mutedText.setFill()
            NSBezierPath(
                ovalIn: CGRect(
                    x: metrics.bulletCenter.x - metrics.dotDiameter / 2,
                    y: metrics.bulletCenter.y - metrics.dotDiameter / 2,
                    width: metrics.dotDiameter,
                    height: metrics.dotDiameter
                )
            ).fill()
            return
        }
        attributedText?.draw(
            with: bounds,
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

struct VirtualListPlaceholderMetrics {
    let bulletCenter: CGPoint
    let dotDiameter: CGFloat
    let contentX: CGFloat
}

extension NativeTextView {
    var virtualListPlaceholderMetrics: VirtualListPlaceholderMetrics? {
        guard (textStorage?.length ?? 0) == 0,
              let prefix = emptyDocumentPrefix,
              ["- ", "* ", "+ "].contains(prefix) else {
            return nil
        }

        let font = baseFont
        let marker = String(prefix.prefix(1))
        let markerWidth = (marker as NSString).size(withAttributes: [.font: font]).width
        let prefixWidth = (prefix as NSString).size(withAttributes: [.font: font]).width
        let baselineY = BulletMarkerGeometry.listBaselineY(for: font)
        let textPadding = textContainer?.lineFragmentPadding ?? 0
        let markerX = textPadding + configuration.lists.firstLevelIndent

        return VirtualListPlaceholderMetrics(
            bulletCenter: CGPoint(
                x: markerX + markerWidth / 2,
                y: BulletMarkerGeometry.centerY(
                    forBaseline: baselineY,
                    font: font
                )
            ),
            dotDiameter: BulletMarkerGeometry.dotDiameter(for: font),
            contentX: markerX + prefixWidth + configuration.lists.markerContentGap
        )
    }

    /// Install, refresh, or remove the placeholder. Cheap when nothing changed —
    /// called from every `updateNSView`.
    func setPlaceholder(_ attributed: NSAttributedString?) {
        if attributed != nil || virtualListPlaceholderMetrics != nil {
            let view: PlaceholderLabelView
            if let existing = placeholderView {
                view = existing
            } else {
                view = PlaceholderLabelView()
                view.autoresizingMask = [.width, .height]
                addSubview(view)
                placeholderView = view
            }
            view.textView = self
            if let attributed {
                if view.attributedText?.isEqual(to: attributed) != true {
                    view.attributedText = attributed
                }
            } else if view.attributedText != nil {
                view.attributedText = nil
            }
            view.needsDisplay = true
            let target = placeholderFrame()
            if !view.frame.isApproximatelyEqual(to: target) {
                view.frame = target
            }
        } else if let placeholderView {
            placeholderView.removeFromSuperview()
            self.placeholderView = nil
        }
        refreshPlaceholderVisibility()
        // An empty doc's text view sits at its one-line content height, which
        // clips the placeholder subview. Stretch it to the viewport (its intended
        // height): the first layout can run before the scroll view is sized and
        // `restack` never re-measures height, so otherwise the quote stays clipped
        // after the editor is rebuilt (e.g. graph view and back).
        if let placeholderView, !placeholderView.isHidden {
            applyManagedFrameSize(width: frame.width)
        }
        DispatchQueue.main.async { [weak self] in
            self?.applyVirtualListCaretPolicy()
        }
    }

    /// Visible only while the document is truly empty: the first typed character
    /// hides it, deleting everything brings it back.
    func refreshPlaceholderVisibility() {
        guard let placeholderView else { return }
        let shouldHide = (textStorage?.length ?? 0) > 0
        if placeholderView.isHidden != shouldHide {
            placeholderView.isHidden = shouldHide
        }
    }

    /// The text container's content area: where TextKit places the first line.
    private func placeholderFrame() -> NSRect {
        NSRect(
            x: textContainerInset.width,
            y: textContainerInset.height,
            width: max(bounds.width - textContainerInset.width * 2, 0),
            height: max(bounds.height - textContainerInset.height, 0)
        )
    }
}

private extension NSRect {
    func isApproximatelyEqual(to other: NSRect) -> Bool {
        abs(origin.x - other.origin.x) < 0.5
            && abs(origin.y - other.origin.y) < 0.5
            && abs(size.width - other.size.width) < 0.5
            && abs(size.height - other.size.height) < 0.5
    }
}

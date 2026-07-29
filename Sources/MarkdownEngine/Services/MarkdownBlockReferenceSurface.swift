import AppKit

/// A host-owned native view used to present one resolved block-reference token.
///
/// MarkdownEngine keeps the token in text storage and only reserves its line's
/// geometry. The caller owns the view's rendering and interactions.
@MainActor
public struct MarkdownBlockReferenceSurface {
    public let view: NSView
    public let height: CGFloat

    public init(view: NSView, height: CGFloat) {
        self.view = view
        self.height = max(1, height)
    }
}

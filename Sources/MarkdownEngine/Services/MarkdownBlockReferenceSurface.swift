import AppKit

/// Visual selection states for an atomic, host-rendered block reference.
///
/// The canonical Markdown token remains in text storage, but an interactive
/// surface presents the three attachment-style positions users can navigate:
/// immediately before the node, the whole selected node, and immediately after.
public enum MarkdownBlockReferenceSelectionState: Hashable, Sendable {
    case none
    case caretBefore
    case selected
    case caretAfter
}

/// Host-view gestures and key commands that the editor resolves against the
/// canonical block-reference token.
public enum MarkdownBlockReferenceSurfaceInteraction: Hashable, Sendable {
    case select
    case placeCaretBefore
    case placeCaretAfter
    case indent
    case outdent
}

/// Optional interaction contract for a host-owned block-reference view.
///
/// Conforming views stay presentation-only: they report user intent to the
/// editor and receive selection state back. The editor remains the sole owner
/// of text selection and indentation edits.
@MainActor
public protocol MarkdownBlockReferenceInteractiveView: AnyObject {
    func setBlockReferenceInteractionHandler(
        _ handler: ((MarkdownBlockReferenceSurfaceInteraction) -> Void)?
    )
    func setBlockReferenceSelectionState(
        _ state: MarkdownBlockReferenceSelectionState
    )
    func performBlockReferenceDelete()
}

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

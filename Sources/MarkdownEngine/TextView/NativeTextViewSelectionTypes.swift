//
//  NativeTextViewSelectionTypes.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 16.03.26.
//
//  Public selection / replacement value types exposed by NativeTextViewWrapper.
//

import AppKit

/// Geometry and target for the wiki link currently under the pointer.
///
/// The anchor rectangle is expressed in ``positioningView`` coordinates so
/// an embedder can present native AppKit UI without translating out of the
/// editor's nested scroll views.
public struct WikiLinkHoverState {
    /// Resolved opaque identifier, or the display name when no resolver exists.
    public let target: String
    /// The visible linked-text bounds in ``positioningView`` coordinates.
    public let anchorRect: CGRect
    /// View against which ``anchorRect`` is measured.
    public let positioningView: NSView

    public init(target: String, anchorRect: CGRect, positioningView: NSView) {
        self.target = target
        self.anchorRect = anchorRect
        self.positioningView = positioningView
    }
}

/// A range of text occupied by a wiki-link `[[Name]]`, in both the display
/// and (where known) the storage coordinate systems.
public struct WikiLinkSelection: Sendable {
    /// Range of the link in the document the user is editing (display form).
    public let displayRange: NSRange
    /// Equivalent range in the underlying storage form `[[Name|<id>]]`,
    /// or `nil` when the storage range is unknown / the link is new.
    public let storageRange: NSRange?
    /// Plain text the user will see inside the brackets — used by embedders
    /// to seed a rename popover or autocomplete.
    public let placeholder: String

    public init(displayRange: NSRange, storageRange: NSRange?, placeholder: String) {
        self.displayRange = displayRange
        self.storageRange = storageRange
        self.placeholder = placeholder
    }
}

/// Which kind of inline token the caret is currently inside.
public enum InlineSelectionKind: Sendable {
    /// A `[[Name]]` wiki-link.
    case wikiLink
    /// A `![[Name]]` embedded-image reference.
    case imageEmbed
}

/// Snapshot of the inline token the caret is inside, delivered through
/// ``NativeTextViewWrapper/onInlineSelectionChange``.
public struct InlineSelectionState: Sendable {
    /// Whether the active token is a wiki-link or an image embed.
    public let kind: InlineSelectionKind
    /// Range and seed text of the active inline token.
    public let selection: WikiLinkSelection

    public init(kind: InlineSelectionKind, selection: WikiLinkSelection) {
        self.kind = kind
        self.selection = selection
    }
}

/// A completed wiki-link typed directly in the editor.
///
/// This is intentionally separate from ``InlineSelectionState``: completing a
/// link moves the caret outside its editable content, so autocomplete is no
/// longer active, but embedders may still want to create or resolve its target.
public struct WikiLinkCompletion: Sendable {
    /// The completed link in display coordinates.
    public let selection: WikiLinkSelection

    public init(selection: WikiLinkSelection) {
        self.selection = selection
    }
}

/// A keyboard command forwarded to an open inline preview (the `[[…]]` autocomplete)
/// via ``NativeTextViewWrapper/onInlinePreviewKey``. The embedder returns `true` to
/// consume the key (it drove its list), or `false` to let the editor handle it normally.
public enum InlinePreviewKey: Sendable {
    case moveUp, moveDown, confirm, confirmAndOpen, cancel
}

/// Request to replace an inline token's source with a new storage fragment.
///
/// Embedders push one of these into
/// ``NativeTextViewWrapper/pendingInlineReplacement`` to commit the result of
/// a rename / autocomplete UI. The engine applies the replacement, restores
/// the caret past it, and clears the binding.
public struct InlineReplacementRequest: Sendable {
    /// Stable identifier so the engine can detect already-applied requests
    /// across SwiftUI re-renders.
    public let id: UUID
    /// Document the replacement targets. Ignored if it doesn't match the
    /// editor's current `documentId` (prevents cross-document writes).
    public let documentId: String
    /// Inline-token range being replaced.
    public let selection: WikiLinkSelection
    /// New storage-form text, e.g. `"[[New Name|<id>]]"` or
    /// `"![[image-name]]"`.
    public let storageFragment: String
    /// `true` when the fragment is a `![[…]]` image embed and the engine
    /// should treat it as a standalone block.
    public let isImageEmbedMode: Bool

    public init(
        id: UUID = UUID(),
        documentId: String,
        selection: WikiLinkSelection,
        storageFragment: String,
        isImageEmbedMode: Bool
    ) {
        self.id = id
        self.documentId = documentId
        self.selection = selection
        self.storageFragment = storageFragment
        self.isImageEmbedMode = isImageEmbedMode
    }
}

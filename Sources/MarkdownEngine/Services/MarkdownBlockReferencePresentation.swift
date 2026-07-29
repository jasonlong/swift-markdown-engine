import Foundation

/// Immutable, host-supplied display data for a block reference.
///
/// The engine deliberately does not resolve, render, or persist this value.
/// A later host-view renderer consumes it while the canonical Markdown token
/// remains the document source of truth.
public struct MarkdownBlockReferencePresentation: Hashable, Sendable {
    public enum State: String, Hashable, Sendable {
        case resolved
        case broken
        case ambiguous
        case duplicate
        case cyclic
    }

    public let state: State
    public let sourceLabel: String
    public let markdown: String
    public let isTaskComplete: Bool?

    public init(
        state: State,
        sourceLabel: String,
        markdown: String,
        isTaskComplete: Bool? = nil
    ) {
        self.state = state
        self.sourceLabel = sourceLabel
        self.markdown = markdown
        self.isTaskComplete = isTaskComplete
    }
}

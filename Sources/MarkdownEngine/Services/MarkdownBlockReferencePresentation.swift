import Foundation

/// Host-supplied, immutable content for a rendered block reference. The
/// engine never resolves it or writes it back; it merely presents this value
/// over the canonical token that remains in text storage.
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

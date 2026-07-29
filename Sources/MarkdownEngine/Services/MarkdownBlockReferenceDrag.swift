import Foundation

/// A source range that a host can turn into a portable block-reference drag.
/// The engine intentionally does not assign identities or decide what a block
/// means; it only recognizes a list-row drag affordance and starts AppKit's
/// drag session once its host has prepared the pasteboard representation.
public struct MarkdownBlockReferenceDragSelection: Hashable, Sendable {
    public let location: Int
    public let length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }
}

/// Host-owned pasteboard data used for an in-editor block drag. `plainText`
/// must be safe to paste independently; the engine never interprets either
/// representation.
public struct MarkdownBlockReferenceDragPayload: Sendable {
    public let privateType: String
    public let privateData: Data
    public let plainText: String

    public init(privateType: String, privateData: Data, plainText: String) {
        self.privateType = privateType
        self.privateData = privateData
        self.plainText = plainText
    }
}

public enum MarkdownBlockReferenceDragSyntax {
    /// Returns the full source line for a draggable unordered or ordered list
    /// item at a UTF-16 cursor position. Ordinary prose deliberately returns
    /// `nil`, preserving normal text selection behavior.
    public static func sourceLineSelection(in source: String, atUTF16 location: Int) -> MarkdownBlockReferenceDragSelection? {
        let text = source as NSString
        guard location >= 0, location < text.length else { return nil }
        let line = text.lineRange(for: NSRange(location: location, length: 0))
        let lineText = text.substring(with: line)
        guard lineText.range(of: #"^[ \t]*(?:[-*+] |\d+[.)] )"#, options: .regularExpression) != nil else {
            return nil
        }
        return MarkdownBlockReferenceDragSelection(location: line.location, length: line.length)
    }
}

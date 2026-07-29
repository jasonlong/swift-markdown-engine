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

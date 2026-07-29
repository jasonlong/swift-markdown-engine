import Foundation

/// Generic source ranges for a full-line Markdown block reference. The engine
/// deliberately does not resolve or mutate these tokens; hosts supply policy.
public struct MarkdownBlockReferenceToken: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable { case link, transclusion }

    public let kind: Kind
    public let noteTarget: String
    public let blockID: String
    public let range: NSRange

    public init(kind: Kind, noteTarget: String, blockID: String, range: NSRange) {
        self.kind = kind
        self.noteTarget = noteTarget
        self.blockID = blockID
        self.range = range
    }
}

/// Foundation-only syntax recognition shared by future presentation, context
/// menu, pasteboard, and navigation seams. Unknown or malformed input remains
/// ordinary editor text.
public enum MarkdownBlockReferenceSyntax {
    public static func tokens(in source: String) -> [MarkdownBlockReferenceToken] {
        let expression = try! NSRegularExpression(
            pattern: #"(?m)^\s*(!?)\[\[([^#\]|\r\n]+)#\^([0-9abcdefghjkmnpqrstvwxyz]{26})\]\]\s*$"#
        )
        let text = source as NSString
        return expression.matches(in: source, range: NSRange(location: 0, length: text.length)).compactMap { match in
            let prefix = text.substring(with: match.range(at: 1))
            let target = text.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
            let id = text.substring(with: match.range(at: 3))
            guard !target.isEmpty else { return nil }
            return MarkdownBlockReferenceToken(
                kind: prefix.isEmpty ? .link : .transclusion,
                noteTarget: target,
                blockID: id,
                range: match.range
            )
        }
    }
}

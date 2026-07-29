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
    /// The canonical end-of-line form used by Markdown-backed applications.
    /// The ranges include the leading space so a normal copy can omit the
    /// identity marker without leaving trailing whitespace behind.
    public static func protectedIDRanges(in source: String) -> [NSRange] {
        let expression = try! NSRegularExpression(
            pattern: #"(?m)[ \t]\^[0-9abcdefghjkmnpqrstvwxyz]{26}(?=\r?$)"#
        )
        let text = source as NSString
        return expression.matches(
            in: source,
            range: NSRange(location: 0, length: text.length)
        ).map(\.range)
    }

    /// Returns true if an edit would mutate a protected block identity. A
    /// caret placed immediately before or after the suffix remains editable;
    /// only an insertion/deletion *inside* the suffix is refused.
    public static func editIntersectsProtectedID(
        _ edit: NSRange,
        in source: String
    ) -> Bool {
        if edit.length == 0 {
            guard let idRange = protectedIDRange(near: edit.location, in: source) else {
                return false
            }
            return edit.location > idRange.location
                && edit.location < NSMaxRange(idRange)
        }
        return protectedIDRanges(in: source).contains { idRange in
            NSIntersectionRange(edit, idRange).length > 0
        }
    }

    /// A hidden end-of-line ID occupies the visual end of its source block.
    /// TextKit can consequently report an insertion at the suffix's far edge
    /// when the user clicks or types at the visible content end. Ordinary
    /// single-line input belongs immediately before the suffix instead.
    public static func visibleInsertionRange(
        for edit: NSRange,
        replacement: String?,
        in source: String
    ) -> NSRange? {
        guard edit.length == 0,
              let replacement,
              !replacement.isEmpty,
              !replacement.contains("\n"),
              !replacement.contains("\r")
        else { return nil }
        guard let idRange = protectedIDRange(near: edit.location, in: source),
              NSMaxRange(idRange) == edit.location
        else { return nil }
        return NSRange(location: idRange.location, length: 0)
    }

    static func protectedIDRange(near location: Int, in source: String) -> NSRange? {
        let text = source as NSString
        guard location >= 0, location <= text.length else { return nil }
        let probe = min(max(location - 1, 0), text.length)
        let lineRange = text.lineRange(for: NSRange(location: probe, length: 0))
        let expression = try! NSRegularExpression(
            pattern: #"(?m)[ \t]\^[0-9abcdefghjkmnpqrstvwxyz]{26}(?=\r?$)"#
        )
        return expression.firstMatch(
            in: source,
            range: lineRange
        )?.range
    }

    /// Finds a source line carrying an ID so a host can reveal it after
    /// resolving a deep link. The returned range is intentionally the visible
    /// source line, not the invisible suffix, which makes the highlight useful
    /// even when marker styling is active.
    public static func lineRange(forBlockID blockID: String, in source: String) -> NSRange? {
        guard MarkdownBlockIDShape.isValid(blockID) else { return nil }
        let escapedID = NSRegularExpression.escapedPattern(for: blockID)
        let expression = try! NSRegularExpression(pattern: "(?m)^.*\\^\(escapedID)\\s*$")
        let text = source as NSString
        return expression.firstMatch(
            in: source,
            range: NSRange(location: 0, length: text.length)
        )?.range
    }

    /// Finds the complete reference line for a particular source address. This
    /// lets a host reveal the occurrence the user selected from a source
    /// block's reference list without teaching the engine about graph paths.
    public static func lineRange(
        forReferenceTo noteTarget: String,
        blockID: String,
        in source: String
    ) -> NSRange? {
        guard MarkdownBlockIDShape.isValid(blockID) else { return nil }
        return tokens(in: source).first(where: {
            $0.noteTarget == noteTarget && $0.blockID == blockID
        })?.range
    }

    public static func editIntersectsTransclusion(_ edit: NSRange, in source: String) -> Bool {
        tokens(in: source).contains { token in
            guard token.kind == .transclusion else { return false }
            if edit.length == 0 {
                return edit.location > token.range.location
                    && edit.location < NSMaxRange(token.range)
            }
            return NSIntersectionRange(edit, token.range).length > 0
        }
    }

    public static func tokens(in source: String) -> [MarkdownBlockReferenceToken] {
        let expression = try! NSRegularExpression(
            pattern: #"(?m)^[ \t]*(!?)\[\[([^#\]|\r\n]+)#\^([0-9abcdefghjkmnpqrstvwxyz]{26})\]\][ \t]*\r?$"#
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

private enum MarkdownBlockIDShape {
    static func isValid(_ value: String) -> Bool {
        value.utf8.count == 26
            && value.allSatisfy { "0123456789abcdefghjkmnpqrstvwxyz".contains($0) }
    }
}

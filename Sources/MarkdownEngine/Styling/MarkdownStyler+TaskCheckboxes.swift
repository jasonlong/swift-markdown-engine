//
//  MarkdownStyler+TaskCheckboxes.swift
//  MarkdownEngine
//
//  Protected-prefix helpers for GitHub-style `- [ ] / - [x]` task syntax.
//  Checkbox styling lives in the AST styler (`MarkdownASTStyler`).
//

import AppKit
import Foundation

extension MarkdownStyler {

    /// Task-list line: indent, marker (`-`/`*`/`+`/`•`/`N.` matching the AST), spacer, `[ ]`/`[x]` box.
    static let taskListRegex: NSRegularExpression = try! NSRegularExpression(
        pattern: #"^([ \t]*)([-•*+]|\d+\.)([ \t]+)(\[[ xX]\])(?=[ \t])"#,
        options: [.anchorsMatchLines]
    )

    // MARK: Task Syntax Membership

    /// Full `<marker><spacer>[ ]` range if `location` is inside (or at the trailing edge of) it, else nil.
    static func taskSyntaxRange(at location: Int, in text: String) -> NSRange? {
        guard let (lineRange, match) = taskMatch(at: location, in: text) else { return nil }
        let markerLineRange = match.range(at: 2)
        let checkboxLineRange = match.range(at: 4)
        guard markerLineRange.location != NSNotFound,
              checkboxLineRange.location != NSNotFound else { return nil }
        let syntaxStart = lineRange.location + markerLineRange.location
        let syntaxEnd = lineRange.location + NSMaxRange(checkboxLineRange)
        let syntaxRange = NSRange(location: syntaxStart, length: syntaxEnd - syntaxStart)
        if NSLocationInRange(location, syntaxRange) || location == syntaxEnd {
            return syntaxRange
        }
        return nil
    }

    /// Prefix from the physical line start through the whitespace after `[ ]`.
    /// Locations in this range are presentation-only and cannot host a caret.
    static func taskProtectedRange(at location: Int, in text: String) -> NSRange? {
        let nsText = text as NSString
        guard let (lineRange, match) = taskMatch(at: location, in: text) else { return nil }
        let checkboxLineRange = match.range(at: 4)
        guard checkboxLineRange.location != NSNotFound else { return nil }
        var contentStart = lineRange.location + NSMaxRange(checkboxLineRange)
        let lineEnd = NSMaxRange(lineRange)
        while contentStart < lineEnd {
            let character = nsText.character(at: contentStart)
            guard character == 0x20 || character == 0x09 else { break }
            contentStart += 1
        }
        let protectedRange = NSRange(
            location: lineRange.location,
            length: contentStart - lineRange.location
        )
        return NSLocationInRange(location, protectedRange) ? protectedRange : nil
    }

    private static func taskMatch(
        at location: Int,
        in text: String
    ) -> (lineRange: NSRange, match: NSTextCheckingResult)? {
        let nsText = text as NSString
        let safeLocation = max(0, min(location, nsText.length))
        let lineRange = nsText.lineRange(for: NSRange(location: safeLocation, length: 0))
        let line = nsText.substring(with: lineRange)
        guard let match = taskListRegex.firstMatch(
            in: line,
            options: [],
            range: NSRange(location: 0, length: line.utf16.count)
        ) else { return nil }
        return (lineRange, match)
    }
}

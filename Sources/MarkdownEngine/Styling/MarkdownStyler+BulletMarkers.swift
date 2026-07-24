//
//  MarkdownStyler+BulletMarkers.swift
//  MarkdownEngine
//
//  Protected-prefix helpers for `-`/`*`/`+` bullet syntax. Bullet rendering
//  (the vector overlay) lives in the AST styler (`MarkdownASTStyler`).
//

import Foundation

extension MarkdownStyler {

    /// Indented bullet marker at line start (trailing space excludes `---`/`*bold*`), not a checkbox.
    static let bulletListRegex: NSRegularExpression = try! NSRegularExpression(
        pattern: #"^([ \t]*)([-*+])([ \t]+)(?!\[[ xX]\])"#,
        options: [.anchorsMatchLines]
    )

    /// Prefix from the physical line start through the marker's trailing whitespace.
    static func bulletProtectedRange(at location: Int, in text: String) -> NSRange? {
        let nsText = text as NSString
        let safeLocation = max(0, min(location, nsText.length))
        let lineRange = nsText.lineRange(for: NSRange(location: safeLocation, length: 0))
        let line = nsText.substring(with: lineRange)
        guard let match = bulletListRegex.firstMatch(
            in: line,
            options: [],
            range: NSRange(location: 0, length: (line as NSString).length)
        ) else { return nil }
        let spacingRange = match.range(at: 3)
        guard spacingRange.location != NSNotFound else { return nil }
        let contentStart = lineRange.location + NSMaxRange(spacingRange)
        let protectedRange = NSRange(
            location: lineRange.location,
            length: contentStart - lineRange.location
        )
        return NSLocationInRange(location, protectedRange) ? protectedRange : nil
    }
}

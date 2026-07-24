//
//  MarkdownASTStylerTests.swift
//  MarkdownEngineTests
//
//  Phase 2.5b — the AST styler composes nested/combined inline styles instead
//  of overwriting them (the flat 18-pass styler's flaw).
//

import AppKit
import Foundation
import Testing
@testable import MarkdownEngine

@Suite("Phase 2.5b — AST styler font composition")
struct MarkdownASTStylerTests {

    private let base: CGFloat = 14
    private var fontName: String { NSFont.systemFont(ofSize: 14).fontName }

    /// Effective font at `pos`: the last styled range covering it that sets `.font`.
    private func font(in attrs: [StyledRange], at pos: Int) -> NSFont? {
        var result: NSFont?
        for (range, a) in attrs where NSLocationInRange(pos, range) {
            if let f = a[.font] as? NSFont { result = f }
        }
        return result
    }

    /// Per-keystroke perf: scoping a restyle to the edited paragraph must produce
    /// the EXACT same attributes within that paragraph as a full-document style.
    /// This is the safety net for the `scopedRanges` fast path — it can't diverge
    /// from the full rebuild (no glitch).
    @MainActor
    @Test("scoped styling == full styling, clipped to the edited paragraph")
    func scopedMatchesFullForEditedParagraph() {
        _ = NSApplication.shared
        let text = "plain one\n\n**bold** in two `code`\n\n- item *x*\n\nhttps://example.com"
        let ns = text as NSString
        let para = ns.paragraphRange(for: NSRange(location: 13, length: 0))   // the `**bold**…` line
        func keys(_ scoped: [NSRange]?) -> String {
            let r = MarkdownASTStyler.styleAttributes(
                text: text, fontName: fontName, fontSize: base, scopedRanges: scoped
            ).filter { NSIntersectionRange($0.range, para).length > 0 }
            return styleKeySnapshot(r)
        }
        #expect(keys([para]) == keys(nil))
    }

    @Test("bold inside a heading stays heading-size and consistent (fixes # **n*o*des**)")
    func headingBoldComposesToHeadingSize() {
        let attrs = MarkdownASTStyler.styleAttributes(text: "# **n*o*des**", fontName: fontName, fontSize: base)
        // "# **n*o*des**": n=4, o=6, d=8
        let n = font(in: attrs, at: 4)
        let o = font(in: attrs, at: 6)
        let d = font(in: attrs, at: 8)

        // The fix: every emphasized char is the SAME (heading) size — not "o" big, "n/des" small.
        #expect(n?.pointSize == o?.pointSize)
        #expect(n?.pointSize == d?.pointSize)
        #expect((n?.pointSize ?? 0) > base)   // heading-size, not base

        // Correct composed traits.
        #expect(n?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        #expect(d?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        #expect(o?.fontDescriptor.symbolicTraits.contains([.bold, .italic]) == true)
    }

    @Test("heading weight is configurable")
    func configurableHeadingWeight() {
        var configuration = MarkdownEditorConfiguration.default
        configuration.headings.fontWeight = .semibold

        let attrs = MarkdownASTStyler.styleAttributes(
            text: "# Heading",
            fontName: fontName,
            fontSize: base,
            configuration: configuration
        )
        let heading = font(in: attrs, at: 2)
        let traits = heading?.fontDescriptor.object(forKey: .traits)
            as? [NSFontDescriptor.TraitKey: Any]
        let weight = traits?[.weight] as? NSNumber

        #expect(abs((weight?.doubleValue ?? 0) - Double(NSFont.Weight.semibold.rawValue)) < 0.001)
        #expect(heading?.pointSize == base * configuration.headings.fontMultiplier(for: 1))
    }

    @Test("strong-emphasis weight is configurable")
    func configurableStrongWeight() {
        var configuration = MarkdownEditorConfiguration.default
        configuration.strong.fontWeight = .semibold

        let attrs = MarkdownASTStyler.styleAttributes(
            text: "**Strong**",
            fontName: fontName,
            fontSize: base,
            configuration: configuration
        )
        let strong = font(in: attrs, at: 2)
        let traits = strong?.fontDescriptor.object(forKey: .traits)
            as? [NSFontDescriptor.TraitKey: Any]
        let weight = traits?[.weight] as? NSNumber

        #expect(abs((weight?.doubleValue ?? 0) - Double(NSFont.Weight.semibold.rawValue)) < 0.001)

        let nestedAttrs = MarkdownASTStyler.styleAttributes(
            text: "*outer **inner** outer*",
            fontName: fontName,
            fontSize: base,
            configuration: configuration
        )
        let nestedStrong = font(in: nestedAttrs, at: 9)
        #expect(nestedStrong?.fontDescriptor.symbolicTraits.contains([.bold, .italic]) == true)
    }

    @Test("blank line height is configurable")
    func configurableBlankLineHeight() {
        var configuration = MarkdownEditorConfiguration.default
        configuration.paragraph.blankLineHeightScale = 0.5
        let attrs = MarkdownASTStyler.styleAttributes(
            text: "first\n\nsecond",
            fontName: fontName,
            fontSize: base,
            configuration: configuration
        )
        let blankLineStyle = attrs.reversed().first { entry in
            NSLocationInRange(6, entry.range) && entry.attributes[.paragraphStyle] != nil
        }?.attributes[.paragraphStyle] as? NSParagraphStyle
        let bodyFont = NSFont(name: fontName, size: base) ?? .systemFont(ofSize: base)
        let bodyLineHeight = ceil(bodyFont.ascender - bodyFont.descender + bodyFont.leading)
            + configuration.paragraph.lineHeightExtraSpacing

        #expect(blankLineStyle?.minimumLineHeight == bodyLineHeight * 0.5)
        #expect(blankLineStyle?.paragraphSpacing == 0)
    }

    @Test("nested emphasis in a paragraph composes bold+italic")
    func paragraphNestedEmphasis() {
        let attrs = MarkdownASTStyler.styleAttributes(text: "**a *b* c**", fontName: fontName, fontSize: base)
        // "**a *b* c**": a=2, b=5, c=8
        let a = font(in: attrs, at: 2)
        let b = font(in: attrs, at: 5)
        #expect(a?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        #expect(a?.fontDescriptor.symbolicTraits.contains(.italic) == false)
        #expect(b?.fontDescriptor.symbolicTraits.contains([.bold, .italic]) == true)
    }

    /// Code is not prose: fenced blocks and inline `code` spans must carry
    /// `.spellingState: 0` so the system spell-checker leaves them alone,
    /// matching the existing convention that links / wiki-links / LaTeX / tables
    /// already follow.
    @Test("code blocks and inline code receive .spellingState: 0; prose does not")
    func codeRegionsSuppressSpellCheck() {
        let text = "prose word\n\n```\nfencedcd notaword\n```\n\nplain `inlnecode` tail"
        let attrs = MarkdownASTStyler.styleAttributes(text: text, fontName: fontName, fontSize: base)
        let ns = text as NSString
        let fencedContent = ns.range(of: "fencedcd notaword")
        let inlineSpan = ns.range(of: "`inlnecode`")
        let prose = ns.range(of: "prose word")

        // Pull every `.spellingState` value from styled ranges that intersect `r`.
        func spellingStates(intersecting r: NSRange) -> [Int] {
            attrs.compactMap { entry -> Int? in
                guard NSIntersectionRange(entry.range, r).length > 0 else { return nil }
                return entry.attributes[.spellingState] as? Int
            }
        }

        #expect(spellingStates(intersecting: fencedContent).contains(0))
        #expect(spellingStates(intersecting: inlineSpan).contains(0))
        #expect(spellingStates(intersecting: prose).isEmpty)
    }

    /// Effective color at `pos`: the last styled range covering it that sets `.foregroundColor`.
    private func color(in attrs: [StyledRange], at pos: Int) -> NSColor? {
        var result: NSColor?
        for (range, a) in attrs where NSLocationInRange(pos, range) {
            if let c = a[.foregroundColor] as? NSColor { result = c }
        }
        return result
    }

    /// Whether the last `.font` attribute covering `pos` is the hidden marker font.
    private func isHiddenMarkerFont(in attrs: [StyledRange], at pos: Int, configuration: MarkdownEditorConfiguration = .default) -> Bool {
        let hiddenSize = configuration.markers.hiddenMarkerFontSize
        let hiddenFont = NSFont(name: fontName, size: hiddenSize) ?? .systemFont(ofSize: hiddenSize)
        var result: NSFont?
        for (range, a) in attrs where NSLocationInRange(pos, range) {
            if let f = a[.font] as? NSFont { result = f }
        }
        return result?.pointSize == hiddenFont.pointSize
    }

    @Test("highlight == markers use mutedText while the caret is inside")
    func highlightMarkersAreMutedWhenActive() {
        let text = "==text=="
        let attrs = MarkdownASTStyler.styleAttributes(
            text: text, fontName: fontName, fontSize: base, caretLocation: 4,
            configuration: .init(extensions: [HighlightExtension(), StrikethroughExtension()])
        )
        #expect(color(in: attrs, at: 0) == MarkdownEditorTheme.default.mutedText)
        #expect(color(in: attrs, at: 1) == MarkdownEditorTheme.default.mutedText)
        #expect(color(in: attrs, at: 6) == MarkdownEditorTheme.default.mutedText)
        #expect(color(in: attrs, at: 7) == MarkdownEditorTheme.default.mutedText)
    }

    @Test("bold ** markers use mutedText while the caret is inside")
    func boldMarkersAreMutedWhenActive() {
        let text = "**bold**"
        let attrs = MarkdownASTStyler.styleAttributes(
            text: text, fontName: fontName, fontSize: base, caretLocation: 4, configuration: .default
        )
        #expect(color(in: attrs, at: 0) == MarkdownEditorTheme.default.mutedText)
        #expect(color(in: attrs, at: 1) == MarkdownEditorTheme.default.mutedText)
        #expect(color(in: attrs, at: 6) == MarkdownEditorTheme.default.mutedText)
        #expect(color(in: attrs, at: 7) == MarkdownEditorTheme.default.mutedText)
    }

    @Test("italic * marker uses mutedText while the caret is inside")
    func italicMarkerIsMutedWhenActive() {
        let text = "*italic*"
        let attrs = MarkdownASTStyler.styleAttributes(
            text: text, fontName: fontName, fontSize: base, caretLocation: 4, configuration: .default
        )
        #expect(color(in: attrs, at: 0) == MarkdownEditorTheme.default.mutedText)
        #expect(color(in: attrs, at: 7) == MarkdownEditorTheme.default.mutedText)
    }

    @Test("strikethrough ~~ markers use mutedText while the caret is inside")
    func strikethroughMarkersAreMutedWhenActive() {
        let text = "~~strike~~"
        let attrs = MarkdownASTStyler.styleAttributes(
            text: text, fontName: fontName, fontSize: base, caretLocation: 5,
            configuration: .init(extensions: [StrikethroughExtension()])
        )
        #expect(color(in: attrs, at: 0) == MarkdownEditorTheme.default.mutedText)
        #expect(color(in: attrs, at: 1) == MarkdownEditorTheme.default.mutedText)
        #expect(color(in: attrs, at: 8) == MarkdownEditorTheme.default.mutedText)
        #expect(color(in: attrs, at: 9) == MarkdownEditorTheme.default.mutedText)
    }

    @Test("inline markers shrink instead of taking muted color when the caret is outside")
    func inactiveMarkersShrinkInsteadOfColored() {
        let text = "a ==text== b **bold** c ~~strike~~ d *italic* e"
        let attrs = MarkdownASTStyler.styleAttributes(
            text: text, fontName: fontName, fontSize: base, caretLocation: 0,
            configuration: .init(extensions: [HighlightExtension(), StrikethroughExtension()])
        )
        for pos in [2, 3, 8, 9, 13, 14, 19, 20, 24, 25, 32, 33, 37, 44] {
            #expect(isHiddenMarkerFont(in: attrs, at: pos), "marker at \(pos) should be shrunk")
        }
    }
}

/// A hidden task item shares the BULLET list's left geometry (GitHub/Obsidian):
/// the `[ ] ` chars collapse to the hidden-marker font (~zero advance) so task
/// content starts at the same x as bullet content, and the hanging indent
/// measures only `- `. While the caret edits the syntax, the raw chars show at
/// full advance and the indent uses the full `- [ ] ` width.
@Suite("Task checkbox geometry — collapsed [ ] shares bullet indent")
struct TaskCheckboxGeometryStylerTests {

    private let base: CGFloat = 14
    private var fontName: String { NSFont.systemFont(ofSize: 14).fontName }
    private var baseFont: NSFont { NSFont(name: fontName, size: base) ?? .systemFont(ofSize: base) }
    private var hiddenSize: CGFloat { MarkdownEditorConfiguration.default.markers.hiddenMarkerFontSize }
    private var indentPerLevel: CGFloat { MarkdownEditorConfiguration.default.lists.indentPerLevel }

    /// Same measurement call the styler uses for the hanging indent.
    private func width(_ s: String) -> CGFloat {
        (s as NSString).size(withAttributes: [.font: baseFont]).width
    }

    /// Effective font at `pos`: the last styled range covering it that sets `.font`.
    private func font(in attrs: [StyledRange], at pos: Int) -> NSFont? {
        var result: NSFont?
        for (range, a) in attrs where NSLocationInRange(pos, range) {
            if let f = a[.font] as? NSFont { result = f }
        }
        return result
    }

    /// Effective paragraph style at `pos`: the last styled range covering it.
    private func paragraphStyle(in attrs: [StyledRange], at pos: Int) -> NSParagraphStyle? {
        var result: NSParagraphStyle?
        for (range, attributes) in attrs where NSLocationInRange(pos, range) {
            if let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle {
                result = paragraph
            }
        }
        return result
    }

    private func attribute(
        _ key: NSAttributedString.Key,
        in attrs: [StyledRange],
        at pos: Int
    ) -> Any? {
        var result: Any?
        for (range, attributes) in attrs where NSLocationInRange(pos, range) {
            if let value = attributes[key] { result = value }
        }
        return result
    }

    private func headIndent(in attrs: [StyledRange], at pos: Int) -> CGFloat? {
        paragraphStyle(in: attrs, at: pos)?.headIndent
    }

    private func style(
        _ text: String,
        caret: Int = -1,
        configuration: MarkdownEditorConfiguration = .default
    ) -> [StyledRange] {
        MarkdownASTStyler.styleAttributes(
            text: text,
            fontName: fontName,
            fontSize: base,
            caretLocation: caret,
            configuration: configuration
        )
    }

    @Test("hidden task: [ ] collapses to the hidden font and indent equals a bullet's")
    func hiddenTaskSharesBulletIndent() {
        // "- [ ] task": marker 0..1, spacer 1..2, box 2..5, gap 5..6, content 6...
        let attrs = style("- [ ] task")

        // The box chars carry the collapse font (~zero advance, house pattern).
        for pos in 2...4 {
            #expect(font(in: attrs, at: pos)?.pointSize == hiddenSize, "box char at \(pos) should collapse")
        }
        // The space after the box collapses too.
        #expect(font(in: attrs, at: 5)?.pointSize == hiddenSize)
        // Marker + spacer keep full advance (the drawn square's slot): no collapse font.
        #expect(font(in: attrs, at: 0)?.pointSize != hiddenSize)
        #expect(font(in: attrs, at: 1)?.pointSize != hiddenSize)

        // Hanging indent measures only "- " — identical to a bullet item.
        let taskIndent = headIndent(in: attrs, at: 0)
        let expected = indentPerLevel + width("- ")
        #expect(taskIndent != nil)
        #expect(abs((taskIndent ?? -1) - expected) < 0.01)

        let bulletIndent = headIndent(in: style("- task"), at: 0)
        #expect(taskIndent == bulletIndent)

        // [x] hits the identical collapse branch as [ ].
        #expect(headIndent(in: style("- [x] task"), at: 0) == taskIndent)
    }

    @Test("custom list geometry aligns markers and adds visual spacing")
    func customListGeometry() {
        var configuration = MarkdownEditorConfiguration.default
        configuration.lists.firstLevelIndent = 0
        configuration.lists.indentPerLevel = 32
        configuration.lists.markerContentGap = 8
        configuration.taskCheckbox.sizeScale = 1.1
        configuration.taskCheckbox.checkedTextColor = .secondaryLabelColor
        configuration.taskCheckbox.showsListBullet = true

        let bulletAttributes = style("- bullet", configuration: configuration)
        #expect(paragraphStyle(in: bulletAttributes, at: 0)?.firstLineHeadIndent == 0)
        #expect(abs((headIndent(in: bulletAttributes, at: 0) ?? -1) - width("- ") - 8) < 0.01)
        #expect(attribute(.kern, in: bulletAttributes, at: 0) as? CGFloat == 8)

        let nestedAttributes = style("  - nested", configuration: configuration)
        let nestedFirstLineIndent = paragraphStyle(
            in: nestedAttributes,
            at: 0
        )?.firstLineHeadIndent ?? -1
        #expect(abs(nestedFirstLineIndent + width("  ") - 32) < 0.01)

        let taskAttributes = style("- [ ] task", configuration: configuration)
        let taskAdvance = 8 + TaskCheckboxGeometry.size(for: baseFont, scale: 1.1)
            + TaskCheckboxGeometry.gap
        #expect(paragraphStyle(in: taskAttributes, at: 0)?.firstLineHeadIndent == 0)
        #expect(abs((headIndent(in: taskAttributes, at: 0) ?? -1) - width("- ") - taskAdvance) < 0.01)
        #expect(attribute(.kern, in: taskAttributes, at: 0) as? CGFloat == taskAdvance)
        #expect(attribute(.bulletMarker, in: taskAttributes, at: 0) as? Bool == true)

        let checkedAttributes = style("- [x] task", configuration: configuration)
        #expect(
            attribute(.foregroundColor, in: checkedAttributes, at: 6) as? NSColor
                == .secondaryLabelColor
        )
    }

    @Test("bullet marker stays rendered when the caret reaches its source range")
    func bulletSyntaxNeverReveals() {
        let attributes = style("* item", caret: 0)

        #expect(attribute(.bulletMarker, in: attributes, at: 0) as? Bool == true)
        #expect(attribute(.foregroundColor, in: attributes, at: 0) as? NSColor == .clear)
    }

    @Test("task syntax stays collapsed when the caret reaches its source range")
    func taskSyntaxNeverReveals() {
        let attrs = style("- [ ] task", caret: 3)

        for position in 2...5 {
            #expect(font(in: attrs, at: position)?.pointSize == hiddenSize)
        }
        let expected = indentPerLevel + width("- ")
        let taskIndent = headIndent(in: attrs, at: 0)
        #expect(taskIndent != nil)
        #expect(abs((taskIndent ?? -1) - expected) < 0.01)
    }

}

/// Canonical, order-independent string of styled ranges so two style runs can be
/// compared for equality.
private func styleKeySnapshot(_ ranges: [StyledRange]) -> String {
    let lines = ranges
        .map { entry -> (NSRange, [String]) in
            (entry.range, entry.attributes.keys.map(\.rawValue).sorted())
        }
        .sorted { a, b in
            if a.0.location != b.0.location { return a.0.location < b.0.location }
            if a.0.length != b.0.length { return a.0.length < b.0.length }
            return a.1.joined(separator: ",") < b.1.joined(separator: ",")
        }
        .map { "@\(fmt($0.0)) keys=[\($0.1.joined(separator: ","))]" }
    return lines.isEmpty ? "(no styled ranges)" : lines.joined(separator: "\n")
}

private func fmt(_ r: NSRange) -> String {
    r.location == NSNotFound ? "∅" : "\(r.location)+\(r.length)"
}

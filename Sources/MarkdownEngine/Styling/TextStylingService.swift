//
//  TextStylingService.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 18.02.26.
//

// Applies base text styling and refreshes only changed sections so editing
// stays smooth while Markdown formatting updates.
import AppKit
import Foundation

struct TextStylingService {
    static func makeBaseTypingAttributes(
        font: NSFont,
        paragraphStyle: NSParagraphStyle,
        theme: MarkdownEditorTheme = .default
    ) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: theme.bodyText,
            .paragraphStyle: paragraphStyle
        ]
    }

    static func makeBaseFontAndStyle(
        fontName: String,
        fontSize: CGFloat,
        layoutBridge: LayoutBridge? = nil,
        configuration: MarkdownEditorConfiguration = .default
    ) -> (font: NSFont, style: NSMutableParagraphStyle) {
        let baseFont = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let defaultLineHeight = layoutBridgeDefaultLineHeight(for: baseFont, using: layoutBridge)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = ceil(defaultLineHeight) + configuration.paragraph.lineHeightExtraSpacing
        paragraph.lineSpacing = 0
        let baseParagraphSpacing = ceil(defaultLineHeight * configuration.paragraph.spacingFactor)
        paragraph.paragraphSpacing = baseParagraphSpacing
        paragraph.paragraphSpacingBefore = 0
        paragraph.lineBreakMode = .byWordWrapping
        // 24 explicit tab stops at indentPerLevel intervals, then natural wrap.
        let perLevel = configuration.lists.indentPerLevel
        paragraph.tabStops = (1...24).map { NSTextTab(textAlignment: .left, location: CGFloat($0) * perLevel) }
        paragraph.defaultTabInterval = 0
        return (baseFont, paragraph)
    }

    static func restyle(
        textView: NSTextView,
        layoutBridge: LayoutBridge?,
        paragraphCandidates: [NSRange],
        baseFont: NSFont,
        paragraphStyle: NSMutableParagraphStyle,
        caretLocation: Int,
        selection: NSRange? = nil,
        activeTokenIndices: Set<Int>,
        wikiLinkIDProvider: @escaping (NSRange) -> String?,
        precomputedTokens: [MarkdownToken]? = nil,
        classified: MarkdownStyler.ClassifiedStyleTokens? = nil,
        precomputedBlocks: [Block]? = nil,
        configuration: MarkdownEditorConfiguration = .default
    ) {
        let paragraphs = normalize(paragraphCandidates)

        textView.typingAttributes = makeBaseTypingAttributes(
            font: baseFont,
            paragraphStyle: paragraphStyle,
            theme: configuration.theme
        )

        guard !paragraphs.isEmpty else {
            textView.setNeedsDisplay(textView.visibleRect)
            return
        }

        let styleT0 = DispatchTime.now().uptimeNanoseconds
        let styledRanges = MarkdownStyler.styleAttributes(
            text: textView.string,
            fontName: baseFont.fontName,
            fontSize: baseFont.pointSize,
            layoutBridge: layoutBridge,
            caretLocation: caretLocation,
            selection: selection,
            activeTokenIndices: activeTokenIndices,
            wikiLinkIDProvider: wikiLinkIDProvider,
            precomputedTokens: precomputedTokens,
            classified: classified,
            precomputedBlocks: precomputedBlocks,
            scopedRanges: paragraphs,
            configuration: configuration
        )
        let styleMs = Double(DispatchTime.now().uptimeNanoseconds - styleT0) / 1_000_000

        let spellT0 = DispatchTime.now().uptimeNanoseconds
        let spellingDisabledRanges = styledRanges.compactMap { (range, attrs) -> NSRange? in
            attrs[.spellingState] as? Int == 0 ? range : nil
        }

        // Remove existing spelling markers before reapplying disabled ranges.
        for disabledRange in spellingDisabledRanges {
            layoutBridge?.removeTemporaryAttribute(.spellingState, forCharacterRange: disabledRange)
        }

        textView.textStorage?.beginEditing()
        for disabledRange in spellingDisabledRanges {
            textView.textStorage?.addAttribute(.spellingState, value: 0, range: disabledRange)
        }
        let spellMs = Double(DispatchTime.now().uptimeNanoseconds - spellT0) / 1_000_000
        let attrT0 = DispatchTime.now().uptimeNanoseconds
        if let storage = textView.textStorage {
            let baseAttributes: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: configuration.theme.bodyText,
                .paragraphStyle: paragraphStyle
            ]
            for paragraph in paragraphs {
                reconcileParagraphAttributes(
                    in: storage,
                    paragraph: paragraph,
                    baseAttributes: baseAttributes,
                    styledRanges: styledRanges
                )
            }
        }
        textView.textStorage?.endEditing()
        let attrMs = Double(DispatchTime.now().uptimeNanoseconds - attrT0) / 1_000_000
        // No ensureLayout here:
        let evlT0 = DispatchTime.now().uptimeNanoseconds
        textView.setNeedsDisplay(textView.visibleRect)
        (textView as? NativeTextView)?.ensureVisibleLayout()
        let evlMs = Double(DispatchTime.now().uptimeNanoseconds - evlT0) / 1_000_000
        PerfTrace.note { "  restyle split: styleAttrs=\(String(format: "%.2f", styleMs))ms spell=\(String(format: "%.2f", spellMs))ms attrApply(paras=\(paragraphs.count))=\(String(format: "%.2f", attrMs))ms ensureVisLayout=\(String(format: "%.2f", evlMs))ms" }
    }

    /// Reconcile only attribute runs whose rendered styling actually changed.
    ///
    /// Calling `setAttributes` across an entire paragraph on every keystroke
    /// makes TextKit invalidate and briefly redraw the whole line. That is
    /// especially visible beside custom-drawn task controls. Building the
    /// desired paragraph off-screen and applying only differing runs keeps the
    /// checkbox, bullet, and unchanged text continuously rendered.
    private static func reconcileParagraphAttributes(
        in storage: NSTextStorage,
        paragraph: NSRange,
        baseAttributes: [NSAttributedString.Key: Any],
        styledRanges: [StyledRange]
    ) {
        guard paragraph.length > 0 else { return }

        let desired = NSMutableAttributedString(
            string: (storage.string as NSString).substring(with: paragraph),
            attributes: baseAttributes
        )
        let desiredFullRange = NSRange(location: 0, length: paragraph.length)

        for (range, attributes) in styledRanges {
            let clipped = NSIntersectionRange(range, paragraph)
            guard clipped.length > 0 else { continue }
            desired.addAttributes(
                attributes,
                range: NSRange(
                    location: clipped.location - paragraph.location,
                    length: clipped.length
                )
            )
        }

        // Outline state is managed in a separate pass. Preserve its current
        // attributes here so an ordinary text edit does not clear and repaint
        // otherwise-unchanged list markers.
        let outlineKeys: [NSAttributedString.Key] = [
            .outlineDepth,
            .outlineHasChildren,
            .outlineCollapsed,
            .outlineHidden,
        ]
        for key in outlineKeys {
            storage.enumerateAttribute(key, in: paragraph) { value, range, _ in
                guard let value else { return }
                desired.addAttribute(
                    key,
                    value: value,
                    range: NSRange(
                        location: range.location - paragraph.location,
                        length: range.length
                    )
                )
            }
        }

        // Collapsed descendants also carry tiny/clear layout attributes. They
        // cannot be edited directly, so retain those complete runs until the
        // outline pass intentionally expands or rebuilds them.
        storage.enumerateAttribute(.outlineHidden, in: paragraph) { value, range, _ in
            guard value != nil else { return }
            storage.enumerateAttributes(in: range) { attributes, attributeRange, _ in
                desired.addAttributes(
                    attributes,
                    range: NSRange(
                        location: attributeRange.location - paragraph.location,
                        length: attributeRange.length
                    )
                )
            }
        }

        struct AttributeUpdate {
            var range: NSRange
            let attributes: [NSAttributedString.Key: Any]
        }
        var updates: [AttributeUpdate] = []
        var localLocation = 0
        while localLocation < desiredFullRange.length {
            let storageLocation = paragraph.location + localLocation
            var currentRange = NSRange()
            let current = storage.attributes(
                at: storageLocation,
                longestEffectiveRange: &currentRange,
                in: paragraph
            )
            var desiredRange = NSRange()
            let expected = desired.attributes(
                at: localLocation,
                longestEffectiveRange: &desiredRange,
                in: desiredFullRange
            )
            let localCurrentEnd = NSMaxRange(currentRange) - paragraph.location
            let segmentEnd = min(localCurrentEnd, NSMaxRange(desiredRange))
            guard segmentEnd > localLocation else { break }

            if !attributesEqual(current, expected) {
                let updateRange = NSRange(
                    location: storageLocation,
                    length: segmentEnd - localLocation
                )
                if let last = updates.last,
                   NSMaxRange(last.range) == updateRange.location,
                   attributesEqual(last.attributes, expected) {
                    updates[updates.count - 1].range.length += updateRange.length
                } else {
                    updates.append(AttributeUpdate(range: updateRange, attributes: expected))
                }
            }
            localLocation = segmentEnd
        }

        for update in updates {
            storage.setAttributes(update.attributes, range: update.range)
        }
    }

    private static func attributesEqual(
        _ lhs: [NSAttributedString.Key: Any],
        _ rhs: [NSAttributedString.Key: Any]
    ) -> Bool {
        (lhs as NSDictionary).isEqual(to: rhs)
    }

    private static func normalize(_ candidates: [NSRange]) -> [NSRange] {
        // Exact-duplicate drop in one pass (was O(n²) via contains); order and
        // overlapping-but-unequal ranges are preserved exactly as before.
        var seen = Set<Int>()
        seen.reserveCapacity(candidates.count)
        var result: [NSRange] = []
        for candidate in candidates where candidate.location != NSNotFound && candidate.length > 0 {
            let key = candidate.location &* 1_000_003 &+ candidate.length
            if seen.insert(key).inserted { result.append(candidate) }
        }
        return result
    }

    /// Convert an NSRange into an NSTextRange for use with NSTextLayoutManager.
    static func textRange(from range: NSRange, in contentStorage: NSTextContentStorage) -> NSTextRange? {
        let docStart = contentStorage.documentRange.location
        guard let start = contentStorage.location(docStart, offsetBy: range.location),
              let end = contentStorage.location(start, offsetBy: range.length) else {
            return nil
        }
        return NSTextRange(location: start, end: end)
    }
}

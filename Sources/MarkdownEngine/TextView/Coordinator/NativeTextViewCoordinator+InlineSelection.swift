//
//  NativeTextViewCoordinator+InlineSelection.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 16.03.26.
//
//  Inline selection geometry: figure out which inline token (wiki-link
//  `[[…]]` or image-embed `![[…]]`) the caret is currently in, compute its
//  on-screen rect for the host's preview popover, and keep image-embed
//  activation in sync with the active-token-index set.
//

import AppKit

extension NativeTextViewCoordinator {

    /// Recompute the preview anchor for the active inline token (used when scrolling).
    func refreshActiveLinkCaretRect() {
        guard isWikiLinkActive || isImageEmbedActive, let tv = textView else { return }
        guard let rect = inlinePreviewRect(in: tv) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onCaretRectChange?(rect)
        }
    }

    func inlinePreviewRect(in tv: NSTextView) -> CGRect? {
        let nsText = tv.string as NSString
        let parsed = parsedDocument(for: tv.string)
        let selectionLocation = tv.selectedRange().location
        guard let inlineContext = inlineTokenContext(
            at: selectionLocation,
            parsed: parsed,
            codeTokens: parsed.codeTokens,
            text: nsText
        ) else {
            return tv.viewRect(forCharacterRange: tv.selectedRange(), using: layoutBridge)
        }

        let openingMarkerLength = inlineContext.selectionKind == .imageEmbed ? 3 : 2
        let displayRange = selectionDisplayRange(for: inlineContext.token, openingMarkerLength: openingMarkerLength)
        return tv.viewRect(forCharacterRange: displayRange, using: layoutBridge)
            ?? tv.viewRect(forCharacterRange: tv.selectedRange(), using: layoutBridge)
    }

    func selectionDisplayRange(for token: MarkdownToken, openingMarkerLength: Int) -> NSRange {
        let leftRange = token.markerRanges.first
            ?? NSRange(location: token.range.location, length: min(openingMarkerLength, token.range.length))
        guard token.markerRanges.count > 1 else {
            return NSRange(
                location: leftRange.location,
                length: NSMaxRange(token.range) - leftRange.location
            )
        }
        let rightRange = token.markerRanges.last
            ?? NSRange(
                location: max(token.range.location, NSMaxRange(token.range) - min(2, token.range.length)),
                length: min(2, token.range.length)
            )
        return NSRange(location: leftRange.location, length: rightRange.location + rightRange.length - leftRange.location)
    }

    func imageEmbedToken(
        at selectionLocation: Int,
        parsed: ParsedDocument,
        in text: NSString
    ) -> (token: MarkdownToken, index: Int)? {
        for token in parsed.imageEmbedTokens {
            guard token.containsSelectionOrStandaloneParagraph(selectionLocation, in: text) else {
                continue
            }
            let index = parsed.tokens.firstIndex(where: {
                $0.range.location == token.range.location && $0.kind == .imageEmbed
            }) ?? 0
            return (token, index)
        }
        return nil
    }

    func inlineTokenContext(
        at selectionLocation: Int,
        parsed: ParsedDocument,
        codeTokens: [MarkdownToken],
        text: NSString
    ) -> InlineTokenContext? {
        if let (token, _) = imageEmbedToken(at: selectionLocation, parsed: parsed, in: text),
           !MarkdownDetection.isInsideCodeBlock(range: token.range, codeTokens: codeTokens) {
            return .imageEmbed(token: token)
        }

        for token in parsed.wikiLinkTokens {
            // Only match when the caret sits between the inner edges of `[[…]]` —
            let start = token.range.location + 2
            let end = NSMaxRange(token.range) - 2
            guard selectionLocation >= start && selectionLocation <= end else { continue }
            guard !MarkdownDetection.isInsideCodeBlock(range: token.range, codeTokens: codeTokens) else { break }
            return .wikiLink(token: token)
        }

        // A wiki-link draft starts at `[[` and intentionally remains open
        // until the user accepts autocomplete or types `]]`. Its editable
        // range ends at the caret so text after the intended target remains
        // untouched when the completion is applied.
        let lineRange = text.lineRange(for: NSRange(location: selectionLocation, length: 0))
        let lineStart = lineRange.location
        var openingLocation: Int?
        var index = max(lineStart, selectionLocation - 2)
        while index >= lineStart {
            if index + 1 < selectionLocation,
               text.character(at: index) == 0x5B,
               text.character(at: index + 1) == 0x5B {
                openingLocation = index
                break
            }
            index -= 1
        }
        if let openingLocation {
            let range = NSRange(location: openingLocation, length: selectionLocation - openingLocation)
            guard !MarkdownDetection.isInsideCodeBlock(range: range, codeTokens: codeTokens) else {
                return nil
            }
            return .wikiLink(token: MarkdownToken(
                kind: .wikiLink,
                range: range,
                contentRange: NSRange(
                    location: openingLocation + 2,
                    length: selectionLocation - (openingLocation + 2)
                ),
                markerRanges: [NSRange(location: openingLocation, length: 2)]
            ))
        }

        return nil
    }

    // MARK: - Image Embed Activation

    func filterImageEmbedActiveTokens(parsed: ParsedDocument, text: NSString, selectionLocation: Int) {
        let activeImageEmbedIndex = imageEmbedToken(
            at: selectionLocation,
            parsed: parsed,
            in: text
        )?.index

        for (idx, token) in parsed.tokens.enumerated() where token.kind == .imageEmbed {
            if idx != activeImageEmbedIndex {
                activeTokenIndices.remove(idx)
            } else {
                activeTokenIndices.insert(idx)
            }
        }
    }

    func resetImageEmbedState() {
        isImageEmbedActive = false
    }
}

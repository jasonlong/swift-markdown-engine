//
//  NativeTextViewCoordinator+ImageClicks.swift
//  MarkdownEngine
//
//  Keeps Markdown-image hit testing at the coordinator boundary so NativeTextView
//  remains unaware of the parser's token model.
//

import AppKit

extension NativeTextViewCoordinator {
    func renderedMarkdownImage(at characterIndex: Int, in textView: NSTextView) -> NSImage? {
        guard
            characterIndex >= 0,
            let storage = textView.textStorage,
            characterIndex < storage.length
        else {
            return nil
        }

        let isImageToken = parsedDocument(for: textView.string).tokens.contains { token in
            (token.kind == .imageEmbed || token.kind == .imageLink)
                && NSLocationInRange(characterIndex, token.range)
        }
        guard isImageToken else { return nil }
        return storage.attribute(.latexImage, at: characterIndex, effectiveRange: nil) as? NSImage
    }
}

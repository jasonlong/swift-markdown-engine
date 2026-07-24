//
//  NativeTextView+CmdReturn.swift
//  MarkdownEngine
//
//  AppKit does not route Command-Return through doCommandBy(insertNewline:),
//  so command-return behavior is handled as a key equivalent.
//

import AppKit

extension NativeTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers == .command,
              event.keyCode == 36 || event.keyCode == 76 else {
            return super.performKeyEquivalent(with: event)
        }
        if cycleBulletTaskState() { return true }
        if let coordinator = delegate as? NativeTextViewCoordinator,
           coordinator.isWikiLinkActive || coordinator.isImageEmbedActive,
           let handler = coordinator.onInlinePreviewKey,
           handler(.confirmAndOpen) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

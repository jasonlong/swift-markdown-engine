//
//  NativeTextView+CmdReturn.swift
//  MarkdownEngine
//
//  AppKit does not route Command-Return through doCommandBy(insertNewline:),
//  so command-return behavior is handled as a key equivalent.
//

import AppKit

extension NativeTextView {
    override func keyDown(with event: NSEvent) {
        if handleCommandReturn(event) { return }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleCommandReturn(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    private func handleCommandReturn(_ event: NSEvent) -> Bool {
        guard isCommandReturn(event) else { return false }
        if cycleBulletTaskState() { return true }
        if let coordinator = delegate as? NativeTextViewCoordinator,
           coordinator.isWikiLinkActive || coordinator.isImageEmbedActive,
           let handler = coordinator.onInlinePreviewKey,
           handler(.confirmAndOpen) {
            return true
        }
        return false
    }

    private func isCommandReturn(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let ignoredModifiers: NSEvent.ModifierFlags = [.capsLock, .numericPad, .function]
        let shortcutModifiers = modifiers.subtracting(ignoredModifiers)
        return shortcutModifiers == .command
            && (event.keyCode == 36 || event.keyCode == 76)
    }
}

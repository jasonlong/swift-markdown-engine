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
        if handleBlockReferenceTab(event) { return }
        if handleWikiLinkOpeningBracket(event) { return }
        if handleOptionArrow(event) { return }
        if handleCommandReturn(event) { return }
        super.keyDown(with: event)
    }

    /// AppKit can treat a physical Tab at an insertion point as focus traversal
    /// before it calls the text delegate's `doCommandBy(insertTab:)`. A copied
    /// node deliberately exposes caret positions just before and after its
    /// atomic surface, so handle an unmodified Tab here as well. This keeps the
    /// shortcut in the editor instead of letting focus leave the note.
    private func handleBlockReferenceTab(_ event: NSEvent) -> Bool {
        guard !configuration.rawSourceMode, event.keyCode == 48 else {
            return false
        }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let ignored: NSEvent.ModifierFlags = [.capsLock, .numericPad, .function]
        switch modifiers.subtracting(ignored) {
        case []:
            return handleBlockReferenceCommand(.indent)
        case [.shift]:
            return handleBlockReferenceCommand(.outdent)
        default:
            return false
        }
    }

    /// Intercept the physical key before AppKit's automatic bracket pairing
    /// can turn the first `[` into `[]`. Wiki-link creation needs the literal
    /// `[[` trigger so its end can be chosen later in the line.
    private func handleWikiLinkOpeningBracket(_ event: NSEvent) -> Bool {
        guard !configuration.rawSourceMode,
              !hasMarkedText(),
              event.charactersIgnoringModifiers == "["
        else {
            return false
        }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let ignored: NSEvent.ModifierFlags = [.capsLock, .numericPad, .function, .shift]
        guard modifiers.subtracting(ignored).isEmpty else { return false }
        insertText("[", replacementRange: selectedRange())
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleBlockReferenceTab(event) { return true }
        if handleFocusedCommandReturnKeyEquivalent(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    func handleFocusedCommandReturnKeyEquivalent(_ event: NSEvent) -> Bool {
        handleCommandReturnKeyEquivalent(
            event,
            firstResponder: window?.firstResponder
        )
    }

    func handleCommandReturnKeyEquivalent(
        _ event: NSEvent,
        firstResponder: NSResponder?
    ) -> Bool {
        guard firstResponder === self else { return false }
        return handleCommandReturn(event)
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

    func handleOptionArrow(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let ignoredModifiers: NSEvent.ModifierFlags = [.capsLock, .numericPad, .function]
        let shortcutModifiers = modifiers.subtracting(ignoredModifiers)
        guard shortcutModifiers == .option else { return false }
        switch event.keyCode {
        case 126:
            return moveBulletItem(.up)
        case 125:
            return moveBulletItem(.down)
        default:
            return false
        }
    }
}

import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("Task checkbox source protection")
struct TaskCheckboxProtectionTests {
    private let text = "first\n  - [ ] task\n"

    private func makeCoordinator() -> NativeTextViewCoordinator {
        NativeTextViewCoordinator(
            text: .constant(text),
            fontName: "SF Pro",
            fontSize: 16,
            isWikiLinkActive: .constant(false),
            onLinkClick: nil,
            onInlineSelectionChange: nil
        )
    }

    @Test("protected range ends at the first content character")
    func protectedRangeStopsAtContent() {
        #expect(MarkdownStyler.taskProtectedRange(at: 8, in: text) == NSRange(location: 6, length: 8))
        #expect(MarkdownStyler.taskProtectedRange(at: 13, in: text) != nil)
        #expect(MarkdownStyler.taskProtectedRange(at: 14, in: text) == nil)
    }

    @Test("arrow navigation skips the protected task prefix")
    func caretSkipsPrefix() {
        let coordinator = makeCoordinator()
        let textView = NativeTextView(frame: .zero)
        textView.string = text

        coordinator.previousSelectedRange = NSRange(location: 14, length: 0)
        textView.setSelectedRange(NSRange(location: 13, length: 0))
        #expect(coordinator.redirectSelectionFromTaskPrefix(in: textView))
        #expect(textView.selectedRange() == NSRange(location: 14, length: 0))

        coordinator.previousSelectedRange = NSRange(location: 5, length: 0)
        textView.setSelectedRange(NSRange(location: 6, length: 0))
        #expect(coordinator.redirectSelectionFromTaskPrefix(in: textView))
        #expect(textView.selectedRange() == NSRange(location: 14, length: 0))
    }

    @Test("typing cannot modify task syntax but checkbox toggles remain valid")
    func editsProtectPrefix() {
        let coordinator = makeCoordinator()
        #expect(coordinator.editTouchesProtectedTaskPrefix(
            affectedRange: NSRange(location: 11, length: 0),
            replacement: "x",
            in: text
        ))
        #expect(coordinator.editTouchesProtectedTaskPrefix(
            affectedRange: NSRange(location: 13, length: 1),
            replacement: "",
            in: text
        ))
        #expect(!coordinator.editTouchesProtectedTaskPrefix(
            affectedRange: NSRange(location: 14, length: 1),
            replacement: "T",
            in: text
        ))
        #expect(!coordinator.editTouchesProtectedTaskPrefix(
            affectedRange: NSRange(location: 10, length: 3),
            replacement: "[x]",
            in: text
        ))
    }
}

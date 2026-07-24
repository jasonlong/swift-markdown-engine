import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("List-prefix source protection")
struct ListPrefixProtectionTests {
    private let taskText = "first\n  - [ ] task\n"
    private let bulletText = "first\n  * item\n"

    private func makeCoordinator(text: String) -> NativeTextViewCoordinator {
        NativeTextViewCoordinator(
            text: .constant(text),
            fontName: "SF Pro",
            fontSize: 16,
            isWikiLinkActive: .constant(false),
            onLinkClick: nil,
            onInlineSelectionChange: nil
        )
    }

    @Test("protected ranges end at the first content character")
    func protectedRangesStopAtContent() {
        #expect(
            MarkdownStyler.listProtectedRange(at: 8, in: taskText)
                == NSRange(location: 6, length: 8)
        )
        #expect(MarkdownStyler.listProtectedRange(at: 13, in: taskText) != nil)
        #expect(MarkdownStyler.listProtectedRange(at: 14, in: taskText) == nil)

        #expect(
            MarkdownStyler.listProtectedRange(at: 8, in: bulletText)
                == NSRange(location: 6, length: 4)
        )
        #expect(MarkdownStyler.listProtectedRange(at: 9, in: bulletText) != nil)
        #expect(MarkdownStyler.listProtectedRange(at: 10, in: bulletText) == nil)
    }

    @Test("caret navigation skips protected list prefixes")
    func caretSkipsPrefixes() {
        let coordinator = makeCoordinator(text: taskText)
        let textView = NativeTextView(frame: .zero)
        textView.string = taskText

        coordinator.previousSelectedRange = NSRange(location: 14, length: 0)
        textView.setSelectedRange(NSRange(location: 13, length: 0))
        #expect(coordinator.redirectSelectionFromProtectedListPrefix(in: textView))
        #expect(textView.selectedRange() == NSRange(location: 14, length: 0))

        textView.string = bulletText
        coordinator.previousSelectedRange = NSRange(location: 10, length: 0)
        textView.setSelectedRange(NSRange(location: 8, length: 0))
        #expect(coordinator.redirectSelectionFromProtectedListPrefix(in: textView))
        #expect(textView.selectedRange() == NSRange(location: 10, length: 0))
    }

    @Test("typing cannot modify list syntax but checkbox toggles remain valid")
    func editsProtectPrefixes() {
        let taskCoordinator = makeCoordinator(text: taskText)
        #expect(taskCoordinator.editTouchesProtectedListPrefix(
            affectedRange: NSRange(location: 11, length: 0),
            replacement: "x",
            in: taskText
        ))
        #expect(!taskCoordinator.editTouchesProtectedListPrefix(
            affectedRange: NSRange(location: 14, length: 1),
            replacement: "T",
            in: taskText
        ))
        #expect(!taskCoordinator.editTouchesProtectedListPrefix(
            affectedRange: NSRange(location: 10, length: 3),
            replacement: "[x]",
            in: taskText
        ))

        let bulletCoordinator = makeCoordinator(text: bulletText)
        #expect(bulletCoordinator.editTouchesProtectedListPrefix(
            affectedRange: NSRange(location: 8, length: 1),
            replacement: "-",
            in: bulletText
        ))
        #expect(bulletCoordinator.editTouchesProtectedListPrefix(
            affectedRange: NSRange(location: 9, length: 1),
            replacement: "",
            in: bulletText
        ))
        #expect(!bulletCoordinator.editTouchesProtectedListPrefix(
            affectedRange: NSRange(location: 10, length: 1),
            replacement: "I",
            in: bulletText
        ))
    }
}

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

    @Test("a hidden ID on an empty list row leaves an insertion boundary")
    func identifiedEmptyRowsLeaveContentBoundary() {
        let id = "01hzy7vz8g4qj6m2n3r5t7w9xy"
        let bullet = "*  ^\(id)"
        let task = "- [ ]  ^\(id)"

        #expect(
            MarkdownStyler.listProtectedRange(at: 1, in: bullet)
                == NSRange(location: 0, length: 2)
        )
        #expect(MarkdownStyler.listProtectedRange(at: 2, in: bullet) == nil)
        #expect(
            MarkdownStyler.listProtectedRange(at: 5, in: task)
                == NSRange(location: 0, length: 6)
        )
        #expect(MarkdownStyler.listProtectedRange(at: 6, in: task) == nil)
    }

    @Test("typing at the visual end of an identified empty bullet inserts before its ID")
    func typingAtIdentifiedEmptyBulletEnd() {
        _ = NSApplication.shared
        let id = "01hzy7vz8g4qj6m2n3r5t7w9xy"
        let source = "*  ^\(id)\n* next"
        let coordinator = makeCoordinator(text: source)
        let textView = NativeTextView(frame: .zero)
        textView.delegate = coordinator
        coordinator.textView = textView
        textView.string = source
        let idEnd = ("*  ^\(id)" as NSString).length
        textView.setSelectedRange(NSRange(location: idEnd, length: 0))

        #expect(!coordinator.textView(
            textView,
            shouldChangeTextIn: textView.selectedRange(),
            replacementString: "a"
        ))
        #expect(textView.string == "* a ^\(id)\n* next")
        #expect(textView.selectedRange() == NSRange(location: 3, length: 0))
    }

    @Test("a hidden ID boundary retains ordinary typing metrics")
    func hiddenIDBoundaryTypingAttributes() throws {
        _ = NSApplication.shared
        let id = "01hzy7vz8g4qj6m2n3r5t7w9xy"
        let source = "* item ^\(id)\n* next"
        let coordinator = makeCoordinator(text: source)
        let textView = NativeTextView(frame: .zero)
        textView.delegate = coordinator
        coordinator.textView = textView
        textView.string = source
        let fullRange = NSRange(location: 0, length: (source as NSString).length)
        textView.textStorage?.addAttribute(
            .font,
            value: NSFont.systemFont(ofSize: 16),
            range: fullRange
        )
        let idRange = try #require(
            MarkdownBlockReferenceSyntax.protectedIDRanges(in: source).first
        )
        textView.textStorage?.addAttribute(
            .font,
            value: NSFont.systemFont(ofSize: 0.1),
            range: idRange
        )
        textView.setSelectedRange(NSRange(location: NSMaxRange(idRange), length: 0))
        textView.delegate = nil
        textView.typingAttributes[.font] = NSFont.systemFont(ofSize: 0.1)
        textView.delegate = coordinator
        #expect((textView.typingAttributes[.font] as? NSFont)?.pointSize == 0.1)
        coordinator.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: textView)
        )
        #expect(
            (textView.typingAttributes[.font] as? NSFont)?.pointSize == 16
        )
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
        #expect(!bulletCoordinator.editTouchesProtectedListPrefix(
            affectedRange: NSRange(location: 5, length: 5),
            replacement: "",
            in: bulletText
        ))
    }

    @Test("checkbox demotion range covers only `[ ] `, keeping the bullet marker")
    func demotionRangeExcludesBulletMarker() {
        // "first\n  - [ ] task\n": bullet `- ` at 8, checkbox `[ ]` at 10,
        // content "task" at 14. Demotion removes `[ ] ` = [10, 4).
        #expect(
            MarkdownStyler.taskCheckboxDemotionRange(at: 13, in: taskText)
                == NSRange(location: 10, length: 4)
        )
        #expect(
            MarkdownStyler.taskCheckboxDemotionRange(at: 14, in: taskText)
                == NSRange(location: 10, length: 4)
        )
        // Plain bullets have no checkbox to demote.
        #expect(MarkdownStyler.taskCheckboxDemotionRange(at: 8, in: bulletText) == nil)
    }

    @Test("Backspace at task content start demotes the task to a plain bullet")
    func backspaceDemotesTaskToBullet() {
        let coordinator = makeCoordinator(text: taskText)
        let textView = NativeTextView(frame: .zero)
        textView.string = taskText
        textView.setSelectedRange(NSRange(location: 14, length: 0))

        #expect(coordinator.handleBackspaceAtProtectedListStart(textView))
        #expect(textView.string == "first\n  - task\n")
        #expect(textView.selectedRange() == NSRange(location: 10, length: 0))
    }
}

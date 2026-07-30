import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

/// A systematic matrix of the editor's core editing gestures — Return,
/// Backspace, and Forward-Delete in every block context — asserting the
/// resulting text and caret against what a user of a WYSIWYG markdown editor
/// expects. Keystrokes route through the same delegate pipeline AppKit uses
/// (doCommandBy first, then the native command through shouldChangeTextIn).
@MainActor
@Suite("Editing behavior matrix", .serialized)
struct EditingBehaviorMatrixTests {
    private struct EditorStack {
        let scrollView: ClampedScrollView
        let container: NativeTextViewContainer
        let textView: NativeTextView
        let coordinator: NativeTextViewCoordinator
    }

    private func makeEditor(text: String) -> EditorStack {
        _ = NSApplication.shared
        let scrollView = ClampedScrollView(
            frame: NSRect(x: 0, y: 0, width: 600, height: 800)
        )
        scrollView.fitsContent = true

        let textView = NativeTextView(frame: .zero)
        var configuration = MarkdownEditorConfiguration.default
        configuration.heightBehavior = .fitsContent
        textView.configuration = configuration
        textView.baseFont = NSFont(name: "SF Pro", size: 16) ?? .systemFont(ofSize: 16)
        textView.font = textView.baseFont
        textView.isEditable = true
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false

        let coordinator = NativeTextViewCoordinator(
            text: .constant(text),
            fontName: "SF Pro",
            fontSize: 16,
            isWikiLinkActive: .constant(false),
            onLinkClick: nil,
            onInlineSelectionChange: nil
        )
        coordinator.configuration = configuration
        coordinator.previousDisplayLength = (text as NSString).length
        let bridge = LayoutBridge(textView.textLayoutManager!)
        coordinator.layoutBridge = bridge
        textView.layoutBridge = bridge
        textView.delegate = coordinator
        textView.string = text

        let container = NativeTextViewContainer(
            frame: NSRect(x: 0, y: 0, width: 600, height: 0)
        )
        container.textView = textView
        textView.frame = NSRect(x: 0, y: 0, width: 600, height: 0)
        container.addSubview(textView)
        scrollView.documentView = container
        textView.recalcOverscroll(for: scrollView)

        return EditorStack(
            scrollView: scrollView,
            container: container,
            textView: textView,
            coordinator: coordinator
        )
    }

    private func pressReturn(_ stack: EditorStack) {
        if !stack.coordinator.textView(
            stack.textView,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        ) {
            stack.textView.insertNewline(nil)
        }
    }

    private func pressBackspace(_ stack: EditorStack) {
        if !stack.coordinator.textView(
            stack.textView,
            doCommandBy: #selector(NSResponder.deleteBackward(_:))
        ) {
            stack.textView.deleteBackward(nil)
        }
    }

    private func pressForwardDelete(_ stack: EditorStack) {
        if !stack.coordinator.textView(
            stack.textView,
            doCommandBy: #selector(NSResponder.deleteForward(_:))
        ) {
            stack.textView.deleteForward(nil)
        }
    }

    // MARK: - Return

    @Test("Return at a plain paragraph end inserts exactly one newline")
    func returnAtParagraphEnd() {
        let stack = makeEditor(text: "hello")
        stack.textView.setSelectedRange(NSRange(location: 5, length: 0))
        pressReturn(stack)
        #expect(stack.textView.string == "hello\n")
        #expect(stack.textView.selectedRange() == NSRange(location: 6, length: 0))
    }

    @Test("Return mid-paragraph splits it without extra newlines")
    func returnMidParagraph() {
        let stack = makeEditor(text: "hello")
        stack.textView.setSelectedRange(NSRange(location: 2, length: 0))
        pressReturn(stack)
        #expect(stack.textView.string == "he\nllo")
    }

    @Test("Return after a heading inserts exactly one newline")
    func returnAfterHeading() {
        let stack = makeEditor(text: "# Head\n\nBody")
        stack.textView.setSelectedRange(NSRange(location: 6, length: 0))
        pressReturn(stack)
        #expect(stack.textView.string == "# Head\n\n\nBody")
        #expect(stack.textView.selectedRange() == NSRange(location: 7, length: 0))
    }

    @Test(
        "Return continues a bullet with the same marker",
        arguments: [("- alpha", "- alpha\n- "), ("* alpha", "* alpha\n* "), ("+ alpha", "+ alpha\n+ ")]
    )
    func returnContinuesBullet(text: String, expected: String) {
        let stack = makeEditor(text: text)
        stack.textView.setSelectedRange(
            NSRange(location: (text as NSString).length, length: 0)
        )
        pressReturn(stack)
        #expect(stack.textView.string == expected)
    }

    @Test("Return continues a nested bullet at the same depth")
    func returnContinuesNestedBullet() {
        let stack = makeEditor(text: "\t- nested")
        stack.textView.setSelectedRange(NSRange(location: 9, length: 0))
        pressReturn(stack)
        #expect(stack.textView.string == "\t- nested\n\t- ")
    }

    @Test("Return increments an ordered list")
    func returnIncrementsOrderedList() {
        let stack = makeEditor(text: "1. first")
        stack.textView.setSelectedRange(NSRange(location: 8, length: 0))
        pressReturn(stack)
        #expect(stack.textView.string == "1. first\n2. ")
    }

    @Test("Return after a checked task continues with an unchecked box")
    func returnContinuesTaskUnchecked() {
        let stack = makeEditor(text: "- [x] done")
        stack.textView.setSelectedRange(NSRange(location: 10, length: 0))
        pressReturn(stack)
        #expect(stack.textView.string == "- [x] done\n- [ ] ")
    }

    @Test("Return continues an ordered task with the next number")
    func returnContinuesOrderedTask() {
        let stack = makeEditor(text: "1. [ ] first")
        stack.textView.setSelectedRange(NSRange(location: 12, length: 0))
        pressReturn(stack)
        #expect(stack.textView.string == "1. [ ] first\n2. [ ] ")
    }

    @Test("Return on an empty bullet exits the list without inserting a newline")
    func returnExitsEmptyBullet() {
        let stack = makeEditor(text: "- ")
        stack.textView.setSelectedRange(NSRange(location: 2, length: 0))
        pressReturn(stack)
        #expect(stack.textView.string == "")
        #expect(stack.textView.selectedRange() == NSRange(location: 0, length: 0))
    }

    @Test("Return on an empty task exits the list")
    func returnExitsEmptyTask() {
        let stack = makeEditor(text: "- [ ] ")
        stack.textView.setSelectedRange(NSRange(location: 6, length: 0))
        pressReturn(stack)
        #expect(stack.textView.string == "")
    }

    @Test("Return continues a blockquote")
    func returnContinuesBlockquote() {
        let stack = makeEditor(text: "> quote")
        stack.textView.setSelectedRange(NSRange(location: 7, length: 0))
        pressReturn(stack)
        #expect(stack.textView.string == "> quote\n> ")
    }

    @Test("Return on an empty blockquote line exits the quote")
    func returnExitsEmptyBlockquote() {
        let stack = makeEditor(text: "> ")
        stack.textView.setSelectedRange(NSRange(location: 2, length: 0))
        pressReturn(stack)
        #expect(stack.textView.string == "")
    }

    @Test("Return at a bullet's content start pushes the item down")
    func returnAtBulletContentStart() {
        let stack = makeEditor(text: "- abc")
        stack.textView.setSelectedRange(NSRange(location: 2, length: 0))
        pressReturn(stack)
        #expect(stack.textView.string == "- \n- abc")
        #expect(stack.textView.selectedRange() == NSRange(location: 5, length: 0))
    }

    @Test("Return mid-content splits a bullet into two items")
    func returnSplitsBulletContent() {
        let stack = makeEditor(text: "- abcd")
        stack.textView.setSelectedRange(NSRange(location: 4, length: 0))
        pressReturn(stack)
        #expect(stack.textView.string == "- ab\n- cd")
    }

    @Test("Return at the end of a fence opener completes the code block")
    func returnCompletesCodeFence() {
        let stack = makeEditor(text: "```swift")
        stack.textView.setSelectedRange(NSRange(location: 8, length: 0))
        pressReturn(stack)
        #expect(stack.textView.string == "```swift\n\n```")
        #expect(stack.textView.selectedRange() == NSRange(location: 9, length: 0))
    }

    @Test("Return inside a code block never continues list-looking lines")
    func returnInsideCodeBlockIsPlain() {
        let stack = makeEditor(text: "```\n- a\n```")
        stack.textView.setSelectedRange(NSRange(location: 7, length: 0))
        pressReturn(stack)
        #expect(stack.textView.string == "```\n- a\n\n```")
    }

    // MARK: - Backspace

    @Test("Backspace on an empty trailing bullet joins the previous item")
    func backspaceRemovesEmptyBullet() {
        let stack = makeEditor(text: "- a\n- ")
        stack.textView.setSelectedRange(NSRange(location: 6, length: 0))
        pressBackspace(stack)
        #expect(stack.textView.string == "- a")
        #expect(stack.textView.selectedRange() == NSRange(location: 3, length: 0))
    }

    @Test("Backspace at a nested bullet start joins the parent item")
    func backspaceJoinsNestedBullet() {
        let stack = makeEditor(text: "- a\n\t- b")
        stack.textView.setSelectedRange(NSRange(location: 7, length: 0))
        pressBackspace(stack)
        #expect(stack.textView.string == "- ab")
    }

    @Test("Backspace at checked-task content start demotes to a bullet, keeping content")
    func backspaceDemotesCheckedTask() {
        let stack = makeEditor(text: "- [x] a")
        stack.textView.setSelectedRange(NSRange(location: 6, length: 0))
        pressBackspace(stack)
        #expect(stack.textView.string == "- a")
    }

    @Test("Backspace on a blank line between paragraphs removes one newline")
    func backspaceOnBlankLine() {
        let stack = makeEditor(text: "a\n\nb")
        stack.textView.setSelectedRange(NSRange(location: 2, length: 0))
        pressBackspace(stack)
        #expect(stack.textView.string == "a\nb")
    }

    @Test("Backspace on the leading blank row removes that row")
    func backspaceOnLeadingBlankLine() {
        let stack = makeEditor(text: "\n- Personal")
        stack.textView.setSelectedRange(NSRange(location: 0, length: 0))
        pressBackspace(stack)
        #expect(stack.textView.string == "- Personal")
        #expect(stack.textView.selectedRange() == NSRange(location: 2, length: 0))
    }

    @Test("Backspace removes whitespace from a leading blank row too")
    func backspaceOnWhitespaceOnlyLeadingBlankLine() {
        let stack = makeEditor(text: "\t  \n- Personal")
        stack.textView.setSelectedRange(NSRange(location: 0, length: 0))
        pressBackspace(stack)
        #expect(stack.textView.string == "- Personal")
    }

    @Test("Deleting a selection ending inside a list prefix removes the whole prefix")
    func deleteSelectionEndingInsidePrefix() {
        let stack = makeEditor(text: "first\n- second")
        // "st\n-" — ends between the marker and its trailing space.
        stack.textView.setSelectedRange(NSRange(location: 3, length: 4))
        pressBackspace(stack)
        #expect(stack.textView.string == "firsecond")
        #expect(stack.textView.selectedRange() == NSRange(location: 3, length: 0))
    }

    @Test("Deleting a selection starting inside a list prefix removes the whole prefix")
    func deleteSelectionStartingInsidePrefix() {
        let stack = makeEditor(text: "first\n- second")
        // " se" — starts on the marker's trailing space.
        stack.textView.setSelectedRange(NSRange(location: 7, length: 3))
        pressBackspace(stack)
        #expect(stack.textView.string == "first\ncond")
        #expect(stack.textView.selectedRange() == NSRange(location: 6, length: 0))
    }

    @Test("Typing over a partial prefix slice stays blocked")
    func typingOverPartialPrefixIsBlocked() {
        let stack = makeEditor(text: "first\n- second")
        stack.textView.setSelectedRange(NSRange(location: 6, length: 1))
        stack.textView.insertText(
            "x",
            replacementRange: NSRange(location: 6, length: 1)
        )
        #expect(stack.textView.string == "first\n- second")
    }

    // MARK: - Forward delete

    @Test("Forward delete at a line end pulls the next list item up without its prefix")
    func forwardDeleteJoinsListItem() {
        let stack = makeEditor(text: "a\n- b")
        stack.textView.setSelectedRange(NSRange(location: 1, length: 0))
        pressForwardDelete(stack)
        #expect(stack.textView.string == "ab")
        #expect(stack.textView.selectedRange() == NSRange(location: 1, length: 0))
    }

    @Test("Forward delete merges two list items, stripping the second prefix")
    func forwardDeleteMergesListItems() {
        let stack = makeEditor(text: "- a\n- b")
        stack.textView.setSelectedRange(NSRange(location: 3, length: 0))
        pressForwardDelete(stack)
        #expect(stack.textView.string == "- ab")
    }

    @Test("Forward delete before a task item strips the whole task prefix")
    func forwardDeleteJoinsTaskItem() {
        let stack = makeEditor(text: "a\n- [ ] b")
        stack.textView.setSelectedRange(NSRange(location: 1, length: 0))
        pressForwardDelete(stack)
        #expect(stack.textView.string == "ab")
    }

    @Test("Forward delete mid-line stays native")
    func forwardDeleteMidLineIsNative() {
        let stack = makeEditor(text: "ab")
        stack.textView.setSelectedRange(NSRange(location: 0, length: 0))
        pressForwardDelete(stack)
        #expect(stack.textView.string == "b")
    }

    // MARK: - Compacted blank lines reveal while edited

    @Test("A compacted blank line after a list reveals while the caret is on it")
    func compactedBlankRevealsUnderCaret() {
        let text = "- First\n\n## Next"
        let blankLocation = (text as NSString).range(of: "\n\n").location + 1
        var configuration = MarkdownEditorConfiguration.default
        configuration.lists.trailingBlankLineHeightScale = 0

        let compacted = MarkdownASTStyler.styleAttributes(
            text: text,
            fontName: "SF Pro",
            fontSize: 16,
            configuration: configuration
        ).last { entry in
            NSLocationInRange(blankLocation, entry.range)
                && entry.attributes[.paragraphStyle] != nil
        }
        #expect(compacted != nil)

        let revealed = MarkdownASTStyler.styleAttributes(
            text: text,
            fontName: "SF Pro",
            fontSize: 16,
            caretLocation: blankLocation,
            configuration: configuration
        ).last { entry in
            NSLocationInRange(blankLocation, entry.range)
                && entry.attributes[.paragraphStyle] != nil
        }
        #expect(revealed == nil)
    }

    @Test("A compacted trailing blank at the document end reveals for the caret")
    func compactedBlankAtDocumentEndReveals() {
        let text = "- a\n\n"
        var configuration = MarkdownEditorConfiguration.default
        configuration.lists.trailingBlankLineHeightScale = 0

        let revealed = MarkdownASTStyler.styleAttributes(
            text: text,
            fontName: "SF Pro",
            fontSize: 16,
            caretLocation: (text as NSString).length,
            configuration: configuration
        ).last { entry in
            NSLocationInRange(4, entry.range)
                && entry.attributes[.paragraphStyle] != nil
        }
        #expect(revealed == nil)
    }

    @Test("A selection crossing a compacted blank line reveals it")
    func compactedBlankRevealsUnderSelection() {
        let text = "- First\n\n## Next"
        let blankLocation = (text as NSString).range(of: "\n\n").location + 1
        var configuration = MarkdownEditorConfiguration.default
        configuration.lists.trailingBlankLineHeightScale = 0

        let revealed = MarkdownASTStyler.styleAttributes(
            text: text,
            fontName: "SF Pro",
            fontSize: 16,
            caretLocation: 0,
            selection: NSRange(location: 2, length: 10),
            configuration: configuration
        ).last { entry in
            NSLocationInRange(blankLocation, entry.range)
                && entry.attributes[.paragraphStyle] != nil
        }
        #expect(revealed == nil)
    }

    @Test("blankRunRange finds the full whitespace-only run")
    func blankRunRangeCoversRun() {
        let text = "a\n\n\nb"
        #expect(
            MarkdownStyler.blankRunRange(at: 2, in: text)
                == NSRange(location: 2, length: 2)
        )
        #expect(
            MarkdownStyler.blankRunRange(at: 3, in: text)
                == NSRange(location: 2, length: 2)
        )
        #expect(MarkdownStyler.blankRunRange(at: 0, in: text) == nil)
        #expect(MarkdownStyler.blankRunRange(at: 4, in: text) == nil)
        #expect(
            MarkdownStyler.blankRunRange(at: 3, in: "a\n\n")
                == NSRange(location: 2, length: 1)
        )
    }

    @Test("Moving the caret onto a compacted blank line restyles it to full height")
    func caretEntryRevealsCompactedBlankInEditor() throws {
        let text = "# H\n\nBody"
        let stack = makeEditor(text: text)
        var configuration = stack.textView.configuration
        configuration.headings.trailingBlankLineHeightScale = 0
        stack.textView.configuration = configuration
        stack.coordinator.configuration = configuration
        stack.textView.setSelectedRange(NSRange(location: 0, length: 0))
        stack.coordinator.rebuildTextStorageAndStyle(stack.textView, from: text)

        let storage = try #require(stack.textView.textStorage)
        let compacted = storage.attribute(
            .paragraphStyle, at: 4, effectiveRange: nil
        ) as? NSParagraphStyle
        #expect(compacted?.maximumLineHeight == 1)

        stack.textView.setSelectedRange(NSRange(location: 4, length: 0))
        let revealed = storage.attribute(
            .paragraphStyle, at: 4, effectiveRange: nil
        ) as? NSParagraphStyle
        #expect(revealed?.maximumLineHeight != 1)

        stack.textView.setSelectedRange(NSRange(location: 0, length: 0))
        let recompacted = storage.attribute(
            .paragraphStyle, at: 4, effectiveRange: nil
        ) as? NSParagraphStyle
        #expect(recompacted?.maximumLineHeight == 1)
    }

    @Test("Arrow keys skip a collapsed list separator without editing")
    func arrowKeysSkipCollapsedListSeparator() throws {
        let text = """
        - Personal
          - Last personal item

        - Work

          - First work item
        """
        let stack = makeEditor(text: text)
        var configuration = stack.textView.configuration
        configuration.lists.trailingBlankLineHeightScale = 0
        stack.textView.configuration = configuration
        stack.coordinator.configuration = configuration
        stack.textView.frame = NSRect(x: 0, y: 0, width: 600, height: 240)
        stack.coordinator.rebuildTextStorageAndStyle(stack.textView, from: text)
        stack.textView.textLayoutManager?.ensureLayout(
            for: stack.textView.textLayoutManager!.documentRange
        )

        let nsText = text as NSString
        let personal = nsText.range(of: "Last personal item")
        let work = nsText.range(of: "Work")
        let blank = nsText.range(of: "\n\n").location + 1
        let storage = try #require(stack.textView.textStorage)
        let compacted = storage.attribute(
            .paragraphStyle,
            at: blank,
            effectiveRange: nil
        ) as? NSParagraphStyle
        #expect(compacted?.maximumLineHeight == 1)

        stack.textView.setSelectedRange(
            NSRange(location: NSMaxRange(personal), length: 0)
        )
        stack.textView.moveDown(nil)
        #expect(
            stack.textView.selectedRange()
                == NSRange(location: NSMaxRange(work), length: 0)
        )
        let stillCompacted = storage.attribute(
            .paragraphStyle,
            at: blank,
            effectiveRange: nil
        ) as? NSParagraphStyle
        #expect(stillCompacted?.maximumLineHeight == 1)
        #expect(stack.textView.string == text)

        stack.textView.setSelectedRange(
            NSRange(location: NSMaxRange(work), length: 0)
        )
        stack.textView.moveDown(nil)
        let firstWorkItem = nsText.range(of: "First work item")
        #expect(
            stack.textView.selectedRange()
                == NSRange(
                    location: firstWorkItem.location + work.length,
                    length: 0
                )
        )
        #expect(stack.textView.string == text)
    }
}

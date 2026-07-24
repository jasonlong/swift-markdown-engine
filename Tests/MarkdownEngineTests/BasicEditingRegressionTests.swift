import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("Basic editing regressions", .serialized)
struct BasicEditingRegressionTests {
    private struct EditorStack {
        let scrollView: ClampedScrollView
        let container: NativeTextViewContainer
        let textView: NativeTextView
        let coordinator: NativeTextViewCoordinator
        let layoutBridge: LayoutBridge
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
        textView.baseFont = .systemFont(ofSize: 16)
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
            coordinator: coordinator,
            layoutBridge: bridge
        )
    }

    @Test("Backspace at a plain line start joins the previous line")
    func backspaceJoinsPlainLines() {
        let stack = makeEditor(text: "first\nsecond")
        stack.textView.setSelectedRange(NSRange(location: 6, length: 0))

        stack.textView.deleteBackward(nil)

        #expect(stack.textView.string == "firstsecond")
        #expect(stack.textView.selectedRange() == NSRange(location: 5, length: 0))
    }

    @Test("Backspace at a list item start joins the previous line")
    func backspaceJoinsListItem() {
        let stack = makeEditor(text: "first\n- second")
        stack.textView.setSelectedRange(NSRange(location: 8, length: 0))

        #expect(stack.coordinator.textView(
            stack.textView,
            doCommandBy: #selector(NSResponder.deleteBackward(_:))
        ))

        #expect(stack.textView.string == "firstsecond")
        #expect(stack.textView.selectedRange() == NSRange(location: 5, length: 0))
    }

    @Test("Backspace at the first list item converts it to a paragraph")
    func backspaceRemovesFirstLineListPrefix() {
        let stack = makeEditor(text: "- first")
        stack.textView.setSelectedRange(NSRange(location: 2, length: 0))

        #expect(stack.coordinator.textView(
            stack.textView,
            doCommandBy: #selector(NSResponder.deleteBackward(_:))
        ))

        #expect(stack.textView.string == "first")
        #expect(stack.textView.selectedRange() == NSRange(location: 0, length: 0))
    }

    @Test("Backspace at a task item start joins and removes task syntax")
    func backspaceJoinsTaskItem() {
        let stack = makeEditor(text: "first\n- [ ] second")
        stack.textView.setSelectedRange(NSRange(location: 12, length: 0))

        #expect(stack.coordinator.textView(
            stack.textView,
            doCommandBy: #selector(NSResponder.deleteBackward(_:))
        ))

        #expect(stack.textView.string == "firstsecond")
        #expect(stack.textView.selectedRange() == NSRange(location: 5, length: 0))
    }

    @Test("Return grows a fit-content editor enough to show the new line")
    func returnGrowsFitContentEditor() {
        let stack = makeEditor(text: "first")
        stack.textView.setSelectedRange(NSRange(location: 5, length: 0))
        let before = stack.container.scrollableContentHeight

        stack.textView.insertNewline(nil)

        let after = stack.container.scrollableContentHeight
        #expect(stack.textView.string == "first\n")
        #expect(after > before)
        #expect(stack.textView.frame.height == after)
    }
}

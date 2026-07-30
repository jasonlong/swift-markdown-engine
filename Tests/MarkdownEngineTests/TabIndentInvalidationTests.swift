import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

/// Tab / Shift-Tab on a list item must invalidate attributes only around the
/// edited line. A whole-document attribute pass forces TextKit to relayout and
/// redraw the entire note, which the user sees as a blank-and-rerender flash.
@MainActor
@Suite("Tab indent invalidation scope", .serialized)
struct TabIndentInvalidationTests {
    private final class StorageEditRecorder: @unchecked Sendable {
        var attributeEditRanges: [NSRange] = []

        func record(_ notification: Notification) {
            guard let storage = notification.object as? NSTextStorage,
                  storage.editedMask.contains(.editedAttributes) else {
                return
            }
            attributeEditRanges.append(storage.editedRange)
        }
    }

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

    private let noteText = """
        # Title

        A paragraph of prose far away from the list.

        Another paragraph with more content in it.

        - alpha
        - beta
        """

    private func recordingAttributeEdits(
        in stack: EditorStack,
        during action: () -> Void
    ) throws -> [NSRange] {
        let storage = try #require(stack.textView.textStorage)
        let recorder = StorageEditRecorder()
        let observer = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification,
            object: storage,
            queue: nil
        ) { notification in
            recorder.record(notification)
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        action()
        return recorder.attributeEditRanges
    }

    @Test("Tab indents a trailing bullet without touching distant paragraphs")
    func tabIndentInvalidatesLocally() throws {
        let stack = makeEditor(text: noteText)
        stack.coordinator.rebuildTextStorageAndStyle(stack.textView, from: noteText)
        let ns = noteText as NSString
        let caret = ns.length
        stack.textView.setSelectedRange(NSRange(location: caret, length: 0))
        // Everything before the list is "distant": prose the Tab must not touch.
        let listStart = ns.range(of: "- alpha").location
        let distantRange = NSRange(location: 0, length: listStart - 2)

        let edits = try recordingAttributeEdits(in: stack) {
            stack.textView.insertText(
                "\t",
                replacementRange: NSRange(location: caret, length: 0)
            )
        }

        #expect(stack.textView.string.hasSuffix("\t- beta"))
        #expect(!edits.isEmpty)
        let distantEdits = edits.filter {
            NSIntersectionRange($0, distantRange).length > 0
        }
        #expect(
            distantEdits.isEmpty,
            "Tab invalidated far-away content: \(distantEdits) (doc length \(ns.length))"
        )
    }

    @Test("Shift-Tab outdents a trailing bullet without touching distant paragraphs")
    func backtabInvalidatesLocally() throws {
        let indented = noteText.replacingOccurrences(of: "- beta", with: "\t- beta")
        let stack = makeEditor(text: indented)
        stack.coordinator.rebuildTextStorageAndStyle(stack.textView, from: indented)
        let ns = indented as NSString
        stack.textView.setSelectedRange(NSRange(location: ns.length, length: 0))
        let listStart = ns.range(of: "- alpha").location
        let distantRange = NSRange(location: 0, length: listStart - 2)

        let edits = try recordingAttributeEdits(in: stack) {
            _ = stack.coordinator.textView(
                stack.textView,
                doCommandBy: #selector(NSResponder.insertBacktab(_:))
            )
        }

        #expect(stack.textView.string.hasSuffix("\n- beta"))
        let distantEdits = edits.filter {
            NSIntersectionRange($0, distantRange).length > 0
        }
        #expect(
            distantEdits.isEmpty,
            "Shift-Tab invalidated far-away content: \(distantEdits) (doc length \(ns.length))"
        )
    }

    @Test("Tab from before an atomic copied reference indents its line")
    func tabIndentsAtomicReferenceFromCaretBefore() throws {
        let reference = "![[Weekly#^01hzy7vz8g4qj6m2n3r5t7w9xy]]"
        let source = "  \(reference)"
        let stack = makeEditor(text: source)
        let token = try #require(MarkdownBlockReferenceSyntax.tokens(in: source).first)
        stack.textView.setSelectedRange(
            NSRange(location: token.range.location, length: 0)
        )

        #expect(
            stack.coordinator.textView(
                stack.textView,
                doCommandBy: #selector(NSResponder.insertTab(_:))
            )
        )
        #expect(stack.textView.string == "\t\(source)")
        #expect(stack.textView.selectedRange() == NSRange(location: 0, length: 0))
    }

    @Test("physical Tab before an atomic copied reference stays in the editor")
    func physicalTabIndentsAtomicReferenceFromCaretBefore() throws {
        let reference = "![[Weekly#^01hzy7vz8g4qj6m2n3r5t7w9xy]]"
        let source = "  \(reference)"
        let stack = makeEditor(text: source)
        let token = try #require(MarkdownBlockReferenceSyntax.tokens(in: source).first)
        stack.textView.setSelectedRange(
            NSRange(location: token.range.location, length: 0)
        )
        let tab = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            isARepeat: false,
            keyCode: 48
        ))

        stack.textView.keyDown(with: tab)

        #expect(stack.textView.string == "\t\(source)")
        #expect(stack.textView.selectedRange() == NSRange(location: 0, length: 0))
    }

    @Test("Tab key equivalents before a copied reference stay in the editor")
    func tabKeyEquivalentIndentsAtomicReferenceFromCaretBefore() throws {
        let reference = "![[Weekly#^01hzy7vz8g4qj6m2n3r5t7w9xy]]"
        let source = "  \(reference)"
        let stack = makeEditor(text: source)
        let token = try #require(MarkdownBlockReferenceSyntax.tokens(in: source).first)
        stack.textView.setSelectedRange(
            NSRange(location: token.range.location, length: 0)
        )
        let tab = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            isARepeat: false,
            keyCode: 48
        ))

        #expect(stack.textView.performKeyEquivalent(with: tab))
        #expect(stack.textView.string == "\t\(source)")
    }
}

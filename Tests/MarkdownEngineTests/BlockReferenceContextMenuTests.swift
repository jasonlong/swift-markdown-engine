import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("Block reference context-menu targeting")
struct BlockReferenceContextMenuTests {
    private struct Editor {
        let textView: NativeTextView
        let coordinator: NativeTextViewCoordinator
        let bridge: LayoutBridge
    }

    private func makeEditor(_ source: String) -> Editor {
        _ = NSApplication.shared
        let textView = NativeTextView(
            frame: NSRect(x: 0, y: 0, width: 520, height: 260)
        )
        let configuration = MarkdownEditorConfiguration.default
        textView.configuration = configuration
        textView.baseFont = .systemFont(ofSize: 16)
        textView.font = textView.baseFont
        textView.isEditable = true
        textView.isSelectable = true
        textView.textContainer?.containerSize = NSSize(
            width: 520,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true

        let coordinator = NativeTextViewCoordinator(
            text: .constant(source),
            fontName: textView.baseFont.fontName,
            fontSize: 16,
            isWikiLinkActive: .constant(false),
            onLinkClick: nil,
            onInlineSelectionChange: nil
        )
        let bridge = LayoutBridge(textView.textLayoutManager!)
        coordinator.configuration = configuration
        coordinator.layoutBridge = bridge
        coordinator.textView = textView
        textView.layoutBridge = bridge
        textView.delegate = coordinator
        textView.string = source
        coordinator.restyleTextView(
            textView,
            paragraphCandidates: [
                NSRange(location: 0, length: (source as NSString).length),
            ]
        )
        textView.textLayoutManager?.ensureLayout(
            for: textView.textLayoutManager!.documentRange
        )
        return Editor(
            textView: textView,
            coordinator: coordinator,
            bridge: bridge
        )
    }

    private func center(
        of range: NSRange,
        in editor: Editor
    ) throws -> CGPoint {
        let container = try #require(editor.textView.textContainer)
        let rect = editor.bridge.boundingRect(
            forCharacterRange: range,
            in: container
        )
        #expect(!rect.isEmpty)
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    @Test("right-clicked bullet wins over a caret on another row")
    func clickedBulletWinsOverCaret() throws {
        let source = "- Alpha\n- Beta"
        let editor = makeEditor(source)
        editor.textView.setSelectedRange(NSRange(location: 11, length: 0))
        let marker = NSRange(location: 0, length: 1)
        let target = editor.coordinator.contextMenuTarget(
            in: editor.textView,
            containerPoint: try center(of: marker, in: editor),
            clickedCharacterIndex: 0
        )

        #expect(target.selection == NSRange(location: 11, length: 0))
        #expect(target.listMarkerLineRange == NSRange(location: 0, length: 8))
    }

    @Test("right-clicking a task checkbox targets its source row")
    func taskCheckboxTargetsTaskRow() throws {
        let source = "- Before\n- [ ] Ship it\n- After"
        let editor = makeEditor(source)
        let checkbox = NSRange(location: 11, length: 3)
        let container = try #require(editor.textView.textContainer)
        let anchor = editor.bridge.boundingRect(
            forCharacterRange: checkbox,
            in: container
        )
        let size = TaskCheckboxGeometry.size(
            for: editor.textView.baseFont,
            scale: editor.textView.configuration.taskCheckbox.sizeScale
        )
        let point = CGPoint(
            x: TaskCheckboxGeometry.boxX(
                contentX: anchor.minX,
                size: size,
                gap: editor.textView.configuration.taskCheckbox.contentGap
            ) + size / 2,
            y: anchor.midY
        )
        let target = editor.coordinator.contextMenuTarget(
            in: editor.textView,
            containerPoint: point,
            clickedCharacterIndex: checkbox.location
        )

        #expect(target.listMarkerLineRange == NSRange(location: 9, length: 14))
    }

    @Test("right-clicking text preserves the ordinary selection target")
    func textClickIsNotMarkerTarget() {
        let source = "- Alpha\n- Beta"
        let editor = makeEditor(source)
        let selection = NSRange(location: 2, length: 5)
        editor.textView.setSelectedRange(selection)
        let target = editor.coordinator.contextMenuTarget(
            in: editor.textView,
            containerPoint: CGPoint(x: 300, y: 10),
            clickedCharacterIndex: 4
        )

        #expect(target.selection == selection)
        #expect(!target.isListMarker)
    }

    @Test("nested markers report the innermost clicked row")
    func nestedMarkerTargetsNestedRow() throws {
        let source = "- Parent\n  - Child\n    - Grandchild"
        let editor = makeEditor(source)
        let nestedMarker = NSRange(location: 11, length: 1)
        let target = editor.coordinator.contextMenuTarget(
            in: editor.textView,
            containerPoint: try center(of: nestedMarker, in: editor),
            clickedCharacterIndex: nestedMarker.location
        )

        #expect(
            target.listMarkerLineRange
                == NSRange(location: 9, length: 10)
        )
    }
}

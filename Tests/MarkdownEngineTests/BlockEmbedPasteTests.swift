import AppKit
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("Block embed paste placement")
struct BlockEmbedPasteTests {
    private let embed = "![[Weekly#^01hzy7vz8g4qj6m2n3r5t7w9xy]]"

    @Test("pasting into an empty note leaves the caret on a fresh line")
    func emptyNote() {
        let textView = NativeTextView(frame: .zero)
        textView.insertBlockEmbed(embed)

        #expect(textView.string == embed + "\n")
        #expect(textView.selectedRange() == NSRange(
            location: (embed + "\n").utf16.count,
            length: 0
        ))
    }

    @Test("pasting before an existing newline advances across that newline")
    func existingFollowingNewline() {
        let textView = NativeTextView(frame: .zero)
        textView.string = "Before\nAfter"
        textView.setSelectedRange(NSRange(location: 6, length: 0))

        textView.insertBlockEmbed(embed)

        let expected = "Before\n" + embed + "\nAfter"
        #expect(textView.string == expected)
        #expect(textView.selectedRange() == NSRange(
            location: ("Before\n" + embed + "\n").utf16.count,
            length: 0
        ))
    }

    @Test("pasting before text creates a separating newline")
    func createsFollowingNewline() {
        let textView = NativeTextView(frame: .zero)
        textView.string = "Before\nAfter"
        textView.setSelectedRange(NSRange(location: 7, length: 0))

        textView.insertBlockEmbed(embed)

        let expected = "Before\n" + embed + "\nAfter"
        #expect(textView.string == expected)
        #expect(textView.selectedRange() == NSRange(
            location: ("Before\n" + embed + "\n").utf16.count,
            length: 0
        ))
    }

    @Test("pasting into an empty daily bullet replaces its marker")
    func replacesDailyBullet() {
        let textView = NativeTextView(frame: .zero)
        textView.string = "- "
        textView.setSelectedRange(NSRange(location: 2, length: 0))

        textView.insertBlockEmbed(embed)

        #expect(textView.string == embed + "\n")
        #expect(textView.selectedRange() == NSRange(
            location: (embed + "\n").utf16.count,
            length: 0
        ))
    }

    @Test("empty nested list and task containers preserve only indentation")
    func replacesNestedContainers() {
        for marker in ["  - ", "  * ", "  + ", "  2. ", "  3) ", "  - [ ] ", "  - [x] "] {
            let textView = NativeTextView(frame: .zero)
            textView.string = marker + "\nAfter"
            textView.setSelectedRange(NSRange(
                location: (marker as NSString).length,
                length: 0
            ))

            textView.insertBlockEmbed(embed)

            #expect(textView.string == "  " + embed + "\nAfter")
            #expect(textView.selectedRange() == NSRange(
                location: ("  " + embed + "\n").utf16.count,
                length: 0
            ))
        }
    }

    @Test("pasting over an empty marker consumes it from any selection point")
    func replacesSelectedMarker() {
        let textView = NativeTextView(frame: .zero)
        textView.string = "- [ ] \nAfter"
        textView.setSelectedRange(NSRange(location: 2, length: 3))

        textView.insertBlockEmbed(embed)

        #expect(textView.string == embed + "\nAfter")
        #expect(textView.selectedRange() == NSRange(
            location: (embed + "\n").utf16.count,
            length: 0
        ))
    }

    @Test("block embeds preserve CRLF and advance past an existing pair")
    func preservesCRLF() {
        let textView = NativeTextView(frame: .zero)
        textView.string = "- \r\nAfter"
        textView.setSelectedRange(NSRange(location: 2, length: 0))

        textView.insertBlockEmbed(embed)

        #expect(textView.string == embed + "\r\nAfter")
        #expect(textView.selectedRange() == NSRange(
            location: (embed + "\r\n").utf16.count,
            length: 0
        ))
    }

    @Test("repeated pastes remain separate full-line embeds")
    func repeatedPastes() {
        let textView = NativeTextView(frame: .zero)
        textView.insertBlockEmbed(embed)
        textView.insertBlockEmbed(embed)

        #expect(textView.string == embed + "\n" + embed + "\n")
        #expect(MarkdownBlockReferenceSyntax.tokens(in: textView.string).count == 2)
        #expect(textView.selectedRange() == NSRange(
            location: textView.string.utf16.count,
            length: 0
        ))
    }

    @Test("paste is one undoable and redoable edit")
    func undoRedo() throws {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 180),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let textView = NativeTextView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = textView
        window.makeFirstResponder(textView)
        textView.allowsUndo = true
        textView.string = "- "
        textView.setSelectedRange(NSRange(location: 2, length: 0))

        textView.insertBlockEmbed(embed)
        let undoManager = try #require(textView.undoManager)
        #expect(textView.string == embed + "\n")
        #expect(undoManager.canUndo)

        undoManager.undo()
        #expect(textView.string == "- ")
        #expect(undoManager.canRedo)

        undoManager.redo()
        #expect(textView.string == embed + "\n")
    }
}

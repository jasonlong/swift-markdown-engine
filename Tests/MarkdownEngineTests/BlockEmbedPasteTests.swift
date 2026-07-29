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
}

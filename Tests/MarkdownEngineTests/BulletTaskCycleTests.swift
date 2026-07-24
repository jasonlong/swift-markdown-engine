import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("Bullet task-state cycle")
struct BulletTaskCycleTests {
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

    @Test("cycle edits preserve indentation, marker, and source spacing")
    func sourceEdits() {
        #expect(
            BulletTaskCycle.edit(in: "\t*  item", at: 6)
                == BulletTaskCycleEdit(
                    range: NSRange(location: 4, length: 0),
                    replacement: "[ ] "
                )
        )
        #expect(
            BulletTaskCycle.edit(in: "  + [ ]  item", at: 11)
                == BulletTaskCycleEdit(
                    range: NSRange(location: 4, length: 3),
                    replacement: "[x]"
                )
        )
        #expect(
            BulletTaskCycle.edit(in: "- [X]\titem", at: 7)
                == BulletTaskCycleEdit(
                    range: NSRange(location: 2, length: 4),
                    replacement: ""
                )
        )
    }

    @Test("normal, unchecked, and completed bullets form a cycle")
    func cyclesAllStates() {
        let textView = NativeTextView(frame: .zero)
        textView.string = "- item"
        let coordinator = makeCoordinator(text: textView.string)
        textView.delegate = coordinator
        textView.setSelectedRange(NSRange(location: 6, length: 0))

        let commandReturn = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        )
        guard let commandReturn else {
            Issue.record("Could not create Command-Return key event")
            return
        }
        #expect(textView.performKeyEquivalent(with: commandReturn))
        #expect(textView.string == "- [ ] item")
        #expect(textView.selectedRange() == NSRange(location: 10, length: 0))

        #expect(textView.cycleBulletTaskState())
        #expect(textView.string == "- [x] item")
        #expect(textView.selectedRange() == NSRange(location: 10, length: 0))

        #expect(textView.cycleBulletTaskState())
        #expect(textView.string == "- item")
        #expect(textView.selectedRange() == NSRange(location: 6, length: 0))
    }

    @Test("window event dispatch cycles the focused bullet")
    func windowDispatchCyclesFocusedBullet() {
        _ = NSApplication.shared
        let textView = NativeTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        textView.string = "+ item"
        let coordinator = makeCoordinator(text: textView.string)
        textView.delegate = coordinator
        textView.setSelectedRange(NSRange(location: 6, length: 0))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = textView
        #expect(window.makeFirstResponder(textView))

        let commandReturn = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        )
        guard let commandReturn else {
            Issue.record("Could not create Command-Return key event")
            return
        }

        window.sendEvent(commandReturn)

        #expect(textView.string == "+ [ ] item")
        #expect(textView.selectedRange() == NSRange(location: 10, length: 0))

        window.sendEvent(commandReturn)

        #expect(textView.string == "+ [x] item")
        #expect(textView.selectedRange() == NSRange(location: 10, length: 0))

        window.sendEvent(commandReturn)

        #expect(textView.string == "+ item")
        #expect(textView.selectedRange() == NSRange(location: 6, length: 0))
    }

    @Test("non-bullet lines and ordered lists are unchanged")
    func ignoresOtherLines() {
        #expect(BulletTaskCycle.edit(in: "plain text", at: 3) == nil)
        #expect(BulletTaskCycle.edit(in: "1. item", at: 4) == nil)
    }
}

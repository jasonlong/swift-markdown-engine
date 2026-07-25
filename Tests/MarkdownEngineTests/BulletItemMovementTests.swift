import AppKit
import SwiftUI
import Testing

@testable import MarkdownEngine

@MainActor
@Suite("Bullet item movement", .serialized)
struct BulletItemMovementTests {
    private func applying(
        _ direction: BulletItemMoveDirection,
        to text: String,
        selection: NSRange
    ) throws -> (text: String, selection: NSRange, edit: BulletItemMoveEdit) {
        let edit = try #require(
            BulletItemMovement.edit(
                in: text,
                selection: selection,
                direction: direction
            )
        )
        let result = NSMutableString(string: text)
        result.replaceCharacters(
            in: edit.range,
            with: edit.replacement(in: text)
        )
        return (result as String, edit.selection, edit)
    }

    private func caret(in text: String, inside value: String) -> NSRange {
        let range = (text as NSString).range(of: value)
        return NSRange(location: range.location + 1, length: 0)
    }

    private func lineSelection(
        in text: String,
        from first: String,
        through last: String
    ) -> NSRange {
        let source = text as NSString
        let firstRange = source.lineRange(
            for: NSRange(location: source.range(of: first).location, length: 0)
        )
        let lastRange = source.lineRange(
            for: NSRange(location: source.range(of: last).location, length: 0)
        )
        return NSRange(
            location: firstRange.location,
            length: NSMaxRange(lastRange) - firstRange.location
        )
    }

    @Test("moving a parent carries its nested subtree")
    func parentCarriesChildren() throws {
        let text = """
            - A
            \t- child
            - B

            """
        let result = try applying(
            .down,
            to: text,
            selection: caret(in: text, inside: "A")
        )

        #expect(
            result.text == """
                - B
                - A
                \t- child

                """
        )
        #expect(
            result.selection.location
                == (result.text as NSString).range(of: "A").location + 1
        )
    }

    @Test("nested siblings reorder without changing depth")
    func nestedSiblingsReorder() throws {
        let text = """
            - A
            \t- B1
            \t- B2
            \t- B3

            """
        let movedUp = try applying(
            .up,
            to: text,
            selection: caret(in: text, inside: "B2")
        )
        #expect(
            movedUp.text == """
                - A
                \t- B2
                \t- B1
                \t- B3

                """
        )

        let movedDown = try applying(
            .down,
            to: text,
            selection: caret(in: text, inside: "B2")
        )
        #expect(
            movedDown.text == """
                - A
                \t- B1
                \t- B3
                \t- B2

                """
        )
    }

    @Test("moving at end of file keeps each item on its own line")
    func finalItemWithoutTrailingNewlineStaysSeparate() throws {
        let text = "- [ ] A\n- [ ] B"

        let movedUp = try applying(
            .up,
            to: text,
            selection: caret(in: text, inside: "B")
        )
        #expect(movedUp.text == "- [ ] B\n- [ ] A")
        #expect(
            movedUp.selection.location
                == (movedUp.text as NSString).range(of: "B").location + 1
        )

        let movedDown = try applying(
            .down,
            to: text,
            selection: caret(in: text, inside: "A")
        )
        #expect(movedDown.text == "- [ ] B\n- [ ] A")
        #expect(
            movedDown.selection.location
                == (movedDown.text as NSString).range(of: "A").location + 1
        )
    }

    @Test("moving a subtree to end of file preserves its line breaks")
    func subtreeMovedToEndWithoutTrailingNewlineStaysSeparate() throws {
        let text = "- A\n\t- child\n- B"
        let result = try applying(
            .down,
            to: text,
            selection: caret(in: text, inside: "A")
        )

        #expect(result.text == "- B\n- A\n\t- child")
        #expect(
            result.selection.location
                == (result.text as NSString).range(of: "A").location + 1
        )
    }

    @Test("moving first nested items up lifts them before their parent like Reflect")
    func nestedFirstItemsLiftUp() throws {
        let text = """
            - A1
            - A2
            \t- B1
            \t- B2
            \t- B3

            """
        let selection = lineSelection(
            in: text,
            from: "B1",
            through: "B2"
        )
        let result = try applying(.up, to: text, selection: selection)

        #expect(
            result.text == """
                - A1
                - B1
                - B2
                - A2
                \t- B3

                """
        )
        #expect(
            (result.text as NSString).substring(with: result.selection)
                == "- B1\n- B2\n"
        )
    }

    @Test("moving last nested items down lifts them past the parent's next sibling")
    func nestedLastItemsLiftDown() throws {
        let text = """
            - A1
            - A2
            \t- B1
            \t- B2
            - A3

            """
        let selection = lineSelection(
            in: text,
            from: "B1",
            through: "B2"
        )
        let result = try applying(.down, to: text, selection: selection)

        #expect(
            result.text == """
                - A1
                - A2
                - A3
                - B1
                - B2

                """
        )
        #expect(
            (result.text as NSString).substring(with: result.selection)
                == "- B1\n- B2\n"
        )
    }

    @Test("movement stops at top-level document boundaries")
    func boundariesAreNoOps() {
        let text = "- A\n- B\n"
        #expect(
            BulletItemMovement.edit(
                in: text,
                selection: caret(in: text, inside: "A"),
                direction: .up
            ) == nil
        )
        #expect(
            BulletItemMovement.edit(
                in: text,
                selection: caret(in: text, inside: "B"),
                direction: .down
            ) == nil
        )
    }

    @Test("moving attributed items preserves wiki-link metadata")
    func preservesWikiLinkMetadata() throws {
        let text = "- [[Note]]\n- Other\n"
        let result = try applying(
            .down,
            to: text,
            selection: caret(in: text, inside: "Note")
        )
        let source = NSMutableAttributedString(string: text)
        source.addAttribute(
            .wikiLinkID,
            value: "note-id",
            range: (text as NSString).range(of: "Note")
        )
        let replacement = result.edit.attributedReplacement(from: source)
        let moved = NSMutableAttributedString(attributedString: source)
        moved.replaceCharacters(in: result.edit.range, with: replacement)
        let movedNameRange = (moved.string as NSString).range(of: "Note")

        #expect(
            moved.attribute(
                .wikiLinkID,
                at: movedNameRange.location,
                effectiveRange: nil
            ) as? String == "note-id"
        )
    }

    @Test("Option-Up dispatches the bullet movement command")
    func optionArrowDispatchesMovement() throws {
        let text = "- A\n- B"
        let textView = NativeTextView(frame: .zero)
        textView.string = text
        textView.isEditable = true
        let coordinator = NativeTextViewCoordinator(
            text: .constant(text),
            fontName: "SF Pro",
            fontSize: 16,
            isWikiLinkActive: .constant(false),
            onLinkClick: nil,
            onInlineSelectionChange: nil
        )
        textView.delegate = coordinator
        textView.setSelectedRange(caret(in: text, inside: "B"))

        let optionUp = try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .option,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "↑",
                charactersIgnoringModifiers: "↑",
                isARepeat: false,
                keyCode: 126
            )
        )

        #expect(textView.handleOptionArrow(optionUp))
        #expect(textView.string == "- B\n- A")
        #expect(
            textView.selectedRange().location
                == (textView.string as NSString).range(of: "B").location + 1
        )
    }
}

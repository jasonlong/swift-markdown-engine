import AppKit
import SwiftUI
import Testing

@testable import MarkdownEngine

@MainActor
@Suite("Atomic wiki-link editing", .serialized)
struct AtomicWikiLinkSelectionTests {
    private final class NavigationRecorder: @unchecked Sendable {
        var target: String?
    }

    private struct ExistingLinkResolver: WikiLinkResolver {
        func resolve(displayName: String, range: NSRange) -> WikiLinkResolution? {
            WikiLinkResolution(id: displayName, exists: true)
        }

        func name(forID id: String) -> String? {
            id == "note-id" ? "Note" : nil
        }
    }

    private struct Editor {
        let textView: NativeTextView
        let coordinator: NativeTextViewCoordinator
        let navigation: NavigationRecorder
    }

    private func makeEditor(
        source: String = "Before [[Note|note-id]] after",
        completedTaskTextColor: NSColor? = nil
    ) -> Editor {
        _ = NSApplication.shared
        let navigation = NavigationRecorder()
        let coordinator = NativeTextViewCoordinator(
            text: .constant(source),
            fontName: "SF Pro",
            fontSize: 16,
            isWikiLinkActive: .constant(false),
            onLinkClick: { navigation.target = $0 },
            onInlineSelectionChange: nil
        )
        var configuration = MarkdownEditorConfiguration.default
        configuration.services.wikiLinks = ExistingLinkResolver()
        configuration.taskCheckbox.checkedTextColor = completedTaskTextColor
        coordinator.configuration = configuration

        let textView = NativeTextView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 400)
        )
        textView.configuration = configuration
        textView.isEditable = true
        textView.isSelectable = true
        textView.delegate = coordinator
        coordinator.textView = textView
        coordinator.rebuildTextStorageAndStyle(textView, from: source)

        return Editor(
            textView: textView,
            coordinator: coordinator,
            navigation: navigation
        )
    }

    private func point(
        in textView: NativeTextView,
        at characterIndex: Int
    ) throws -> CGPoint {
        let textLayoutManager = try #require(textView.textLayoutManager)
        let contentManager = try #require(textLayoutManager.textContentManager)
        textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)
        let location = try #require(
            contentManager.location(
                textLayoutManager.documentRange.location,
                offsetBy: characterIndex
            )
        )
        var segmentFrame: CGRect?
        textLayoutManager.enumerateTextSegments(
            in: NSTextRange(location: location),
            type: .standard,
            options: []
        ) { _, frame, _, _ in
            segmentFrame = frame
            return false
        }
        let frame = try #require(segmentFrame)
        return CGPoint(
            x: textView.textContainerOrigin.x + frame.minX + 2,
            y: textView.textContainerOrigin.y + frame.midY
        )
    }

    @Test("moving a caret into a wiki link selects the entire link")
    func caretSelectsWholeLink() {
        let editor = makeEditor()
        let linkRange = NSRange(location: 7, length: 8)

        editor.textView.setSelectedRange(NSRange(location: linkRange.location, length: 0))
        editor.textView.moveRight(nil)

        #expect(editor.textView.selectedRange() == linkRange)
        #expect(
            editor.textView.textStorage?.attribute(
                .link,
                at: 9,
                effectiveRange: nil
            ) != nil
        )

        editor.textView.setSelectedRange(NSRange(location: NSMaxRange(linkRange), length: 0))
        editor.textView.moveLeft(nil)
        #expect(editor.textView.selectedRange() == linkRange)

        editor.textView.setSelectedRange(NSRange(location: NSMaxRange(linkRange), length: 0))
        #expect(
            editor.textView.selectedRange()
                == NSRange(location: NSMaxRange(linkRange), length: 0)
        )
    }

    @Test("partial selections expand to include complete wiki links")
    func partialSelectionsExpand() {
        let editor = makeEditor()

        editor.textView.setSelectedRange(NSRange(location: 4, length: 7))

        #expect(editor.textView.selectedRange() == NSRange(location: 4, length: 11))
    }

    @Test("Delete removes the selected wiki link as one unit")
    func deleteRemovesWholeLink() {
        let editor = makeEditor()
        editor.textView.setSelectedRange(NSRange(location: 10, length: 0))
        #expect(editor.textView.selectedRange() == NSRange(location: 7, length: 8))

        editor.textView.deleteBackward(nil)

        #expect(editor.textView.string == "Before  after")
        #expect(editor.coordinator.lastComputedStorage == "Before  after")
        #expect(editor.textView.selectedRange() == NSRange(location: 7, length: 0))
    }

    @Test("clicking a wiki link navigates even when the editor has a caret")
    func clickAlwaysNavigates() async throws {
        let editor = makeEditor()
        editor.textView.setSelectedRange(NSRange(location: 2, length: 0))
        let link = try #require(
            editor.textView.textStorage?.attribute(
                .link,
                at: 9,
                effectiveRange: nil
            )
        )

        #expect(
            editor.coordinator.textView(
                editor.textView,
                clickedOnLink: link,
                at: 9
            )
        )
        await Task.yield()

        #expect(editor.navigation.target == "note-id")
        #expect(editor.textView.selectedRange() == NSRange(location: 2, length: 0))
    }

    @Test("an unfinished wiki-link keeps completion open at its chosen end")
    func unfinishedWikiLinkKeepsCompletionOpen() {
        let editor = makeEditor(source: "Before [[Target")
        editor.textView.setSelectedRange(NSRange(location: 15, length: 0))

        #expect(editor.coordinator.textView(
            editor.textView,
            shouldChangeTextIn: NSRange(location: 8, length: 0),
            replacementString: "["
        ))
        let parsed = editor.coordinator.parsedDocument(for: editor.textView.string)
        let context = editor.coordinator.inlineTokenContext(
            at: 15,
            parsed: parsed,
            codeTokens: parsed.codeTokens,
            text: editor.textView.string as NSString
        )

        #expect(editor.textView.string == "Before [[Target")
        #expect(editor.textView.selectedRange() == NSRange(location: 15, length: 0))
        guard case .wikiLink(let token) = context else {
            Issue.record("Expected an unfinished wiki-link context")
            return
        }
        let displayRange = editor.coordinator.selectionDisplayRange(for: token, openingMarkerLength: 2)
        #expect((editor.textView.string as NSString).substring(with: displayRange) == "[[Target")
    }

    @Test("typing double opening brackets does not auto-pair them")
    func typedDoubleOpeningBracketsStayOpen() {
        let editor = makeEditor(source: "Before")
        editor.textView.setSelectedRange(NSRange(location: 6, length: 0))

        editor.textView.insertText("[", replacementRange: editor.textView.selectedRange())
        editor.textView.insertText("[", replacementRange: editor.textView.selectedRange())

        #expect(editor.textView.string == "Before[[")
        #expect(editor.textView.selectedRange() == NSRange(location: 8, length: 0))
    }

    @Test("typing an opening bracket wraps a text selection in an editable link")
    func openingBracketWrapsSelection() {
        let editor = makeEditor(source: "Before target after")
        editor.textView.setSelectedRange(NSRange(location: 7, length: 6))

        #expect(!editor.coordinator.textView(
            editor.textView,
            shouldChangeTextIn: NSRange(location: 7, length: 6),
            replacementString: "["
        ))
        #expect(editor.textView.string == "Before [[target after")
        #expect(editor.textView.selectedRange() == NSRange(location: 15, length: 0))
    }

    @Test("typing closing brackets reports the completed wiki link")
    func closingBracketsReportCompletion() async {
        let editor = makeEditor(source: "Before [[Target")
        var completion: WikiLinkCompletion?
        editor.coordinator.onWikiLinkCompletion = { completion = $0 }
        editor.textView.setSelectedRange(NSRange(location: 15, length: 0))

        #expect(editor.coordinator.textView(
            editor.textView,
            shouldChangeTextIn: NSRange(location: 15, length: 0),
            replacementString: "]]"
        ))
        editor.textView.textStorage?.replaceCharacters(
            in: NSRange(location: 15, length: 0),
            with: "]]"
        )
        editor.textView.setSelectedRange(NSRange(location: 17, length: 0))
        editor.textView.didChangeText()
        await Task.yield()

        #expect(completion?.selection.placeholder == "[[Target]]")
    }

    @Test("editable links use a pointing-hand cursor")
    func editableLinkCursor() throws {
        let editor = makeEditor()
        let linkPoint = try point(in: editor.textView, at: 9)
        let prosePoint = try point(in: editor.textView, at: 2)

        #expect(
            editor.textView.textCursorOverride(at: linkPoint)
                === NSCursor.pointingHand
        )
        #expect(editor.textView.textCursorOverride(at: prosePoint) == nil)

        editor.textView.isEditable = false
        #expect(
            editor.textView.textCursorOverride(at: prosePoint)
                === NSCursor.arrow
        )
    }

    @Test("wiki-link hover exposes the target and exact native anchor")
    func wikiLinkHoverGeometry() throws {
        let editor = makeEditor()
        let linkPoint = try point(in: editor.textView, at: 9)
        let prosePoint = try point(in: editor.textView, at: 2)

        let hit = try #require(editor.textView.wikiLinkHoverHit(at: linkPoint))
        #expect(hit.target == "note-id")
        #expect(hit.range == NSRange(location: 9, length: 4))
        #expect(hit.anchorRect.width > 0)
        #expect(hit.anchorRect.height > 0)
        #expect(editor.textView.wikiLinkHoverHit(at: prosePoint) == nil)
    }

    @Test("web links keep their hand cursor without requesting a note preview")
    func webLinksDoNotPreview() throws {
        let editor = makeEditor(source: "Before [Site](example.com) after")
        let siteLocation = (editor.textView.string as NSString).range(of: "Site").location
        let point = try point(in: editor.textView, at: siteLocation)

        #expect(editor.textView.textCursorOverride(at: point) === NSCursor.pointingHand)
        #expect(editor.textView.wikiLinkHoverHit(at: point) == nil)
    }

    @Test("muted completed-task links stay atomic, clickable, and use a pointing-hand cursor")
    func mutedCompletedTaskLinkInteractions() async throws {
        let editor = makeEditor(
            source: "- [x] [[Note|note-id]] after",
            completedTaskTextColor: .secondaryLabelColor
        )
        let nameLocation = (editor.textView.string as NSString).range(of: "Note").location
        let mutedLink = try #require(
            editor.textView.textStorage?.attribute(
                .mutedLink,
                at: nameLocation,
                effectiveRange: nil
            )
        )

        #expect(
            editor.textView.textStorage?.attribute(
                .link,
                at: nameLocation,
                effectiveRange: nil
            ) == nil
        )
        #expect(
            editor.textView.textCursorOverride(
                at: try point(in: editor.textView, at: nameLocation)
            ) === NSCursor.pointingHand
        )

        editor.textView.setSelectedRange(NSRange(location: nameLocation, length: 0))
        #expect(editor.textView.selectedRange() == NSRange(location: 6, length: 8))

        #expect(
            editor.coordinator.textView(
                editor.textView,
                clickedOnLink: mutedLink,
                at: nameLocation
            )
        )
        await Task.yield()
        #expect(editor.navigation.target == "note-id")
    }

    @Test("an autocomplete draft remains editable")
    func draftRemainsEditable() {
        let editor = makeEditor()
        editor.coordinator.rebuildTextStorageAndStyle(
            editor.textView,
            from: "Draft [[]]"
        )

        editor.textView.setSelectedRange(NSRange(location: 8, length: 0))

        #expect(editor.textView.selectedRange() == NSRange(location: 8, length: 0))
        #expect(
            editor.coordinator.textView(
                editor.textView,
                shouldChangeTextIn: NSRange(location: 8, length: 0),
                replacementString: "N"
            )
        )
    }
}

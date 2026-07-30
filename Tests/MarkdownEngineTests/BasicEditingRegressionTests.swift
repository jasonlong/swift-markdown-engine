import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("Basic editing regressions", .serialized)
struct BasicEditingRegressionTests {
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
        let layoutBridge: LayoutBridge
    }

    private func makeEditor(
        text: String,
        fontName: String = "SF Pro",
        fontSize: CGFloat = 16
    ) -> EditorStack {
        _ = NSApplication.shared
        let scrollView = ClampedScrollView(
            frame: NSRect(x: 0, y: 0, width: 600, height: 800)
        )
        scrollView.fitsContent = true

        let textView = NativeTextView(frame: .zero)
        var configuration = MarkdownEditorConfiguration.default
        configuration.heightBehavior = .fitsContent
        textView.configuration = configuration
        textView.baseFont =
            NSFont(name: fontName, size: fontSize)
            ?? .systemFont(ofSize: fontSize)
        textView.font = textView.baseFont
        textView.isEditable = true
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false

        let coordinator = NativeTextViewCoordinator(
            text: .constant(text),
            fontName: fontName,
            fontSize: fontSize,
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

    @Test("List controls center on the font's cap-height body")
    func listControlsUseCapHeightCenter() {
        let font = NSFont.systemFont(ofSize: 15)
        let baselineY: CGFloat = 100

        #expect(
            MarkdownListMarkerGeometry.centerY(
                forBaseline: baselineY,
                font: font
            ) == baselineY - font.capHeight / 2
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

    @Test("Backspace at a task item start demotes the task to a plain bullet")
    func backspaceDemotesTaskItem() {
        let stack = makeEditor(text: "first\n- [ ] second")
        stack.textView.setSelectedRange(NSRange(location: 12, length: 0))

        // First Backspace removes only the `[ ] ` checkbox, keeping the bullet.
        #expect(stack.coordinator.textView(
            stack.textView,
            doCommandBy: #selector(NSResponder.deleteBackward(_:))
        ))
        #expect(stack.textView.string == "first\n- second")
        #expect(stack.textView.selectedRange() == NSRange(location: 8, length: 0))

        // A second Backspace removes the bare bullet and joins the previous line.
        #expect(stack.coordinator.textView(
            stack.textView,
            doCommandBy: #selector(NSResponder.deleteBackward(_:))
        ))
        #expect(stack.textView.string == "firstsecond")
        #expect(stack.textView.selectedRange() == NSRange(location: 5, length: 0))
    }

    @Test("Typing task text does not restyle its checkbox prefix")
    func typingTaskTextLeavesCheckboxPrefixRendered() throws {
        let text = "- [ ] task"
        let stack = makeEditor(text: text)
        var configuration = stack.textView.configuration
        configuration.taskCheckbox.showsListBullet = true
        stack.textView.configuration = configuration
        stack.coordinator.configuration = configuration
        stack.coordinator.rebuildTextStorageAndStyle(stack.textView, from: text)

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

        stack.textView.setSelectedRange(
            NSRange(location: (text as NSString).length, length: 0)
        )
        stack.textView.insertText(
            "x",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        let checkboxPrefix = NSRange(location: 0, length: 5)
        #expect(
            recorder.attributeEditRanges.allSatisfy {
                NSIntersectionRange($0, checkboxPrefix).length == 0
            },
            "Unchanged checkbox prefix was invalidated: \(recorder.attributeEditRanges)"
        )
        #expect(storage.attribute(.taskCheckbox, at: 2, effectiveRange: nil) != nil)
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

    @Test("A fit-content editor remeasures after final-list-line layout settles")
    func finalListLineRemainsVisibleAfterEditing() async throws {
        let text = """
            - [[Fickwood Plumbing]] came out and installed the garbage disposal but they couldn’t do the fridge water line because the shut-off valve to the house is ancient and will probably break if they turn it.
            \t- We need to coordinate with the city to have them shut the water off at the street and have the plumbers come back and replace the shut-off valve. *Then* they can install the new water line.
            - Making good progress on Nook. Editor mostly works now. Also backlinks and a page for all notes.
            - Testing
            """
        let stack = makeEditor(text: text, fontName: "Geist-Regular", fontSize: 15)
        var configuration = stack.textView.configuration
        configuration.lists.firstLevelIndent = 0
        configuration.lists.indentPerLevel = 32
        configuration.lists.markerContentGap = 8
        configuration.lists.nestedBlankLineHeightScale = 0.05
        stack.textView.configuration = configuration
        stack.coordinator.configuration = configuration
        stack.coordinator.rebuildTextStorageAndStyle(stack.textView, from: text)
        stack.textView.pendingFullLayoutMeasure = false
        stack.textView.setSelectedRange(
            NSRange(location: (stack.textView.string as NSString).length, length: 0)
        )

        stack.textView.insertText(
            "x",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        #expect(stack.textView.pendingFitContentRemeasure)
        try await Task.sleep(for: .milliseconds(20))
        #expect(!stack.textView.pendingFitContentRemeasure)

        let textLayoutManager = try #require(stack.textView.textLayoutManager)
        let documentEnd = textLayoutManager.documentRange.endLocation
        textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)
        var finalSegmentMaxY: CGFloat = 0
        textLayoutManager.enumerateTextSegments(
            in: NSTextRange(location: documentEnd),
            type: .standard,
            options: []
        ) { _, segmentFrame, _, _ in
            finalSegmentMaxY = max(finalSegmentMaxY, segmentFrame.maxY)
            return true
        }

        #expect(finalSegmentMaxY > 0)
        #expect(stack.textView.frame.height >= finalSegmentMaxY)
    }

    @Test(
        "An empty-document prefix stays virtual until the first insertion",
        arguments: ["Geist-Regular", "Geist-Light", "SF Pro"]
    )
    func emptyDocumentPrefixMaterializesOnFirstEdit(fontName: String) throws {
        let stack = makeEditor(text: "", fontName: fontName, fontSize: 15)
        stack.textView.emptyDocumentPrefix = "- "
        stack.textView.setPlaceholder(nil)
        stack.textView.setSelectedRange(NSRange(location: 0, length: 0))

        #expect(stack.textView.string.isEmpty)
        #expect(stack.textView.placeholderView != nil)
        let metrics = try #require(stack.textView.virtualListPlaceholderMetrics)
        let font = stack.textView.baseFont
        let expectedContentX =
            (stack.textView.textContainer?.lineFragmentPadding ?? 0)
            + stack.textView.configuration.lists.firstLevelIndent
            + ("- " as NSString).size(withAttributes: [.font: font]).width
            + stack.textView.configuration.lists.markerContentGap
        #expect(metrics.contentX == expectedContentX)
        #expect(metrics.dotDiameter == MarkdownListMarkerGeometry.dotDiameter(for: font))
        let expectedBaseline = MarkdownListMarkerGeometry.listBaselineY(for: font)
        #expect(
            metrics.bulletCenter.y
                == MarkdownListMarkerGeometry.centerY(
                    forBaseline: expectedBaseline,
                    font: font
                )
        )
        let virtualCenter = metrics.bulletCenter

        stack.textView.insertText(
            "First item",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        #expect(stack.textView.string == "- First item")
        #expect(stack.textView.selectedRange() == NSRange(location: 12, length: 0))

        let textLayoutManager = try #require(stack.textView.textLayoutManager)
        let contentStorage = try #require(
            textLayoutManager.textContentManager as? NSTextContentStorage
        )
        var renderedCenter: CGPoint?
        textLayoutManager.enumerateTextLayoutFragments(
            from: textLayoutManager.documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            let fragmentStart = contentStorage.offset(
                from: contentStorage.documentRange.location,
                to: fragment.rangeInElement.location
            )
            guard fragmentStart == 0, let line = fragment.textLineFragments.first else {
                return true
            }
            let markerPosition = line.locationForCharacter(at: 0)
            let lineBounds = line.typographicBounds
            let baselineY =
                fragment.layoutFragmentFrame.minY
                + lineBounds.minY
                + markerPosition.y
            let markerWidth = ("-" as NSString).size(
                withAttributes: [.font: font]
            ).width
            renderedCenter = CGPoint(
                x: fragment.layoutFragmentFrame.minX
                    + lineBounds.minX
                    + markerPosition.x
                    + markerWidth / 2,
                y: MarkdownListMarkerGeometry.centerY(
                    forBaseline: baselineY,
                    font: font
                )
            )
            return false
        }
        let resolvedRenderedCenter = try #require(renderedCenter)
        #expect(
            abs(resolvedRenderedCenter.y - virtualCenter.y) < 0.01,
            "Rendered \(resolvedRenderedCenter.y), virtual \(virtualCenter.y)"
        )
        #expect(abs(resolvedRenderedCenter.x - virtualCenter.x) < 0.01)
    }
}

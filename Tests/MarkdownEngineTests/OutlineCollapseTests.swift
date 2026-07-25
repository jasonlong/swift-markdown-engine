import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

private final class TestOutlineStateStore: OutlineStateStore, @unchecked Sendable {
    var itemsByDocument: [String: Set<OutlineItemReference>] = [:]

    func collapsedItems(for documentID: String) -> Set<OutlineItemReference> {
        itemsByDocument[documentID] ?? []
    }

    func replaceCollapsedItems(
        _ items: Set<OutlineItemReference>,
        for documentID: String
    ) {
        itemsByDocument[documentID] = items
    }
}

@MainActor
@Suite("Outline collapse presentation")
struct OutlineCollapseTests {
    @Test("task parents collapse when their list bullet is visible")
    func taskParentCollapses() throws {
        let text = "- [ ] parent\n\t- child\n"
        let parent = try #require(OutlineListModel.items(in: text).first)
        let store = TestOutlineStateStore()
        store.itemsByDocument["doc"] = [parent.reference]
        var configuration = MarkdownEditorConfiguration.default
        configuration.services.outlineState = store
        configuration.taskCheckbox.showsListBullet = true
        let coordinator = NativeTextViewCoordinator(
            text: .constant(text),
            fontName: "SF Pro",
            fontSize: 16,
            isWikiLinkActive: .constant(false),
            onLinkClick: nil,
            onInlineSelectionChange: nil
        )
        coordinator.documentId = "doc"
        coordinator.configuration = configuration
        let textView = NativeTextView(frame: .zero)
        textView.configuration = configuration

        coordinator.rebuildTextStorageAndStyle(textView, from: text)

        #expect(
            textView.textStorage?.attribute(
                .outlineCollapsed,
                at: parent.markerRange.location,
                effectiveRange: nil
            ) as? Bool == true
        )
    }

    @Test("persisted parents hide descendants without changing source")
    func persistedCollapseIsPresentationOnly() throws {
        let text = "- parent\n\t- child\n- next\n"
        let outlineItems = OutlineListModel.items(in: text)
        let parent = try #require(outlineItems.first)
        let child = try #require(outlineItems.dropFirst().first)
        let store = TestOutlineStateStore()
        store.itemsByDocument["doc"] = [parent.reference]
        var configuration = MarkdownEditorConfiguration.default
        configuration.services.outlineState = store
        let coordinator = NativeTextViewCoordinator(
            text: .constant(text),
            fontName: "SF Pro",
            fontSize: 16,
            isWikiLinkActive: .constant(false),
            onLinkClick: nil,
            onInlineSelectionChange: nil
        )
        coordinator.documentId = "doc"
        coordinator.configuration = configuration
        let textView = NativeTextView(frame: .zero)
        textView.configuration = configuration

        coordinator.rebuildTextStorageAndStyle(textView, from: text)

        #expect(textView.string == text)
        #expect(
            textView.textStorage?.attribute(
                .outlineCollapsed,
                at: parent.markerRange.location,
                effectiveRange: nil
            ) as? Bool == true
        )
        #expect(
            textView.textStorage?.attribute(
                .outlineHidden,
                at: child.markerRange.location,
                effectiveRange: nil
            ) as? Bool == true
        )
    }

    @Test("loose nested lists remain one collapsible outline")
    func looseNestedListsCollapseTogether() throws {
        let text = """
            + parent
              - section

                - [ ] first

                - [ ] second

              - sibling
            - next
            """
        let outlineItems = OutlineListModel.items(in: text)
        let parent = try #require(outlineItems.first)
        let section = try #require(outlineItems.dropFirst().first)
        let firstTask = try #require(outlineItems.dropFirst(2).first)
        let sibling = try #require(outlineItems.dropFirst(4).first)

        #expect(parent.hasChildren)
        #expect(section.hasChildren)
        #expect(parent.descendantRange.map {
            NSLocationInRange(firstTask.markerRange.location, $0)
                && NSLocationInRange(sibling.markerRange.location, $0)
        } == true)
        #expect(section.descendantRange.map {
            NSLocationInRange(firstTask.markerRange.location, $0)
                && !NSLocationInRange(sibling.markerRange.location, $0)
        } == true)

        let store = TestOutlineStateStore()
        store.itemsByDocument["doc"] = [parent.reference]
        var configuration = MarkdownEditorConfiguration.default
        configuration.services.outlineState = store
        let coordinator = NativeTextViewCoordinator(
            text: .constant(text),
            fontName: "SF Pro",
            fontSize: 16,
            isWikiLinkActive: .constant(false),
            onLinkClick: nil,
            onInlineSelectionChange: nil
        )
        coordinator.documentId = "doc"
        coordinator.configuration = configuration
        let textView = NativeTextView(frame: .zero)
        textView.configuration = configuration

        coordinator.rebuildTextStorageAndStyle(textView, from: text)

        #expect(
            textView.textStorage?.attribute(
                .outlineHidden,
                at: firstTask.markerRange.location,
                effectiveRange: nil
            ) as? Bool == true
        )
        #expect(
            textView.textStorage?.attribute(
                .outlineHidden,
                at: sibling.markerRange.location,
                effectiveRange: nil
            ) as? Bool == true
        )
    }

    @Test("expanding a loose collapsed outline restores its descendants")
    func expandingLooseOutlineRestoresDescendants() throws {
        let text = """
            + Toledo stuff
              - Clothes

                - [ ] blazer

              - [x] charge drill battery
            - next
        """
        let outlineItems = OutlineListModel.items(in: text)
        let parent = try #require(outlineItems.first)
        let child = try #require(outlineItems.dropFirst().first)
        let grandchild = try #require(outlineItems.dropFirst(2).first)
        let siblingAfterCollapsedChild = try #require(
            outlineItems.dropFirst(3).first
        )
        let store = TestOutlineStateStore()
        store.itemsByDocument["daily/2026-07-23.md"] = [
            parent.reference,
            child.reference,
        ]
        var configuration = MarkdownEditorConfiguration.default
        configuration.services.outlineState = store
        configuration.taskCheckbox.showsListBullet = true
        let coordinator = NativeTextViewCoordinator(
            text: .constant(text),
            fontName: "SF Pro",
            fontSize: 16,
            isWikiLinkActive: .constant(false),
            onLinkClick: nil,
            onInlineSelectionChange: nil
        )
        coordinator.documentId = "daily/2026-07-23.md"
        coordinator.configuration = configuration
        let textView = NativeTextView(frame: .zero)
        textView.configuration = configuration

        coordinator.rebuildTextStorageAndStyle(textView, from: text)
        #expect(
            textView.textStorage?.attribute(
                .outlineHidden,
                at: child.markerRange.location,
                effectiveRange: nil
            ) as? Bool == true
        )

        #expect(
            coordinator.toggleOutlineItem(
                at: parent.markerRange.location,
                in: textView
            )
        )
        #expect(
            store.itemsByDocument["daily/2026-07-23.md"]
                == [child.reference]
        )
        #expect(
            textView.textStorage?.attribute(
                .outlineHidden,
                at: child.markerRange.location,
                effectiveRange: nil
            ) == nil
        )
        #expect(
            textView.textStorage?.attribute(
                .outlineCollapsed,
                at: child.markerRange.location,
                effectiveRange: nil
            ) as? Bool == true
        )
        #expect(
            textView.textStorage?.attribute(
                .outlineHidden,
                at: grandchild.markerRange.location,
                effectiveRange: nil
            ) as? Bool == true
        )
        #expect(
            textView.textStorage?.attribute(
                .outlineHidden,
                at: siblingAfterCollapsedChild.markerRange.location,
                effectiveRange: nil
            ) == nil
        )
        let siblingFont = try #require(
            textView.textStorage?.attribute(
                .font,
                at: siblingAfterCollapsedChild.markerRange.location,
                effectiveRange: nil
            ) as? NSFont
        )
        #expect(siblingFont.pointSize == 16)
        let restoredFont = try #require(
            textView.textStorage?.attribute(
                .font,
                at: child.markerRange.location,
                effectiveRange: nil
            ) as? NSFont
        )
        #expect(restoredFont.pointSize == 16)
        let childContentLocation = NSMaxRange(child.markerRange) + 1
        #expect(
            textView.textStorage?.attribute(
                .foregroundColor,
                at: childContentLocation,
                effectiveRange: nil
            ) as? NSColor != .clear
        )
    }
}

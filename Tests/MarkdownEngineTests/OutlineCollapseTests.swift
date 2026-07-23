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
}

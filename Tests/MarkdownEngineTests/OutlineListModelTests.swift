import Foundation
import Testing
@testable import MarkdownEngine

@Suite("Outline list model")
struct OutlineListModelTests {
    @Test("nested descendants stop at the next peer")
    func descendantRangesFollowIndentation() {
        let text = "- parent\n\t- child\n\t\t- grandchild\n\t- sibling\n- next\n"
        let items = OutlineListModel.items(in: text)

        #expect(items.count == 5)
        #expect(items[0].depth == 0)
        #expect(items[0].hasChildren)
        #expect(items[1].depth == 1)
        #expect(items[1].hasChildren)
        #expect(items[2].depth == 2)
        #expect(!items[2].hasChildren)
        #expect(items[3].depth == 1)
        #expect(!items[3].hasChildren)
        #expect(items[4].depth == 0)

        guard let parentRange = items[0].descendantRange,
              let childRange = items[1].descendantRange else {
            Issue.record("Expected parent and child descendant ranges")
            return
        }
        let parentDescendants = (text as NSString).substring(with: parentRange)
        #expect(parentDescendants == "\t- child\n\t\t- grandchild\n\t- sibling\n")
        let childDescendants = (text as NSString).substring(with: childRange)
        #expect(childDescendants == "\t\t- grandchild\n")
    }

    @Test("only plain unordered parents expose collapsible bullets")
    func collapsibleParentsExcludeTasksAndOrderedItems() {
        let text = "- parent\n\t- child\n- [ ] task\n\t- task child\n1. ordered\n\t- ordered child\n"
        let items = OutlineListModel.items(in: text)

        #expect(items[0].isBullet && items[0].hasChildren)
        #expect(!items[2].isBullet && items[2].hasChildren)
        #expect(!items[4].isBullet && items[4].hasChildren)
    }

    @Test("references are deterministic")
    func stableReferences() {
        let text = "- parent\n\t- child\n"
        let first = OutlineListModel.items(in: text)
        let second = OutlineListModel.items(in: text)

        #expect(first.map(\.reference) == second.map(\.reference))
    }
}

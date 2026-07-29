import Foundation
import Testing
@testable import MarkdownEngine

@Test func blockReferenceSyntaxOnlyRecognizesFullLines() {
    let source = "![[Weekly#^01hzy7vz8g4qj6m2n3r5t7w9xy]]\nprose [[Weekly#^01hzy7vz8g4qj6m2n3r5t7w9xy]]"
    let tokens = MarkdownBlockReferenceSyntax.tokens(in: source)
    #expect(tokens.count == 1)
    #expect(tokens.first?.kind == .transclusion)
    #expect(tokens.first?.noteTarget == "Weekly")
}

@Test func blockIDSuffixesAreHiddenAndProtectedWithoutCapturingOrdinaryCaretPositions() {
    let source = "- [ ] Ship it ^01hzy7vz8g4qj6m2n3r5t7w9xy\n"
    let range = try! #require(MarkdownBlockReferenceSyntax.protectedIDRanges(in: source).first)

    #expect((source as NSString).substring(with: range) == " ^01hzy7vz8g4qj6m2n3r5t7w9xy")
    #expect(MarkdownBlockReferenceSyntax.editIntersectsProtectedID(
        NSRange(location: range.location + 4, length: 1),
        in: source
    ))
    #expect(!MarkdownBlockReferenceSyntax.editIntersectsProtectedID(
        NSRange(location: range.location, length: 0),
        in: source
    ))
    #expect(!MarkdownBlockReferenceSyntax.editIntersectsProtectedID(
        NSRange(location: NSMaxRange(range), length: 0),
        in: source
    ))
}

@Test func sourceNavigationFindsTheLineContainingTheDurableID() {
    let source = "First\n- [ ] Ship it ^01hzy7vz8g4qj6m2n3r5t7w9xy\nLast\n"
    let range = MarkdownBlockReferenceSyntax.lineRange(
        forBlockID: "01hzy7vz8g4qj6m2n3r5t7w9xy",
        in: source
    )
    #expect((source as NSString).substring(with: try! #require(range)) == "- [ ] Ship it ^01hzy7vz8g4qj6m2n3r5t7w9xy")
}

@Test func transclusionEditsAreRejectedButBlockLinksRemainEditable() {
    let transclusion = "![[Weekly#^01hzy7vz8g4qj6m2n3r5t7w9xy]]"
    let link = "[[Weekly#^01hzy7vz8g4qj6m2n3r5t7w9xy]]"
    #expect(MarkdownBlockReferenceSyntax.editIntersectsTransclusion(
        NSRange(location: 3, length: 0), in: transclusion
    ))
    #expect(!MarkdownBlockReferenceSyntax.editIntersectsTransclusion(
        NSRange(location: 3, length: 0), in: link
    ))
}

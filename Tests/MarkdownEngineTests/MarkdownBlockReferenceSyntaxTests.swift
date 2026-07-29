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

@Test func referenceNavigationFindsTheSelectedReferenceOccurrence() {
    let id = "01hzy7vz8g4qj6m2n3r5t7w9xy"
    let source = "![[Weekly#^\(id)]]\n![[Other#^\(id)]]\n"
    let range = MarkdownBlockReferenceSyntax.lineRange(
        forReferenceTo: "Other",
        blockID: id,
        in: source
    )
    #expect(try! #require(range).location == ("![[Weekly#^\(id)]]\n" as NSString).length)
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

@Test func transclusionRangesStayOnTheirLineAndLeaveCaretBoundariesEditable() {
    let token = "  ![[Weekly#^01hzy7vz8g4qj6m2n3r5t7w9xy]]  "
    let source = "\(token)\n\n"
    let range = try! #require(MarkdownBlockReferenceSyntax.tokens(in: source).first?.range)

    #expect((source as NSString).substring(with: range) == token)
    #expect(!MarkdownBlockReferenceSyntax.editIntersectsTransclusion(
        NSRange(location: range.location, length: 0),
        in: source
    ))
    #expect(!MarkdownBlockReferenceSyntax.editIntersectsTransclusion(
        NSRange(location: NSMaxRange(range), length: 0),
        in: source
    ))
    #expect(!MarkdownBlockReferenceSyntax.editIntersectsTransclusion(
        NSRange(location: (source as NSString).length, length: 0),
        in: source
    ))
}

@Test func blockReferenceDragOnlyRecognizesSourceListRows() {
    let source = "Intro\n- [ ] Ship it\n2. Follow up\nPlain text"
    let task = try! #require(MarkdownBlockReferenceDragSyntax.sourceLineSelection(in: source, atUTF16: 8))
    let ordered = try! #require(MarkdownBlockReferenceDragSyntax.sourceLineSelection(in: source, atUTF16: 25))

    #expect((source as NSString).substring(with: NSRange(location: task.location, length: task.length)) == "- [ ] Ship it\n")
    #expect((source as NSString).substring(with: NSRange(location: ordered.location, length: ordered.length)) == "2. Follow up\n")
    #expect(MarkdownBlockReferenceDragSyntax.sourceLineSelection(in: source, atUTF16: 1) == nil)
    #expect(MarkdownBlockReferenceDragSyntax.sourceLineSelection(in: source, atUTF16: 40) == nil)
}

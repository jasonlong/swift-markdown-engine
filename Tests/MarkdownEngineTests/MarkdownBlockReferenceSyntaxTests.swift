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

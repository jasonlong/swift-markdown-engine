import Foundation

/// Immutable information about the location that opened an editor context
/// menu. Hosts can distinguish a rendered list affordance from ordinary text
/// without reproducing TextKit geometry or changing the current selection.
public struct MarkdownContextMenuTarget: Hashable, Sendable {
    /// AppKit's character index nearest the click.
    public let clickedCharacterIndex: Int
    /// The editor selection that was active when the menu opened.
    public let selection: NSRange
    /// The source line owning the rendered bullet or task checkbox that was
    /// clicked. `nil` means the click did not hit a rendered list marker.
    public let listMarkerLineRange: NSRange?

    public init(
        clickedCharacterIndex: Int,
        selection: NSRange,
        listMarkerLineRange: NSRange? = nil
    ) {
        self.clickedCharacterIndex = clickedCharacterIndex
        self.selection = selection
        self.listMarkerLineRange = listMarkerLineRange
    }

    public var isListMarker: Bool {
        listMarkerLineRange != nil
    }
}

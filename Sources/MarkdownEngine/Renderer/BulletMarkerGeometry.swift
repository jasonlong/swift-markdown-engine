import AppKit

enum BulletMarkerGeometry {
    static func dotDiameter(for font: NSFont) -> CGFloat {
        max(4.5, min(6, font.pointSize * 0.34))
    }

    /// Visual center of the font's upright letter body. Cap height keeps
    /// bullets and task controls aligned across families without a fixed
    /// per-font offset.
    static func centerY(forBaseline baselineY: CGFloat, font: NSFont) -> CGFloat {
        baselineY - font.capHeight / 2
    }

    /// Baseline produced by TextKit for a rendered list item's first line.
    /// List paragraphs use the font's natural line height with extra leading
    /// as lineSpacing (below the line), so the first baseline is AppKit's
    /// default baseline offset for the font.
    static func listBaselineY(for font: NSFont) -> CGFloat {
        NSLayoutManager().defaultBaselineOffset(for: font)
    }
}

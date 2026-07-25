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

    /// Baseline produced by TextKit for the fixed-height paragraph used by
    /// rendered list items. Font ascender/descender rounding differs by family,
    /// so derive it from AppKit's own default line and baseline metrics.
    static func listBaselineY(for font: NSFont, extraLineHeight: CGFloat) -> CGFloat {
        let naturalLineHeight = ceil(
            font.ascender - font.descender + font.leading
        )
        let listLineHeight = naturalLineHeight + extraLineHeight
        let layoutManager = NSLayoutManager()
        return layoutManager.defaultBaselineOffset(for: font)
            + listLineHeight
            - layoutManager.defaultLineHeight(for: font)
    }
}

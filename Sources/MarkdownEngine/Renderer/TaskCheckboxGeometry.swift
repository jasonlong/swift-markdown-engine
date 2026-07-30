//
//  TaskCheckboxGeometry.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 09.07.26.
//
//  Shared geometry for the drawn task-checkbox square. The hidden `[ ] ` chars
//  are collapsed to ~zero advance by the styler, so `drawPosition`/
//  `boundingRect` of the box range sit at the task CONTENT's left edge. The
//  square is right-aligned to that edge with a small gap (Obsidian-style),
//  occupying the `- ` marker slot. Fragment draw and click hit-test both use
//  these functions so their rects can't drift apart.
//

import AppKit

enum TaskCheckboxGeometry {

    /// Side length of the square for the given body font and configured scale.
    static func size(for font: NSFont, scale: CGFloat = 1) -> CGFloat {
        let ascent = max(0, font.ascender)
        let descent = max(0, -font.descender)
        let fontHeight = max(1, ceil(ascent + descent))
        let markerWidth = ("[ ]" as NSString).size(withAttributes: [.font: font]).width
        let baseSize = max(1.0, min(floor(fontHeight * 1.2), floor(markerWidth * 1.2)))
        return baseSize * max(0.5, min(2, scale))
    }

    /// Left edge of the square: right-aligned to the content start x with the configured gap.
    static func boxX(contentX: CGFloat, size: CGFloat, gap: CGFloat) -> CGFloat {
        contentX - size - gap
    }

    /// Top edge of a square centered on the same first-line visual center used
    /// by bullet markers. Using the font's full ascender/descender bounds here
    /// makes task controls drift relative to bullets for fonts such as SF Pro.
    static func boxY(baselineY: CGFloat, font: NSFont, size: CGFloat) -> CGFloat {
        MarkdownListMarkerGeometry.centerY(
            forBaseline: baselineY,
            font: font
        ) - size / 2
    }
}

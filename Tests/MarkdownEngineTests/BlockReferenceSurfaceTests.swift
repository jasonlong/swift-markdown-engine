import AppKit
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("Block reference host surfaces")
struct BlockReferenceSurfaceTests {
    private final class ProofSurface: NSView {
        static let color = NSColor(calibratedRed: 0.91, green: 0.11, blue: 0.37, alpha: 1)

        override func draw(_ dirtyRect: NSRect) {
            Self.color.setFill()
            NSBezierPath(rect: bounds).fill()
        }
    }

    @Test("a host surface is attached and visibly painted above its preserved token")
    func hostSurfaceIsVisibleWithoutReplacingTextStorage() throws {
        _ = NSApplication.shared
        let source = "![[Weekly#^01hzy7vz8g4qj6m2n3r5t7w9xy]]"
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 220))
        let scrollView = NSScrollView(frame: root.bounds)
        let container = NativeTextViewContainer(frame: root.bounds)
        let textView = NativeTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 220))
        root.addSubview(scrollView)
        container.textView = textView
        container.addSubview(textView)
        scrollView.documentView = container
        textView.string = source
        let layoutBridge = LayoutBridge(try #require(textView.textLayoutManager))
        textView.layoutBridge = layoutBridge
        textView.blockReferencePresentationProvider = { _ in
            MarkdownBlockReferencePresentation(
                state: .resolved,
                sourceLabel: "Weekly",
                markdown: "- [ ] Ship the release",
                isTaskComplete: false
            )
        }
        textView.blockReferenceSurfaceProvider = { _, _, _ in
            MarkdownBlockReferenceSurface(view: ProofSurface(), height: 72)
        }

        root.layoutSubtreeIfNeeded()
        textView.updateBlockReferenceSurfaces()
        root.layoutSubtreeIfNeeded()

        let surface = try #require(textView.blockReferenceSurfaceViews.first as? ProofSurface)
        #expect(surface.superview === container)
        #expect(surface.frame.width > 300)
        #expect(surface.frame.height == 72)
        #expect(textView.string == source)

        let rep = try #require(root.bitmapImageRepForCachingDisplay(in: root.bounds))
        root.cacheDisplay(in: root.bounds, to: rep)
        let center = surface.convert(
            NSPoint(x: surface.bounds.midX, y: surface.bounds.midY),
            to: root
        )
        let x = Int(center.x.rounded())
        let y = Int(center.y.rounded())
        let direct = rep.colorAt(x: x, y: y)
        let flipped = rep.colorAt(x: x, y: Int(root.bounds.height.rounded()) - y)
        let painted = [direct, flipped].compactMap { $0 }.contains { color in
            color.redComponent > 0.7 && color.greenComponent < 0.3 && color.blueComponent < 0.5
        }
        #expect(painted)
    }
}

import AppKit
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("Block reference host surfaces")
struct BlockReferenceSurfaceTests {
    private final class ProofSurface:
        NSView,
        MarkdownBlockReferenceInteractiveView
    {
        static let color = NSColor(calibratedRed: 0.91, green: 0.11, blue: 0.37, alpha: 1)
        var interactionHandler:
            ((MarkdownBlockReferenceSurfaceInteraction) -> Void)?
        var selectionStates: [MarkdownBlockReferenceSelectionState] = []
        var deleteCount = 0

        override func draw(_ dirtyRect: NSRect) {
            Self.color.setFill()
            NSBezierPath(rect: bounds).fill()
        }

        func setBlockReferenceInteractionHandler(
            _ handler: (
                (MarkdownBlockReferenceSurfaceInteraction) -> Void
            )?
        ) {
            interactionHandler = handler
        }

        func setBlockReferenceSelectionState(
            _ state: MarkdownBlockReferenceSelectionState
        ) {
            selectionStates.append(state)
        }

        func performBlockReferenceDelete() {
            deleteCount += 1
        }
    }

    @Test("an unchanged copied surface stays mounted while later text is edited")
    func copiedSurfaceIsRetainedForLaterEdits() throws {
        _ = NSApplication.shared
        let reference = "![[Weekly#^01hzy7vz8g4qj6m2n3r5t7w9xy]]"
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 220))
        let scrollView = NSScrollView(frame: root.bounds)
        let container = NativeTextViewContainer(frame: root.bounds)
        let textView = NativeTextView(frame: root.bounds)
        root.addSubview(scrollView)
        container.textView = textView
        container.addSubview(textView)
        scrollView.documentView = container
        textView.string = "\(reference)\nA normal line"
        let layoutBridge = LayoutBridge(try #require(textView.textLayoutManager))
        textView.layoutBridge = layoutBridge
        textView.blockReferencePresentationProvider = { _ in
            MarkdownBlockReferencePresentation(
                state: .resolved,
                sourceLabel: "Weekly",
                markdown: "- Ship the release"
            )
        }
        var createdSurfaces = 0
        textView.blockReferenceSurfaceProvider = { _, _, _ in
            createdSurfaces += 1
            return MarkdownBlockReferenceSurface(view: ProofSurface(), height: 28)
        }

        root.layoutSubtreeIfNeeded()
        textView.updateBlockReferenceSurfaces()
        let originalSurface = try #require(textView.blockReferenceSurfaceViews.first as? ProofSurface)

        textView.string = "\(reference)\nA normal line edited"
        textView.updateBlockReferenceSurfaces()

        #expect(textView.blockReferenceSurfaceViews.first === originalSurface)
        #expect(originalSurface.superview === container)
        #expect(createdSurfaces == 1)
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
                isTaskComplete: false,
                referenceCount: 2
            )
        }
        textView.blockReferenceSurfaceProvider = { _, _, _ in
            MarkdownBlockReferenceSurface(view: ProofSurface(), height: 72)
        }
        textView.textStorage?.addAttribute(
            .link,
            value: "nook://reference",
            range: NSRange(location: 0, length: source.utf16.count)
        )

        root.layoutSubtreeIfNeeded()
        textView.updateBlockReferenceSurfaces()
        root.layoutSubtreeIfNeeded()

        let surface = try #require(textView.blockReferenceSurfaceViews.first as? ProofSurface)
        #expect(surface.superview === container)
        #expect(surface.frame.width > 300)
        #expect(surface.frame.height == 72)
        #expect(textView.string == source)
        #expect(textView.textStorage?.attribute(.link, at: 0, effectiveRange: nil) == nil)
        #expect(
            (textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
                == NSColor.clear
        )

        // Selection-only restyles can reapply link presentation without
        // changing the source. A second reconciliation must hide it again.
        textView.textStorage?.addAttributes(
            [.link: "nook://reference", .foregroundColor: NSColor.linkColor],
            range: NSRange(location: 0, length: source.utf16.count)
        )
        textView.updateBlockReferenceSurfaces()
        #expect(textView.textStorage?.attribute(.link, at: 0, effectiveRange: nil) == nil)
        #expect(
            (textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
                == NSColor.clear
        )
        #expect(
            textView.blockReferencePresentationProvider?(
                MarkdownBlockReferenceToken(
                    kind: .transclusion,
                    noteTarget: "Weekly",
                    blockID: "01hzy7vz8g4qj6m2n3r5t7w9xy",
                    range: NSRange(location: 0, length: source.utf16.count)
                )
            )?.referenceCount == 2
        )

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

        textView.removeBlockReferenceSurfaces()
        #expect(
            textView.textStorage?.attribute(.link, at: 0, effectiveRange: nil) as? String
                == "nook://reference"
        )
    }

    @Test("a legacy list-contained reference receives the same host surface")
    func listContainedReferenceIsRendered() throws {
        _ = NSApplication.shared
        let source =
            "  - [ ] ![[Weekly#^01hzy7vz8g4qj6m2n3r5t7w9xy]]"
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 120))
        let scrollView = NSScrollView(frame: root.bounds)
        let container = NativeTextViewContainer(frame: root.bounds)
        let textView = NativeTextView(frame: root.bounds)
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
                markdown: "- Source item"
            )
        }
        textView.blockReferenceSurfaceProvider = { _, _, _ in
            MarkdownBlockReferenceSurface(view: ProofSurface(), height: 28)
        }
        textView.textStorage?.addAttribute(
            .bulletMarker,
            value: true,
            range: NSRange(location: 2, length: 1)
        )
        textView.textStorage?.addAttribute(
            .taskCheckbox,
            value: false,
            range: NSRange(location: 4, length: 3)
        )
        textView.textStorage?.addAttribute(
            .listMarkerPrefix,
            value: true,
            range: NSRange(location: 0, length: 8)
        )

        root.layoutSubtreeIfNeeded()
        textView.updateBlockReferenceSurfaces()
        root.layoutSubtreeIfNeeded()

        #expect(textView.blockReferenceSurfaceViews.count == 1)
        let token = try #require(
            MarkdownBlockReferenceSyntax.tokens(in: source).first
        )
        #expect(token.range == NSRange(
            location: 0,
            length: (source as NSString).length
        ))
        #expect(
            (textView.textStorage?.attribute(
                .foregroundColor,
                at: 0,
                effectiveRange: nil
            ) as? NSColor) == .clear
        )
        for key in [
            NSAttributedString.Key.bulletMarker,
            .taskCheckbox,
            .listMarkerPrefix,
        ] {
            #expect(
                textView.textStorage?.attribute(
                    key,
                    at: key == .taskCheckbox ? 4 : 2,
                    effectiveRange: nil
                ) == nil
            )
        }

        textView.removeBlockReferenceSurfaces()
        #expect(
            textView.textStorage?.attribute(
                .bulletMarker,
                at: 2,
                effectiveRange: nil
            ) as? Bool == true
        )
        #expect(
            textView.textStorage?.attribute(
                .taskCheckbox,
                at: 4,
                effectiveRange: nil
            ) as? Bool == false
        )
        #expect(
            textView.textStorage?.attribute(
                .listMarkerPrefix,
                at: 2,
                effectiveRange: nil
            ) as? Bool == true
        )
    }

    @Test("host interaction behaves like one atomic selectable node")
    func atomicSelectionAndOutlineCommands() throws {
        _ = NSApplication.shared
        let id = "01hzy7vz8g4qj6m2n3r5t7w9xy"
        let source = "\t![[Weekly#^\(id)]]"
        let root = NSView(
            frame: NSRect(x: 0, y: 0, width: 480, height: 180)
        )
        let window = NSWindow(
            contentRect: root.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = root
        let scrollView = NSScrollView(frame: root.bounds)
        let container = NativeTextViewContainer(frame: root.bounds)
        let textView = NativeTextView(frame: root.bounds)
        root.addSubview(scrollView)
        container.textView = textView
        container.addSubview(textView)
        scrollView.documentView = container
        textView.string = source
        textView.isEditable = true
        textView.isSelectable = true
        let bridge = LayoutBridge(
            try #require(textView.textLayoutManager)
        )
        textView.layoutBridge = bridge
        let surface = ProofSurface()
        textView.blockReferencePresentationProvider = { _ in
            MarkdownBlockReferencePresentation(
                state: .resolved,
                sourceLabel: "Weekly",
                markdown: "- [ ] Ship the release",
                isTaskComplete: false,
                referenceCount: 2
            )
        }
        textView.blockReferenceSurfaceProvider = { _, _, _ in
            MarkdownBlockReferenceSurface(
                view: surface,
                height: 32
            )
        }

        root.layoutSubtreeIfNeeded()
        textView.updateBlockReferenceSurfaces()
        let token = try #require(
            MarkdownBlockReferenceSyntax.tokens(in: source).first
        )
        let interact = try #require(surface.interactionHandler)

        interact(.placeCaretBefore)
        #expect(
            textView.selectedRange()
                == NSRange(location: token.range.location, length: 0)
        )
        #expect(surface.selectionStates.last == .caretBefore)

        interact(.select)
        #expect(textView.selectedRange() == token.range)
        #expect(surface.selectionStates.last == .selected)
        #expect(window.firstResponder === textView)

        interact(.placeCaretAfter)
        #expect(
            textView.selectedRange()
                == NSRange(
                    location: NSMaxRange(token.range),
                    length: 0
                )
        )
        #expect(surface.selectionStates.last == .caretAfter)

        #expect(
            textView.handleBlockReferenceCommand(.deleteBackward)
        )
        #expect(textView.selectedRange() == token.range)
        #expect(surface.selectionStates.last == .selected)
        #expect(
            textView.handleBlockReferenceCommand(.deleteBackward)
        )
        #expect(surface.deleteCount == 1)

        #expect(textView.handleBlockReferenceCommand(.indent))
        #expect(textView.string.hasPrefix("\t\t"))
        #expect(
            textView.handleBlockReferenceCommand(.outdent)
        )
        #expect(textView.string == source)

        let refreshed = try #require(
            MarkdownBlockReferenceSyntax.tokens(in: textView.string).first
        )
        textView.setSelectedRange(
            NSRange(location: refreshed.range.location, length: 0)
        )
        #expect(
            textView.handleBlockReferenceCommand(.deleteBackward)
        )
        #expect(!textView.string.hasPrefix("\t"))
        #expect(
            textView.selectedRange()
                == NSRange(location: 0, length: 0)
        )
        #expect(
            textView.handleBlockReferenceCommand(.deleteBackward)
        )
        #expect(textView.string.hasPrefix("![["))
    }

    @Test("a partial source selection expands to the whole atomic node")
    func partialSelectionExpands() throws {
        let source =
            "Before\n![[Weekly#^01hzy7vz8g4qj6m2n3r5t7w9xy]]\nAfter"
        let textView = NativeTextView(
            frame: NSRect(x: 0, y: 0, width: 480, height: 180)
        )
        textView.string = source
        let token = try #require(
            MarkdownBlockReferenceSyntax.tokens(in: source).first
        )
        textView.setSelectedRange(
            NSRange(location: token.range.location + 4, length: 3)
        )

        #expect(textView.redirectSelectionAroundBlockReference())
        #expect(textView.selectedRange() == token.range)
    }

    @Test("indentation preserves the selected duplicate occurrence")
    func duplicateReferenceIndentation() throws {
        _ = NSApplication.shared
        let id = "01hzy7vz8g4qj6m2n3r5t7w9xy"
        let reference = "![[Weekly#^\(id)]]"
        let source = "\(reference)\n\(reference)"
        let root = NSView(
            frame: NSRect(x: 0, y: 0, width: 480, height: 180)
        )
        let container = NativeTextViewContainer(frame: root.bounds)
        let textView = NativeTextView(frame: root.bounds)
        root.addSubview(container)
        container.textView = textView
        container.addSubview(textView)
        textView.string = source
        let layoutBridge = LayoutBridge(
            try #require(textView.textLayoutManager)
        )
        textView.layoutBridge = layoutBridge
        textView.blockReferencePresentationProvider = { _ in
            MarkdownBlockReferencePresentation(
                state: .resolved,
                sourceLabel: "Weekly",
                markdown: "- Ship the release"
            )
        }
        var surfaces: [ProofSurface] = []
        textView.blockReferenceSurfaceProvider = { _, _, _ in
            let surface = ProofSurface()
            surfaces.append(surface)
            return MarkdownBlockReferenceSurface(
                view: surface,
                height: 28
            )
        }

        root.layoutSubtreeIfNeeded()
        textView.updateBlockReferenceSurfaces()
        let originalTokens = MarkdownBlockReferenceSyntax.tokens(
            in: source
        )
        #expect(surfaces.count == 2)
        let second = try #require(surfaces.last)
        let initialHandler = try #require(second.interactionHandler)
        let originalSecondToken = try #require(originalTokens.last)
        initialHandler(.select)
        #expect(textView.selectedRange() == originalSecondToken.range)

        initialHandler(.indent)
        #expect(textView.string == "\(reference)\n\t\(reference)")
        let updatedTokens = MarkdownBlockReferenceSyntax.tokens(
            in: textView.string
        )
        let updatedFirstToken = try #require(updatedTokens.first)
        let updatedSecondToken = try #require(updatedTokens.last)
        #expect(textView.selectedRange() == updatedSecondToken.range)
        #expect(textView.selectedRange() != updatedFirstToken.range)
    }

    @Test("copied surface frames preserve source indentation")
    func copiedSurfaceFramesPreserveSourceIndentation() throws {
        _ = NSApplication.shared
        let id = "01hzy7vz8g4qj6m2n3r5t7w9xy"
        let reference = "![[Weekly#^\(id)]]"
        let source = "\(reference)\n\t\t\(reference)"
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 180))
        let container = NativeTextViewContainer(frame: root.bounds)
        let textView = NativeTextView(frame: root.bounds)
        root.addSubview(container)
        container.textView = textView
        container.addSubview(textView)
        textView.configuration.lists.indentPerLevel = 32
        textView.string = source
        let layoutBridge = LayoutBridge(
            try #require(textView.textLayoutManager)
        )
        textView.layoutBridge = layoutBridge
        textView.blockReferencePresentationProvider = { _ in
            MarkdownBlockReferencePresentation(
                state: .resolved,
                sourceLabel: "Weekly",
                markdown: "- Ship the release"
            )
        }
        var surfaces: [ProofSurface] = []
        textView.blockReferenceSurfaceProvider = { _, _, _ in
            let surface = ProofSurface()
            surfaces.append(surface)
            return MarkdownBlockReferenceSurface(view: surface, height: 24)
        }

        root.layoutSubtreeIfNeeded()
        textView.updateBlockReferenceSurfaces()

        #expect(surfaces.count == 2)
        let rootSurface = try #require(surfaces.first)
        let nestedSurface = try #require(surfaces.last)
        #expect(abs(nestedSurface.frame.minX - rootSurface.frame.minX - 64) < 1)
        #expect(abs(nestedSurface.frame.width - rootSurface.frame.width + 64) < 1)
    }

    @Test("copied surface markers use the native list marker columns")
    func copiedSurfaceMarkersAlignWithNativeListColumns() throws {
        _ = NSApplication.shared
        let id = "01hzy7vz8g4qj6m2n3r5t7w9xy"
        let reference = "![[Weekly#^\(id)]]"
        let source = "\(reference)\n\t\(reference)"
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 180))
        let container = NativeTextViewContainer(frame: root.bounds)
        let textView = NativeTextView(frame: root.bounds)
        root.addSubview(container)
        container.textView = textView
        container.addSubview(textView)
        textView.configuration.lists.firstLevelIndent = 28
        textView.configuration.lists.indentPerLevel = 32
        textView.string = source
        let bridge = LayoutBridge(
            try #require(textView.textLayoutManager)
        )
        textView.layoutBridge = bridge
        textView.blockReferencePresentationProvider = { _ in
            MarkdownBlockReferencePresentation(
                state: .resolved,
                sourceLabel: "Weekly",
                markdown: "- Source item"
            )
        }
        var surfaces: [ProofSurface] = []
        let markerCenterOffset: CGFloat = 15
        textView.blockReferenceSurfaceProvider = { _, _, _ in
            let surface = ProofSurface()
            surfaces.append(surface)
            return MarkdownBlockReferenceSurface(
                view: surface,
                height: 24,
                markerCenterOffset: markerCenterOffset
            )
        }

        root.layoutSubtreeIfNeeded()
        textView.updateBlockReferenceSurfaces()

        let markerWidth = ("-" as NSString).size(
            withAttributes: [.font: textView.baseFont]
        ).width
        let rootMarkerX = textView.frame.minX + textView.textContainerOrigin.x
            + 28 + markerWidth / 2
        let nestedMarkerX = rootMarkerX + 32
        let rootSurface = try #require(surfaces.first)
        let nestedSurface = try #require(surfaces.last)
        #expect(abs(rootSurface.frame.minX + markerCenterOffset - rootMarkerX) < 1)
        #expect(abs(nestedSurface.frame.minX + markerCenterOffset - nestedMarkerX) < 1)
    }

    @Test("copied surfaces reserve native list row spacing")
    func copiedSurfaceUsesNativeListRowMetrics() throws {
        _ = NSApplication.shared
        let source = "![[Weekly#^01hzy7vz8g4qj6m2n3r5t7w9xy]]"
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 180))
        let container = NativeTextViewContainer(frame: root.bounds)
        let textView = NativeTextView(frame: root.bounds)
        root.addSubview(container)
        container.textView = textView
        container.addSubview(textView)
        let font = NSFont.systemFont(ofSize: 16)
        textView.baseFont = font
        textView.font = font
        textView.configuration.lists.extraLineHeight = 3
        textView.configuration.paragraph.lineHeightExtraSpacing = 2
        textView.configuration.paragraph.spacingFactor = 0.3
        textView.string = source
        let bridge = LayoutBridge(try #require(textView.textLayoutManager))
        textView.layoutBridge = bridge
        textView.blockReferencePresentationProvider = { _ in
            MarkdownBlockReferencePresentation(
                state: .resolved,
                sourceLabel: "Weekly",
                markdown: "- Source item"
            )
        }
        textView.blockReferenceSurfaceProvider = { _, _, _ in
            MarkdownBlockReferenceSurface(view: ProofSurface(), height: 20)
        }

        root.layoutSubtreeIfNeeded()
        textView.updateBlockReferenceSurfaces()

        let paragraph = try #require(
            textView.textStorage?.attribute(
                .paragraphStyle,
                at: 0,
                effectiveRange: nil
            ) as? NSParagraphStyle
        )
        let naturalLineHeight = ceil(
            font.ascender - font.descender + font.leading
        )
        let expectedLineHeight = naturalLineHeight + 2
        #expect(paragraph.minimumLineHeight == expectedLineHeight)
        #expect(paragraph.maximumLineHeight == expectedLineHeight)
        #expect(paragraph.lineSpacing == 3)
        #expect(paragraph.paragraphSpacing == ceil(naturalLineHeight * 0.3))
        let surface = try #require(textView.blockReferenceSurfaceViews.first)
        #expect(surface.frame.height == expectedLineHeight)
    }

    @Test("native caret is suppressed at copied-node boundaries")
    func nativeCaretIsSuppressedAtCopiedNodeBoundaries() throws {
        let source = "![[Weekly#^01hzy7vz8g4qj6m2n3r5t7w9xy]]\nAfter"
        let textView = NativeTextView(frame: .zero)
        textView.string = source
        let token = try #require(
            MarkdownBlockReferenceSyntax.tokens(in: source).first
        )

        textView.setSelectedRange(
            NSRange(location: token.range.location, length: 0)
        )
        #expect(textView.shouldSuppressNativeInsertionPointForBlockReference())
        textView.setSelectedRange(
            NSRange(location: NSMaxRange(token.range), length: 0)
        )
        #expect(textView.shouldSuppressNativeInsertionPointForBlockReference())
        textView.setSelectedRange(
            NSRange(location: NSMaxRange(token.range) + 1, length: 0)
        )
        #expect(!textView.shouldSuppressNativeInsertionPointForBlockReference())
    }
}

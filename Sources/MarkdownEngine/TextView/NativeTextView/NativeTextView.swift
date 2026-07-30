//
//  NativeTextView.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 18.02.26.
//
//  AppKit `NSTextView` subclass used by the markdown editor. Stored state
//  lives here; behavior is split across `NativeTextView+<Feature>.swift`
//  files in this folder (frame & overscroll, caret workarounds, click remap,
//  paste handling, drag-select boost, task checkbox, spelling policy).
//
//  Bottom-overscroll math lives in `BottomOverscrollPolicy.swift`.
//  Pasteboard image inspection lives in `PasteboardImageReader.swift`.
//

import AppKit
import UniformTypeIdentifiers

final class NativeTextView: NSTextView {
    // MARK: Frame & overscroll state
    var baseContentHeight: CGFloat = 0
    var activeBottomOverscroll: CGFloat = 0
    var isApplyingManagedFrameSize = false
    /// Set on switch/resize to force full-layout height measurement until the cascade settles.
    var pendingFullLayoutMeasure = false
    /// Coalesces the post-edit fit-content remeasure that runs after TextKit
    /// settles paragraph spacing on the next main-loop pass.
    var pendingFitContentRemeasure = false
    /// Coalesces wide-table overlay updates to once per runloop (resize fires many per frame).
    var pendingWideTableOverlayUpdate = false
    var suppressAutoRevealOnce: Bool = false
    // Set by clickedOnLink during a mouseDown: did the delegate fire (so
    // mouseDown can re-dispatch a click AppKit dropped), and did it navigate
    // (so the pre-click caret is restored — a link click isn't caret placement).
    var linkClickDidFire = false
    var linkClickDidNavigate = false

    // MARK: Configuration
    var configuration: MarkdownEditorConfiguration = .default {
        didSet {
            overscrollPercent = configuration.overscroll.percent
            maxOverscrollPoints = configuration.overscroll.maxPoints
            minOverscrollPoints = configuration.overscroll.minPoints
        }
    }
    var overscrollPercent: CGFloat = MarkdownEditorConfiguration.default.overscroll.percent
    var maxOverscrollPoints: CGFloat = MarkdownEditorConfiguration.default.overscroll.maxPoints
    var minOverscrollPoints: CGFloat = MarkdownEditorConfiguration.default.overscroll.minPoints

    // MARK: Editor wiring
    var onPasteImage: ((NSPasteboard) -> String?)?
    var blockReferencePasteResult: ((NSPasteboard) -> MarkdownBlockReferencePasteResult)?
    var blockReferencePresentationProvider: ((MarkdownBlockReferenceToken) -> MarkdownBlockReferencePresentation?)?
    var blockReferenceSurfaceProvider: ((MarkdownBlockReferenceToken, MarkdownBlockReferencePresentation, CGFloat) -> MarkdownBlockReferenceSurface?)?
    var onBlockReferenceDrag: (@MainActor (MarkdownBlockReferenceDragSelection) async -> MarkdownBlockReferenceDragPayload?)?
    var onWikiLinkHover: ((WikiLinkHoverState?) -> Void)?
    var wikiLinkHoverTrackingArea: NSTrackingArea?
    var hoveredWikiLinkRange: NSRange?
    var hoveredWikiLinkTarget: String?
    weak var layoutBridge: LayoutBridge?
    var baseFont: NSFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)

    // MARK: Caret-workaround state
    var caretIndicatorObservation: NSKeyValueObservation?
    weak var observedCaretIndicator: NSView?
    var isApplyingCaretShift: Bool = false

    // MARK: Drag-select state
    var dragStartMouseScreenLoc: NSPoint?

    // MARK: Placeholder state
    /// Click-through ghost-text label shown while the document is empty;
    /// managed by `NativeTextView+Placeholder.swift`.
    weak var placeholderView: PlaceholderLabelView?
    /// Storage prefix materialized atomically with the first user insertion.
    /// Focus and caret movement leave it virtual.
    var emptyDocumentPrefix: String?

    // MARK: Cursor exclusion
    /// Embedder-supplied predicate that suppresses the I-beam cursor in edit mode.
    /// Called on every mouse-move with the event location in window coordinates.
    /// Return `true` to show the arrow cursor instead of the edit-mode I-beam.
    var isCursorExcluded: ((CGPoint) -> Bool)?

    // MARK: Wide-table overlay state
    /// Live NSScrollView per wide table; keyed by source-ID hash.
    var wideTableOverlays: [Int: WideTableOverlay] = [:]
    /// Persisted horizontal scroll offset per wide table; survives restyles.
    var tableHorizontalScrollOffsets: [Int: CGFloat] = [:]

    // MARK: Block-reference surface state
    /// Native host views attached as siblings above the text view. They are
    /// intentionally not text attachments: the canonical token stays in storage.
    var blockReferenceSurfaceViews: [NSView] = []
    struct MountedBlockReferenceSurface {
        let token: MarkdownBlockReferenceToken
        let presentation: MarkdownBlockReferencePresentation
        let view: NSView
        let height: CGFloat
        let markerCenterOffset: CGFloat?
        let availableWidth: CGFloat
        let fontName: String
        let fontSize: CGFloat
    }
    var mountedBlockReferenceSurfaces: [MountedBlockReferenceSurface] = []

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // Forward appearance changes to the embedder's highlighter via its registered notification.
        if let name = configuration.services.syntaxHighlighter.appearanceDidChangeNotification {
            NotificationCenter.default.post(name: name, object: self)
        }
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        // AppKit's normal hardware-key path can pair `[` before the delegate
        // sees the second bracket. Wiki links intentionally need an *open*
        // `[[` draft, so perform this insertion ourselves and let the delegate
        // decide whether a selected range should be wrapped.
        let insertedText: String? = (insertString as? String)
            ?? (insertString as? NSAttributedString)?.string
        // Certain input sources deliver AppKit's automatic pair as one
        // insertion (`[]`) rather than delivering the opening bracket alone.
        // Treat both forms as the literal `[` needed to begin a wiki-link
        // draft. This intentionally does not affect pasted text because this
        // override is only concerned with a zero-length interactive insertion.
        let range = replacementRange.location == NSNotFound
            ? selectedRange()
            : replacementRange
        if (insertedText == "[" || (insertedText == "[]" && range.length == 0)),
           !hasMarkedText(),
           !configuration.rawSourceMode {
            guard shouldChangeText(in: range, replacementString: "[") else {
                return
            }
            textStorage?.replaceCharacters(in: range, with: "[")
            setSelectedRange(NSRange(location: range.location + 1, length: 0))
            didChangeText()
            return
        }

        guard let prefix = emptyDocumentPrefix,
              !prefix.isEmpty,
              string.isEmpty else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }

        let effectiveRange = replacementRange.location == NSNotFound
            ? selectedRange()
            : replacementRange
        guard effectiveRange.location == 0, effectiveRange.length == 0 else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }

        if let attributed = insertString as? NSAttributedString, attributed.length > 0 {
            let prefixed = NSMutableAttributedString(
                string: prefix,
                attributes: typingAttributes
            )
            prefixed.append(attributed)
            super.insertText(prefixed, replacementRange: effectiveRange)
        } else if let inserted = insertString as? String, !inserted.isEmpty {
            super.insertText(prefix + inserted, replacementRange: effectiveRange)
        } else {
            super.insertText(insertString, replacementRange: replacementRange)
        }
    }

    // setMarkedText skips textDidChange, so restyle the marked paragraph to apply markdown attrs.
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        guard hasMarkedText(),
              let coord = delegate as? NativeTextViewCoordinator else { return }
        let marked = markedRange()
        guard marked.location != NSNotFound, marked.length > 0 else { return }
        // The composition mutated the storage without textDidChange, and
        // shouldChangeTextIn's own parse re-cached the PRE-edit string at the
        // current generation — bump so the restyle below reparses instead of
        // serving that stale document (same-length composition updates).
        coord.parseGeneration &+= 1
        // Census bookkeeping never saw this mutation → next census full-scans.
        coord.backtickCensusNeedsRescan = true
        let nsText = self.string as NSString
        let paragraph = nsText.paragraphRange(for: marked)
        coord.restyleParagraphs([paragraph], in: self)
    }

    deinit { caretIndicatorObservation?.invalidate() }
}

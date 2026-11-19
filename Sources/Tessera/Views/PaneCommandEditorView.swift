import AppKit
import SwiftUI

/// Native AppKit terminal command prompt modeled after Warp / zsh-syntax-highlighting:
/// - Sub-pixel-exact baseline alignment between `$` prompt gutter and command text
/// - Live, undo-safe shell syntax highlighting (verbs, flags, strings, operators, comments)
/// - Subtle active-line highlight when focused
/// - Zero smart-quote / smart-dash / spellcheck interference
/// - Instant click-to-type anywhere in the pane with zero animation jitter
struct PaneCommandEditorView: NSViewRepresentable {
    @Binding var commands: [String]
    var accentHex: String
    var placeholder: String = "Type command…"
    var fontSize: CGFloat = 12.0
    var darkSurface: Bool = true
    var onFocus: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> PaneCommandContainerView {
        let view = PaneCommandContainerView(
            text: Self.joinCommands(commands),
            accentColor: Self.nsColor(hex: accentHex),
            placeholder: placeholder,
            fontSize: fontSize,
            darkSurface: darkSurface,
            delegate: context.coordinator
        )
        context.coordinator.container = view
        context.coordinator.lastKnownCommands = commands
        view.onFocus = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onFocus?()
        }
        return view
    }

    func updateNSView(_ container: PaneCommandContainerView, context: Context) {
        context.coordinator.parent = self
        container.onFocus = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onFocus?()
        }
        container.updateAppearance(
            accentColor: Self.nsColor(hex: accentHex),
            placeholder: placeholder,
            fontSize: fontSize,
            darkSurface: darkSurface
        )

        // Only replace text when `commands` changed externally (e.g. switching panes/layouts or clicking a Library chip),
        // never on echo-back from the user's own keystrokes.
        if context.coordinator.lastKnownCommands != commands {
            let incoming = Self.joinCommands(commands)
            context.coordinator.lastKnownCommands = commands
            if container.textView.string != incoming {
                context.coordinator.isProgrammaticUpdate = true
                let wasFirstResponder = (container.window?.firstResponder === container.textView)
                container.textView.string = incoming
                container.textView.restyleAll()
                if wasFirstResponder {
                    let end = (incoming as NSString).length
                    container.textView.setSelectedRange(NSRange(location: end, length: 0))
                }
                container.gutterView.needsDisplay = true
                context.coordinator.isProgrammaticUpdate = false
            }
        }
    }

    static func joinCommands(_ commands: [String]) -> String {
        commands.joined(separator: "\n")
    }

    static func splitCommands(_ text: String) -> [String] {
        if text.isEmpty { return [] }
        return text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    static func nsColor(hex: String) -> NSColor {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        guard cleaned.count == 6 else {
            return NSColor(srgbRed: 0.39, green: 0.40, blue: 0.95, alpha: 1.0)
        }
        let r = CGFloat((int >> 16) & 0xFF) / 255.0
        let g = CGFloat((int >> 8) & 0xFF) / 255.0
        let b = CGFloat(int & 0xFF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PaneCommandEditorView
        weak var container: PaneCommandContainerView?
        var isProgrammaticUpdate = false
        var lastKnownCommands: [String] = []

        init(_ parent: PaneCommandEditorView) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.onFocus?()
            container?.textView.needsDisplay = true
            container?.gutterView.needsDisplay = true
        }

        func textDidEndEditing(_ notification: Notification) {
            container?.textView.needsDisplay = true
            container?.gutterView.needsDisplay = true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            container?.needsDisplay = true
            container?.textView.needsDisplay = true
            container?.gutterView.needsDisplay = true
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticUpdate,
                  let textView = notification.object as? PanePromptTextView else { return }
            textView.applyShellHighlighting()
            let parsed = PaneCommandEditorView.splitCommands(textView.string)
            lastKnownCommands = parsed
            if parent.commands != parsed {
                parent.commands = parsed
            }
            container?.needsDisplay = true
            textView.needsDisplay = true
            container?.gutterView.needsDisplay = true
        }
    }
}

final class PaneCommandContainerView: NSView {
    let gutterView = PromptSymbolGutterView()
    let scrollView = NSScrollView()
    let textView: PanePromptTextView
    var onFocus: (() -> Void)?

    private let gutterWidth: CGFloat = 20
    private var observers: [NSObjectProtocol] = []

    override var isFlipped: Bool { true }

    init(
        text: String,
        accentColor: NSColor,
        placeholder: String,
        fontSize: CGFloat,
        darkSurface: Bool,
        delegate: NSTextViewDelegate
    ) {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: NSSize(width: 300, height: 10_000_000))
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)

        textView = PanePromptTextView(
            frame: NSRect(x: 0, y: 0, width: 300, height: 120),
            textContainer: textContainer
        )

        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 120))

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsetsZero

        textView.delegate = delegate
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: 10_000_000, height: 10_000_000)

        textView.onBecomeFirstResponder = { [weak self] in
            self?.onFocus?()
            self?.needsDisplay = true
            self?.gutterView.needsDisplay = true
        }
        textView.onResignFirstResponder = { [weak self] in
            self?.needsDisplay = true
            self?.gutterView.needsDisplay = true
        }
        textView.onActiveLineChanged = { [weak self] in
            self?.needsDisplay = true
            self?.gutterView.needsDisplay = true
        }

        scrollView.documentView = textView

        gutterView.textView = textView
        addSubview(gutterView)
        addSubview(scrollView)

        updateAppearance(
            accentColor: accentColor,
            placeholder: placeholder,
            fontSize: fontSize,
            darkSurface: darkSurface
        )
        textView.string = text
        textView.restyleAll()

        scrollView.contentView.postsBoundsChangedNotifications = true
        let boundsObs = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.needsDisplay = true
            self?.gutterView.needsDisplay = true
        }
        let frameObs = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: textView,
            queue: .main
        ) { [weak self] _ in
            self?.needsDisplay = true
            self?.gutterView.needsDisplay = true
        }
        observers = [boundsObs, frameObs]
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Unified full-width Warp-style active-line pill spanning BOTH the `$` gutter and command text
        guard window?.firstResponder === textView,
              let lineRectInText = textView.activeLineRect() else { return }

        let yInSelf = convert(NSPoint(x: 0, y: lineRectInText.minY), from: textView).y
        // Center the pill symmetrically around the visible glyph ink (TextKit's lineHeightMultiple=1.22
        // places ~3px of leading above the glyphs, so shifting top down by +1.5 and bottom down by +1.5
        // centers both the text and the caret inside a 26pt tall pill with 3px clearance above/below).
        let pillRect = NSRect(
            x: 0,
            y: yInSelf - 1.5,
            width: bounds.width,
            height: lineRectInText.height + 5.0
        )
        guard pillRect.maxY >= 0 && pillRect.minY <= bounds.height else { return }

        let fillColor = textView.isDarkSurface
            ? NSColor(white: 1.0, alpha: 0.045)
            : textView.accentColor.withAlphaComponent(0.06)
        let borderColor = textView.isDarkSurface
            ? NSColor(white: 1.0, alpha: 0.08)
            : textView.accentColor.withAlphaComponent(0.15)

        let path = NSBezierPath(roundedRect: pillRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        fillColor.setFill()
        path.fill()
        borderColor.setStroke()
        path.lineWidth = 0.75
        path.stroke()
    }

    deinit {
        for obs in observers {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateAppearance(
        accentColor: NSColor,
        placeholder: String,
        fontSize: CGFloat,
        darkSurface: Bool
    ) {
        let changed = (textView.promptFontSize != fontSize)
            || (textView.isDarkSurface != darkSurface)
            || (textView.placeholderText != placeholder)
            || (textView.accentColor != accentColor)
        guard changed else { return }

        let needsRestyle = (textView.promptFontSize != fontSize) || (textView.isDarkSurface != darkSurface)
        textView.isDarkSurface = darkSurface

        if darkSurface {
            appearance = NSAppearance(named: .darkAqua)
            scrollView.appearance = NSAppearance(named: .darkAqua)
            textView.appearance = NSAppearance(named: .darkAqua)
            textView.inkColor = NSColor(srgbRed: 0.92, green: 0.94, blue: 0.98, alpha: 0.95)
            textView.placeholderColor = NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.28)
        } else {
            appearance = nil
            scrollView.appearance = nil
            textView.appearance = nil
            textView.inkColor = NSColor.labelColor
            textView.placeholderColor = NSColor.placeholderTextColor
        }

        textView.promptFontSize = fontSize
        textView.placeholderText = placeholder
        textView.accentColor = accentColor
        textView.insertionPointColor = accentColor
        textView.selectedTextAttributes = [
            .backgroundColor: accentColor.withAlphaComponent(0.32),
            .foregroundColor: textView.inkColor
        ]

        gutterView.accentColor = accentColor
        gutterView.fontSize = fontSize

        if needsRestyle {
            textView.restyleAll()
        }
        gutterView.needsDisplay = true
        textView.needsDisplay = true
    }

    override func layout() {
        super.layout()
        gutterView.frame = NSRect(x: 0, y: 0, width: gutterWidth, height: bounds.height)
        scrollView.frame = NSRect(
            x: gutterWidth,
            y: 0,
            width: max(0, bounds.width - gutterWidth),
            height: bounds.height
        )

        let contentSize = scrollView.contentSize
        textView.minSize = contentSize
        if textView.frame.width != contentSize.width {
            textView.setFrameSize(NSSize(width: contentSize.width, height: max(textView.frame.height, contentSize.height)))
        }
        gutterView.needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(textView)
        onFocus?()
        super.mouseDown(with: event)
    }
}

final class PanePromptTextView: NSTextView {
    static let lineHeightMultiple: CGFloat = 1.22

    var promptFontSize: CGFloat = 12.0
    var placeholderText: String = ""
    var isDarkSurface: Bool = true
    var inkColor: NSColor = .white
    var placeholderColor: NSColor = NSColor(white: 1.0, alpha: 0.28)
    var accentColor: NSColor = NSColor(srgbRed: 0.39, green: 0.40, blue: 0.95, alpha: 1.0)
    var onBecomeFirstResponder: (() -> Void)?
    var onResignFirstResponder: (() -> Void)?
    var onActiveLineChanged: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            onBecomeFirstResponder?()
            needsDisplay = true
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            onResignFirstResponder?()
            needsDisplay = true
        }
        return resigned
    }

    static func makeParagraphStyle() -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = lineHeightMultiple
        paragraph.lineBreakMode = .byWordWrapping
        return paragraph
    }

    private func baseAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: promptFontSize, weight: .regular),
            .foregroundColor: inkColor,
            .paragraphStyle: Self.makeParagraphStyle()
        ]
    }

    func restyleAll() {
        let attrs = baseAttributes()
        font = attrs[.font] as? NSFont
        textColor = inkColor
        defaultParagraphStyle = attrs[.paragraphStyle] as? NSParagraphStyle
        typingAttributes = attrs

        if !hasMarkedText(), let storage = textStorage, storage.length > 0 {
            let range = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.addAttributes(attrs, range: range)
            storage.endEditing()
        }
        applyShellHighlighting()
    }

    /// Lightweight, undo-safe `zsh-syntax-highlighting` style coloring via TextKit 1 temporary attributes.
    func applyShellHighlighting() {
        guard let layoutManager, let storage = textStorage else { return }
        let length = storage.length
        let fullRange = NSRange(location: 0, length: length)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)
        guard length > 0 else { return }

        let source = storage.string

        let verbColor = isDarkSurface
            ? NSColor(srgbRed: 0.44, green: 0.89, blue: 0.72, alpha: 1.0)
            : NSColor(srgbRed: 0.04, green: 0.52, blue: 0.36, alpha: 1.0)
        let flagColor = isDarkSurface
            ? NSColor(srgbRed: 0.65, green: 0.73, blue: 1.0, alpha: 1.0)
            : NSColor(srgbRed: 0.25, green: 0.30, blue: 0.78, alpha: 1.0)
        let operatorColor = isDarkSurface
            ? NSColor(srgbRed: 0.96, green: 0.68, blue: 0.38, alpha: 0.95)
            : NSColor(srgbRed: 0.76, green: 0.40, blue: 0.06, alpha: 1.0)
        let stringColor = isDarkSurface
            ? NSColor(srgbRed: 0.98, green: 0.82, blue: 0.52, alpha: 1.0)
            : NSColor(srgbRed: 0.68, green: 0.38, blue: 0.04, alpha: 1.0)
        let varColor = isDarkSurface
            ? NSColor(srgbRed: 0.47, green: 0.82, blue: 0.99, alpha: 1.0)
            : NSColor(srgbRed: 0.02, green: 0.45, blue: 0.70, alpha: 1.0)
        let commentColor = isDarkSurface
            ? NSColor(srgbRed: 0.50, green: 0.56, blue: 0.68, alpha: 0.85)
            : NSColor.secondaryLabelColor

        func highlight(_ pattern: String, color: NSColor, options: NSRegularExpression.Options = [], group: Int = 0) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            for match in regex.matches(in: source, options: [], range: fullRange) {
                let target = group < match.numberOfRanges ? match.range(at: group) : match.range
                guard target.location != NSNotFound, NSMaxRange(target) <= length else { continue }
                layoutManager.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: target)
            }
        }

        // First command token on each line or immediately after &&, ||, ;, |
        highlight(#"(?:^|(?:&&|\|\||[;|])\s*)([A-Za-z0-9_./-]+)"#, color: verbColor, options: [.anchorsMatchLines], group: 1)
        // CLI flags (-la, --watch, -sb)
        highlight(#"(?<!\S)--?[A-Za-z0-9][A-Za-z0-9_-]*"#, color: flagColor)
        // Shell operators & redirects (&&, ||, |, ;, 2>/dev/null, >)
        highlight(#"&&|\|\||[|;]|\d*>>?|\d*<&?\d*"#, color: operatorColor)
        // File paths (/dev/null, ./script.sh, ~/work)
        let pathColor = isDarkSurface
            ? NSColor(srgbRed: 0.68, green: 0.85, blue: 0.96, alpha: 0.92)
            : NSColor(srgbRed: 0.14, green: 0.42, blue: 0.62, alpha: 1.0)
        highlight(#"(?:(?<=[\s=>])|^)(?:~|\.{1,2})?/[A-Za-z0-9_./-]+"#, color: pathColor)
        // Environment variables ($HOME, ${PORT})
        highlight(#"\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"#, color: varColor)
        // Quoted strings
        highlight(#"'[^']*'|"(?:\\.|[^"\\])*""#, color: stringColor)
        // Comments
        highlight(#"(?:^|\s)(#.*)$"#, color: commentColor, options: [.anchorsMatchLines], group: 1)
    }

    func activeLineRect() -> NSRect? {
        guard let layoutManager, let textContainer else { return nil }
        layoutManager.ensureLayout(for: textContainer)
        let inset = textContainerInset
        let content = string as NSString
        let selLoc = min(selectedRange().location, content.length)

        let extraHeight = layoutManager.extraLineFragmentRect.height
        let fallbackHeight = extraHeight > 0 ? extraHeight : ceil(promptFontSize * Self.lineHeightMultiple)

        if content.length == 0 {
            return NSRect(x: 0, y: inset.height, width: bounds.width, height: fallbackHeight)
        } else if selLoc == content.length && content.hasSuffix("\n") {
            let extra = layoutManager.extraLineFragmentRect
            if extra.height > 0 {
                return NSRect(x: 0, y: extra.minY + inset.height, width: bounds.width, height: extra.height)
            }
            return nil
        } else {
            let safeLoc = min(selLoc, max(0, content.length - 1))
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: safeLoc)
            var eff = NSRange()
            let frag = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &eff)
            return NSRect(x: 0, y: frag.minY + inset.height, width: bounds.width, height: frag.height)
        }
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        // Inset the blinking cursor by 2pt top and bottom so it never touches or overflows the active-line pill border
        let adjusted = NSRect(
            x: rect.minX,
            y: rect.minY + 2.0,
            width: max(1.5, rect.width),
            height: max(10, rect.height - 4.0)
        )
        super.drawInsertionPoint(in: adjusted, color: color, turnedOn: flag)
    }

    override func setNeedsDisplay(_ invalidRect: NSRect, avoidAdditionalLayout flag: Bool) {
        // Expand cursor blink invalidation rect slightly so custom-inset insertion point never leaves artifacts
        let expanded = invalidRect.insetBy(dx: -2, dy: -4)
        super.setNeedsDisplay(expanded, avoidAdditionalLayout: flag)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty, !placeholderText.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: promptFontSize, weight: .regular),
                .foregroundColor: placeholderColor,
                .paragraphStyle: Self.makeParagraphStyle()
            ]
            let inset = textContainerInset
            let lineHeight = activeLineRect()?.height ?? ceil(promptFontSize * Self.lineHeightMultiple)
            let drawRect = NSRect(x: inset.width + 2, y: inset.height, width: max(0, bounds.width - inset.width * 2 - 2), height: lineHeight)
            (placeholderText as NSString).draw(in: drawRect, withAttributes: attrs)
        }
    }
}

/// Draws the `$` terminal prompt in the left gutter using the exact same `NSParagraphStyle`
/// and `lineFragmentRect` geometry as `PanePromptTextView`, guaranteeing sub-pixel baseline alignment.
final class PromptSymbolGutterView: NSView {
    weak var textView: PanePromptTextView?
    var accentColor: NSColor = NSColor(srgbRed: 0.39, green: 0.40, blue: 0.95, alpha: 1.0)
    var fontSize: CGFloat = 12.0

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        layoutManager.ensureLayout(for: textContainer)
        let inset = textView.textContainerInset
        let content = textView.string as NSString
        let isFocused = (textView.window?.firstResponder === textView)
        let paragraph = PanePromptTextView.makeParagraphStyle()

        let activeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: accentColor,
            .paragraphStyle: paragraph
        ]
        let mutedAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: accentColor.withAlphaComponent(isFocused ? 0.75 : 0.45),
            .paragraphStyle: paragraph
        ]

        let symbol = "$" as NSString

        func drawPrompt(yInContainer: CGFloat, lineHeight: CGFloat, muted: Bool) {
            let yInGutter = convert(NSPoint(x: 0, y: yInContainer + inset.height), from: textView).y
            guard yInGutter + lineHeight >= -4 && yInGutter <= bounds.height + 4 else { return }
            let drawRect = NSRect(x: 7, y: yInGutter, width: bounds.width - 7, height: lineHeight)
            symbol.draw(in: drawRect, withAttributes: muted ? mutedAttrs : activeAttrs)
        }

        if content.length == 0 {
            let extraHeight = layoutManager.extraLineFragmentRect.height
            let lineHeight = extraHeight > 0 ? extraHeight : ceil(fontSize * PanePromptTextView.lineHeightMultiple)
            drawPrompt(yInContainer: 0, lineHeight: lineHeight, muted: true)
            return
        }

        var index = 0
        while index < content.length {
            let lineRange = content.lineRange(for: NSRange(location: index, length: 0))
            let lineText = content.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
            let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            if glyphRange.location != NSNotFound && glyphRange.length > 0 {
                var eff = NSRange()
                let rect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: &eff)
                drawPrompt(yInContainer: rect.minY, lineHeight: rect.height, muted: lineText.isEmpty)
            }
            let next = NSMaxRange(lineRange)
            if next <= index { break }
            index = next
        }

        if content.hasSuffix("\n") {
            let extra = layoutManager.extraLineFragmentRect
            if extra.height > 0 {
                drawPrompt(yInContainer: extra.minY, lineHeight: extra.height, muted: true)
            }
        }
    }
}

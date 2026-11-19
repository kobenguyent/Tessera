import AppKit
import SwiftUI

/// Native macOS AppKit code editor built on an explicit TextKit 1 stack with
/// a sibling line-number gutter (avoiding legacy `NSRulerView` Liquid Glass issues),
/// forced dark appearance, high-contrast syntax highlighting, Find & Replace (`⌘F`),
/// soft-tab indentation, and smart-quote/spellcheck disabled.
struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    var language: String
    var fontSize: CGFloat = 12.5

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> CodeEditorContainerView {
        let container = CodeEditorContainerView(
            text: text,
            language: language,
            fontSize: fontSize,
            delegate: context.coordinator
        )
        context.coordinator.container = container
        context.coordinator.observe(container: container)
        return container
    }

    func updateNSView(_ container: CodeEditorContainerView, context: Context) {
        context.coordinator.parent = self
        let textView = container.textView

        let languageChanged = textView.editorLanguage != language
        textView.editorFontSize = fontSize
        textView.editorLanguage = language
        textView.tabWidth = (language.lowercased() == "yaml") ? 2 : 4

        if textView.string != text {
            context.coordinator.isProgrammaticUpdate = true
            textView.string = text
            textView.restyleAllText()
            textView.undoManager?.removeAllActions()
            container.scrollToTopLeft()
            container.updateGutter()
            context.coordinator.isProgrammaticUpdate = false
        } else if languageChanged {
            textView.applySyntaxHighlighting()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorView
        weak var container: CodeEditorContainerView?
        var isProgrammaticUpdate = false
        private var observers: [NSObjectProtocol] = []

        init(_ parent: CodeEditorView) {
            self.parent = parent
        }

        deinit {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func observe(container: CodeEditorContainerView) {
            container.scrollView.contentView.postsBoundsChangedNotifications = true
            let boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: container.scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.container?.gutterView.needsDisplay = true
            }
            let frameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: container.textView,
                queue: .main
            ) { [weak self] _ in
                self?.container?.gutterView.needsDisplay = true
            }
            observers.append(contentsOf: [boundsObserver, frameObserver])
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticUpdate,
                  let codeView = notification.object as? TesseraCodeTextView else { return }
            codeView.restyleAllText()
            let updated = codeView.string
            if parent.text != updated {
                parent.text = updated
            }
            container?.updateGutter()
        }
    }
}

final class CodeEditorContainerView: NSView {
    let gutterView = LineNumberGutterView()
    let scrollView = NSScrollView()
    let textView: TesseraCodeTextView
    private var gutterWidth: CGFloat = 44

    override var isFlipped: Bool { true }

    init(text: String, language: String, fontSize: CGFloat, delegate: NSTextViewDelegate) {
        let darkAppearance = NSAppearance(named: .darkAqua)
        let editorBackground = NSColor(srgbRed: 0.08, green: 0.09, blue: 0.13, alpha: 1.0)
        let maxDim: CGFloat = 10_000_000

        // Explicit TextKit 1 stack avoids late TextKit 2 -> 1 resets when reading layoutManager.
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: NSSize(width: maxDim, height: maxDim))
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false
        layoutManager.addTextContainer(textContainer)

        textView = TesseraCodeTextView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 320),
            textContainer: textContainer
        )

        super.init(frame: NSRect(x: 0, y: 0, width: 720, height: 320))

        self.appearance = darkAppearance
        self.wantsLayer = true
        self.layer?.backgroundColor = editorBackground.cgColor

        scrollView.appearance = darkAppearance
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = editorBackground
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsetsZero

        textView.appearance = darkAppearance
        textView.delegate = delegate
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = true

        // Disable all smart text substitutions so AppleScript / Shell / YAML stay exact.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false

        textView.backgroundColor = editorBackground
        textView.insertionPointColor = NSColor(srgbRed: 0.48, green: 0.62, blue: 1.0, alpha: 1.0)
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor(srgbRed: 0.39, green: 0.40, blue: 0.95, alpha: 0.42),
            .foregroundColor: NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        ]

        textView.textContainerInset = NSSize(width: 10, height: 12)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = []
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: maxDim, height: maxDim)

        textView.editorFontSize = fontSize
        textView.editorLanguage = language
        textView.tabWidth = (language.lowercased() == "yaml") ? 2 : 4
        textView.configureBaseStyling()
        textView.string = text
        textView.restyleAllText()

        scrollView.documentView = textView

        gutterView.appearance = darkAppearance
        gutterView.textView = textView

        addSubview(gutterView)
        addSubview(scrollView)
        updateGutter()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        if textView.frame.width < contentSize.width || textView.frame.height < contentSize.height {
            textView.setFrameSize(NSSize(
                width: max(textView.frame.width, contentSize.width),
                height: max(textView.frame.height, contentSize.height)
            ))
        }
        if textView.frame.origin != .zero {
            textView.setFrameOrigin(.zero)
        }
        gutterView.needsDisplay = true
    }

    func scrollToTopLeft() {
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func updateGutter() {
        let lineCount = max(1, textView.string.reduce(1) { $0 + ($1 == "\n" ? 1 : 0) })
        let digits = max(2, String(lineCount).count)
        let desired = CGFloat(digits) * 8.5 + 24
        if abs(gutterWidth - desired) > 1 {
            gutterWidth = desired
            needsLayout = true
        }
        gutterView.needsDisplay = true
    }
}

final class TesseraCodeTextView: NSTextView {
    var tabWidth: Int = 4
    var editorFontSize: CGFloat = 12.5
    var editorLanguage: String = "applescript"

    static let baseInk = NSColor(srgbRed: 0.93, green: 0.95, blue: 0.99, alpha: 1.0)
    static let commentColor = NSColor(srgbRed: 0.49, green: 0.56, blue: 0.69, alpha: 1.0)
    static let stringColor = NSColor(srgbRed: 0.45, green: 0.90, blue: 0.72, alpha: 1.0)
    static let keywordColor = NSColor(srgbRed: 0.67, green: 0.72, blue: 1.0, alpha: 1.0)
    static let variableColor = NSColor(srgbRed: 0.47, green: 0.82, blue: 0.99, alpha: 1.0)
    static let numberColor = NSColor(srgbRed: 0.98, green: 0.75, blue: 0.44, alpha: 1.0)

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        appearance = NSAppearance(named: .darkAqua)
        restyleAllText()
    }

    override func insertTab(_ sender: Any?) {
        let spaces = String(repeating: " ", count: max(2, tabWidth))
        insertText(spaces, replacementRange: selectedRange())
    }

    private func makeBaseAttributes() -> [NSAttributedString.Key: Any] {
        let font = NSFont.monospacedSystemFont(ofSize: editorFontSize, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.28
        return [
            .font: font,
            .foregroundColor: Self.baseInk,
            .paragraphStyle: paragraph
        ]
    }

    func configureBaseStyling() {
        let attrs = makeBaseAttributes()
        font = attrs[.font] as? NSFont
        textColor = Self.baseInk
        defaultParagraphStyle = attrs[.paragraphStyle] as? NSParagraphStyle
        typingAttributes = attrs
    }

    func restyleAllText() {
        let attrs = makeBaseAttributes()
        font = attrs[.font] as? NSFont
        textColor = Self.baseInk
        defaultParagraphStyle = attrs[.paragraphStyle] as? NSParagraphStyle
        typingAttributes = attrs

        if !hasMarkedText(), let storage = textStorage, storage.length > 0 {
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.addAttributes(attrs, range: fullRange)
            storage.endEditing()
        }
        applySyntaxHighlighting()
    }

    /// Applies lightweight, undo-safe syntax coloring via TextKit 1 temporary attributes.
    func applySyntaxHighlighting() {
        guard let layoutManager, let storage = textStorage else { return }
        let length = storage.length
        let fullRange = NSRange(location: 0, length: length)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)
        guard length > 0 else { return }

        let source = storage.string

        func highlight(pattern: String, color: NSColor, options: NSRegularExpression.Options = []) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            let matches = regex.matches(in: source, options: [], range: fullRange)
            for match in matches {
                let targetRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
                guard targetRange.location != NSNotFound,
                      NSMaxRange(targetRange) <= length else { continue }
                layoutManager.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: targetRange)
            }
        }

        switch editorLanguage.lowercased() {
        case "applescript":
            highlight(
                pattern: #"\b(tell|end tell|end try|try|activate|set|to|of|with|default|profile|create|window|tab|session|split|vertically|horizontally|write text|select|do script|bounds|current|front|application|id|name|custom title)\b"#,
                color: Self.keywordColor
            )
            highlight(pattern: #"\b\d+(?:\.\d+)?\b"#, color: Self.numberColor)
            highlight(pattern: #"\b(sess_\d+|tab_\d+|termTab_\d+|termWin_\d+|targetWindow)\b"#, color: Self.variableColor)
            highlight(pattern: #""(?:\\.|[^"\\])*""#, color: Self.stringColor)
            highlight(pattern: #"--.*$"#, color: Self.commentColor, options: [.anchorsMatchLines])

        case "yaml", "yml":
            highlight(pattern: #"^\s*-?\s*([A-Za-z0-9_-]+)\s*:"#, color: Self.keywordColor, options: [.anchorsMatchLines])
            highlight(pattern: #"\b(true|false|horizontal|vertical)\b"#, color: Self.numberColor)
            highlight(pattern: #""(?:\\.|[^"\\])*""#, color: Self.stringColor)
            highlight(pattern: #"#.*$"#, color: Self.commentColor, options: [.anchorsMatchLines])

        case "conf", "kitty":
            highlight(
                pattern: #"^\s*(new_tab|layout|cd|env|launch|focus)\b"#,
                color: Self.keywordColor,
                options: [.anchorsMatchLines]
            )
            highlight(pattern: #"--[A-Za-z0-9_-]+(?:=[^\s]+)?"#, color: Self.variableColor)
            highlight(pattern: #"'[^']*'|"(?:\\.|[^"\\])*""#, color: Self.stringColor)
            highlight(pattern: #"#.*$"#, color: Self.commentColor, options: [.anchorsMatchLines])

        default: // zsh / bash / sh
            highlight(
                pattern: #"\b(if|then|else|elif|fi|for|do|done|while|case|esac|set|export|sleep|echo|printf|open|osascript|exit|true|false)\b"#,
                color: Self.keywordColor
            )
            highlight(pattern: #"\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"#, color: Self.variableColor)
            highlight(pattern: #"'[^']*'|"(?:\\.|[^"\\])*""#, color: Self.stringColor)
            highlight(pattern: #"#.*$"#, color: Self.commentColor, options: [.anchorsMatchLines])
        }
    }
}

final class LineNumberGutterView: NSView {
    weak var textView: NSTextView?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 0.06, green: 0.07, blue: 0.10, alpha: 1.0).setFill()
        bounds.fill()

        NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.09).setFill()
        NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill()

        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        layoutManager.ensureLayout(for: textContainer)
        let textInset = textView.textContainerInset
        let content = textView.string as NSString

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor(srgbRed: 0.62, green: 0.68, blue: 0.80, alpha: 0.70)
        ]

        func drawLineNumber(_ number: Int, yInTextContainer: CGFloat, lineHeight: CGFloat) {
            let yInGutter = convert(NSPoint(x: 0, y: yInTextContainer + textInset.height), from: textView).y
            let label = "\(number)" as NSString
            let size = label.size(withAttributes: attributes)
            let yPos = yInGutter + (lineHeight - size.height) / 2.0
            guard yPos + size.height >= -4 && yPos <= bounds.height + 4 else { return }
            label.draw(at: NSPoint(x: bounds.width - size.width - 10, y: yPos), withAttributes: attributes)
        }

        if content.length == 0 {
            drawLineNumber(1, yInTextContainer: 0, lineHeight: 18)
            return
        }

        var lineNumber = 1
        var index = 0
        while index < content.length {
            let lineRange = content.lineRange(for: NSRange(location: index, length: 0))
            let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            if glyphRange.location != NSNotFound && glyphRange.length > 0 {
                var eff = NSRange()
                let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: &eff)
                drawLineNumber(lineNumber, yInTextContainer: lineRect.minY, lineHeight: lineRect.height)
            }
            lineNumber += 1
            let next = NSMaxRange(lineRange)
            if next <= index { break }
            index = next
        }

        if content.hasSuffix("\n") {
            let extraRect = layoutManager.extraLineFragmentRect
            if extraRect.height > 0 {
                drawLineNumber(lineNumber, yInTextContainer: extraRect.minY, lineHeight: extraRect.height)
            }
        }
    }
}

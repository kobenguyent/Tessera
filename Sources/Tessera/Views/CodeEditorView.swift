import AppKit
import SwiftUI

/// Native macOS AppKit code editor built on an explicit TextKit 1 stack with
/// forced dark appearance, high-contrast syntax highlighting, line numbers,
/// Find & Replace (`⌘F`), soft-tab indentation, and smart-quote/spellcheck disabled.
struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    var language: String
    var fontSize: CGFloat = 12.5

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let darkAppearance = NSAppearance(named: .darkAqua)
        let editorBackground = NSColor(srgbRed: 0.08, green: 0.09, blue: 0.13, alpha: 1.0)

        let scrollView = NSScrollView()
        scrollView.appearance = darkAppearance
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = editorBackground

        // Construct an explicit TextKit 1 stack up front so accessing `layoutManager`
        // for line numbers / highlighting never triggers a late TextKit 2 -> 1 reset.
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(
            size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        )
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false
        layoutManager.addTextContainer(textContainer)

        let textView = TesseraCodeTextView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            textContainer: textContainer
        )
        textView.appearance = darkAppearance
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = true

        // Critical for editing AppleScript / Shell / YAML: disable all smart text substitutions.
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
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)

        textView.editorFontSize = fontSize
        textView.editorLanguage = language
        textView.tabWidth = (language.lowercased() == "yaml") ? 2 : 4
        textView.configureBaseStyling()
        textView.string = text
        textView.restyleAllText()

        scrollView.documentView = textView

        // Attach line-number gutter ruler
        let ruler = LineNumberRulerView(textView: textView)
        ruler.appearance = darkAppearance
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        ruler.updateThicknessIfNeeded()

        context.coordinator.textView = textView
        context.coordinator.rulerView = ruler
        context.coordinator.observe(textView: textView, scrollView: scrollView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? TesseraCodeTextView else { return }

        let languageChanged = textView.editorLanguage != language
        textView.editorFontSize = fontSize
        textView.editorLanguage = language
        textView.tabWidth = (language.lowercased() == "yaml") ? 2 : 4

        if textView.string != text {
            context.coordinator.isProgrammaticUpdate = true
            textView.string = text
            textView.restyleAllText()
            textView.undoManager?.removeAllActions()
            context.coordinator.isProgrammaticUpdate = false
            context.coordinator.rulerView?.updateThicknessIfNeeded()
            context.coordinator.rulerView?.needsDisplay = true
        } else if languageChanged {
            textView.applySyntaxHighlighting()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorView
        weak var textView: TesseraCodeTextView?
        weak var rulerView: LineNumberRulerView?
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

        func observe(textView: NSTextView, scrollView: NSScrollView) {
            scrollView.contentView.postsBoundsChangedNotifications = true
            let boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.rulerView?.needsDisplay = true
            }
            let frameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: textView,
                queue: .main
            ) { [weak self] _ in
                self?.rulerView?.needsDisplay = true
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
            rulerView?.updateThicknessIfNeeded()
            rulerView?.needsDisplay = true
        }
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

final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 44
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateThicknessIfNeeded() {
        guard let text = textView?.string else { return }
        let lineCount = max(1, text.reduce(1) { $0 + ($1 == "\n" ? 1 : 0) })
        let digits = max(2, String(lineCount).count)
        let desired = CGFloat(digits) * 8.5 + 22
        if abs(ruleThickness - desired) > 1 {
            ruleThickness = desired
        }
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        // Gutter background & subtle divider
        NSColor(srgbRed: 0.06, green: 0.07, blue: 0.10, alpha: 1.0).setFill()
        rect.fill()

        NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.09).setFill()
        NSRect(x: bounds.maxX - 1, y: rect.minY, width: 1, height: rect.height).fill()

        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let visibleRect = scrollView?.contentView.bounds ?? textView.visibleRect
        let textInset = textView.textContainerInset
        let content = textView.string as NSString

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor(srgbRed: 0.62, green: 0.68, blue: 0.80, alpha: 0.65)
        ]

        let containerRect = NSRect(
            x: 0,
            y: max(0, visibleRect.minY - textInset.height),
            width: textContainer.containerSize.width,
            height: visibleRect.height + textInset.height * 2
        )
        let glyphRange = layoutManager.glyphRange(forBoundingRect: containerRect, in: textContainer)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        var lineNumber = 1
        var scanIndex = 0
        while scanIndex < charRange.location {
            let lineRange = content.lineRange(for: NSRange(location: scanIndex, length: 0))
            lineNumber += 1
            scanIndex = NSMaxRange(lineRange)
            if lineRange.length == 0 { break }
        }

        var index = charRange.location
        let maxIndex = NSMaxRange(charRange)

        func drawLineNumber(_ number: Int, yInTextView: CGFloat, lineHeight: CGFloat) {
            let label = "\(number)" as NSString
            let size = label.size(withAttributes: attributes)
            let yPos = yInTextView + textInset.height - visibleRect.minY + (lineHeight - size.height) / 2.0
            let drawPoint = NSPoint(x: ruleThickness - size.width - 10, y: yPos)
            label.draw(at: drawPoint, withAttributes: attributes)
        }

        if content.length == 0 {
            drawLineNumber(1, yInTextView: 0, lineHeight: 18)
            return
        }

        while index < maxIndex {
            let lineRange = content.lineRange(for: NSRange(location: index, length: 0))
            let lineGlyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            if lineGlyphRange.location != NSNotFound && lineGlyphRange.length > 0 {
                var effectiveRange = NSRange(location: 0, length: 0)
                let lineRect = layoutManager.lineFragmentRect(
                    forGlyphAt: lineGlyphRange.location,
                    effectiveRange: &effectiveRange
                )
                drawLineNumber(lineNumber, yInTextView: lineRect.minY, lineHeight: lineRect.height)
            }
            lineNumber += 1
            let next = NSMaxRange(lineRange)
            if next <= index { break }
            index = next
        }

        if content.hasSuffix("\n") {
            let extraRect = layoutManager.extraLineFragmentRect
            if extraRect.height > 0 {
                drawLineNumber(lineNumber, yInTextView: extraRect.minY, lineHeight: extraRect.height)
            }
        }
    }
}

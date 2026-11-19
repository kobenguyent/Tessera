import AppKit
import SwiftUI

/// Native macOS AppKit code editor with line numbers, monospace typography,
/// Find & Replace (`⌘F`), soft-tab indentation, and smart-quote/spellcheck disabled.
struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    var language: String
    var fontSize: CGFloat = 12.5

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(red: 0.08, green: 0.09, blue: 0.13, alpha: 1.0)

        let textView = TesseraCodeTextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isRichText = false
        textView.importsGraphics = false

        // Critical for editing AppleScript / Shell / YAML: disable all smart text substitutions!
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false

        textView.backgroundColor = NSColor(red: 0.08, green: 0.09, blue: 0.13, alpha: 1.0)
        textView.insertionPointColor = NSColor(red: 0.45, green: 0.56, blue: 1.0, alpha: 1.0)
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor(red: 0.39, green: 0.40, blue: 0.95, alpha: 0.36),
            .foregroundColor: NSColor.white
        ]

        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.28

        textView.font = font
        textView.textColor = NSColor(white: 0.93, alpha: 1.0)
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: NSColor(white: 0.93, alpha: 1.0),
            .paragraphStyle: paragraph
        ]
        textView.textContainerInset = NSSize(width: 10, height: 12)

        // Allow smooth horizontal scrolling without awkward mid-command wrapping
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        textView.tabWidth = (language.lowercased() == "yaml") ? 2 : 4
        textView.string = text
        textView.applyBaseAttributes(font: font, paragraph: paragraph)

        scrollView.documentView = textView

        // Attach line-number gutter ruler
        let ruler = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        context.coordinator.textView = textView
        context.coordinator.rulerView = ruler
        context.coordinator.observe(textView: textView, scrollView: scrollView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? TesseraCodeTextView else { return }
        textView.tabWidth = (language.lowercased() == "yaml") ? 2 : 4

        if textView.string != text {
            context.coordinator.isProgrammaticUpdate = true
            let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineHeightMultiple = 1.28
            textView.string = text
            textView.applyBaseAttributes(font: font, paragraph: paragraph)
            textView.undoManager?.removeAllActions()
            context.coordinator.isProgrammaticUpdate = false
            context.coordinator.rulerView?.needsDisplay = true
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
                  let textView = notification.object as? NSTextView else { return }
            let updated = textView.string
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

    override func insertTab(_ sender: Any?) {
        let spaces = String(repeating: " ", count: max(2, tabWidth))
        insertText(spaces, replacementRange: selectedRange())
    }

    func applyBaseAttributes(font: NSFont, paragraph: NSParagraphStyle) {
        guard let storage = textStorage, storage.length > 0 else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes([
            .font: font,
            .foregroundColor: NSColor(white: 0.93, alpha: 1.0),
            .paragraphStyle: paragraph
        ], range: fullRange)
        storage.endEditing()
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
        NSColor(red: 0.06, green: 0.07, blue: 0.10, alpha: 1.0).setFill()
        rect.fill()

        NSColor(white: 1.0, alpha: 0.08).setFill()
        NSRect(x: bounds.maxX - 1, y: rect.minY, width: 1, height: rect.height).fill()

        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let visibleRect = scrollView?.contentView.bounds ?? textView.visibleRect
        let textInset = textView.textContainerInset
        let content = textView.string as NSString

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor(white: 1.0, alpha: 0.36)
        ]

        // Convert visible rect into text container coordinates
        let containerRect = NSRect(
            x: 0,
            y: max(0, visibleRect.minY - textInset.height),
            width: textContainer.containerSize.width,
            height: visibleRect.height + textInset.height * 2
        )
        let glyphRange = layoutManager.glyphRange(forBoundingRect: containerRect, in: textContainer)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        // Count lines preceding the first visible character
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

        // Draw trailing blank line number if text ends with newline
        if content.hasSuffix("\n") {
            let extraRect = layoutManager.extraLineFragmentRect
            if extraRect.height > 0 {
                drawLineNumber(lineNumber, yInTextView: extraRect.minY, lineHeight: extraRect.height)
            }
        }
    }
}

import AppKit

/// 탭 하나 = 문서 하나. 각자 편집기, 스크롤 뷰, 실행 취소 기록을 가진다.
final class TabDocument: NSObject, NSTextViewDelegate {
    let id: UUID
    var url: URL? { didSet { onChange?() } }
    var encoding: FileEncoding = .utf8 { didSet { onChange?() } }
    var lineEnding: LineEnding = .lf { didSet { onChange?() } }
    var isModified = false { didSet { if oldValue != isModified { onChange?() } } }
    var fileModDate: Date?

    let undo = UndoManager()
    let scrollView: NSScrollView
    let textView: EditorTextView

    var onChange: (() -> Void)?
    var onTextChange: (() -> Void)?
    var onSelectionChange: (() -> Void)?

    var title: String { url?.lastPathComponent ?? "제목 없음" }
    var text: String {
        get { textView.string }
        set { textView.string = newValue }
    }

    init(id: UUID = UUID()) {
        self.id = id
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.editorBackground
        scrollView.scrollerStyle = .overlay

        let storage = NSTextStorage()
        let lm = NSLayoutManager()
        lm.allowsNonContiguousLayout = true
        storage.addLayoutManager(lm)
        let tc = NSTextContainer(size: NSSize(width: 100, height: CGFloat.greatestFiniteMagnitude))
        tc.lineFragmentPadding = 0
        lm.addTextContainer(tc)
        textView = EditorTextView(frame: .zero, textContainer: tc)
        super.init()

        let tv = textView
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsImageEditing = false
        tv.usesFontPanel = false
        tv.usesRuler = false
        tv.usesFindBar = false
        tv.usesFindPanel = false
        tv.isIncrementalSearchingEnabled = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.isAutomaticTextCompletionEnabled = false
        tv.displaysLinkToolTips = false
        tv.drawsBackground = true
        tv.backgroundColor = Theme.editorBackground
        tv.textColor = Theme.editorText
        tv.insertionPointColor = Theme.editorText
        tv.selectedTextAttributes = [.backgroundColor: Theme.selectionBackground, .foregroundColor: NSColor.white]
        tv.isVerticallyResizable = true
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.autoresizingMask = [.width]
        tv.textContainerInset = NSSize(width: 9, height: 13)
        tv.delegate = self
        scrollView.documentView = tv
    }

    // MARK: 스타일

    func applyStyle(font: NSFont, wordWrap: Bool, spellCheck: Bool, autoCorrect: Bool) {
        let tv = textView
        let lineHeight = round(font.ascender - font.descender + font.leading)
        let ps = NSMutableParagraphStyle()
        ps.minimumLineHeight = lineHeight
        ps.maximumLineHeight = lineHeight
        let tabW = ("x" as NSString).size(withAttributes: [.font: font]).width * 8
        ps.tabStops = []
        ps.defaultTabInterval = max(8, tabW)
        ps.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: ps, .foregroundColor: Theme.editorText]
        tv.defaultParagraphStyle = ps
        tv.typingAttributes = attrs
        if let ts = tv.textStorage {
            ts.beginEditing()
            ts.setAttributes(attrs, range: NSRange(location: 0, length: ts.length))
            ts.endEditing()
        }
        tv.font = font

        tv.isContinuousSpellCheckingEnabled = spellCheck
        tv.isAutomaticSpellingCorrectionEnabled = autoCorrect

        guard let tc = tv.textContainer else { return }
        if wordWrap {
            scrollView.hasHorizontalScroller = false
            tv.isHorizontallyResizable = false
            tv.autoresizingMask = [.width]
            tc.widthTracksTextView = true
            tc.containerSize = NSSize(width: scrollView.contentSize.width - tv.textContainerInset.width * 2, height: CGFloat.greatestFiniteMagnitude)
            tv.frame.size.width = scrollView.contentSize.width
        } else {
            scrollView.hasHorizontalScroller = true
            tc.widthTracksTextView = false
            tc.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            tv.isHorizontallyResizable = true
            tv.autoresizingMask = []
        }
        tv.layoutManager?.ensureLayout(for: tc)
        tv.sizeToFit()
    }

    // MARK: 상태 표시줄 정보

    /// (줄, 열) 1부터 시작
    func caretPosition() -> (line: Int, column: Int) {
        let ns = textView.string as NSString
        let sel = textView.selectedRange()
        let loc = min(sel.location, ns.length)
        var line = 1
        var lineStart = 0
        var search = NSRange(location: 0, length: loc)
        while true {
            let r = ns.range(of: "\n", options: .literal, range: search)
            if r.location == NSNotFound { break }
            line += 1
            lineStart = r.location + 1
            search = NSRange(location: lineStart, length: loc - lineStart)
        }
        let col = (ns.substring(with: NSRange(location: lineStart, length: loc - lineStart))).count + 1
        return (line, col)
    }

    func characterCount() -> Int { textView.string.count }

    func selectedCharacterCount() -> Int {
        let ns = textView.string as NSString
        return textView.selectedRanges.reduce(0) { $0 + ns.substring(with: $1.rangeValue).count }
    }

    // MARK: NSTextViewDelegate

    func undoManager(for view: NSTextView) -> UndoManager? { undo }

    func textDidChange(_ notification: Notification) {
        isModified = true
        onTextChange?()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        onSelectionChange?()
    }
}

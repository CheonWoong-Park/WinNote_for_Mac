import AppKit

protocol EditorTextViewHost: AnyObject {
    func editorRequestsZoom(delta: Int)
    func editorOpenFiles(_ urls: [URL])
    func editorContextMenu(_ editor: EditorTextView, event: NSEvent)
}

/// 서식 없는 텍스트 전용 편집기. 복사/붙여넣기/드래그 모두 순수 텍스트만 주고받는다.
final class EditorTextView: NSTextView {
    weak var host: EditorTextViewHost?
    private var magnifyAccumulator: CGFloat = 0

    /// Windows 메모장처럼 왼쪽 여백만 두고 오른쪽 끝까지 줄 바꿈
    override var textContainerOrigin: NSPoint { NSPoint(x: 17, y: textContainerInset.height) }

    // MARK: 순수 텍스트 클립보드

    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] { [.fileURL, .string] }

    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard type == .string else { return false }
        let s = selectedRanges.map { (string as NSString).substring(with: $0.rangeValue) }.joined(separator: "\n")
        pboard.setString(s, forType: .string)
        return true
    }

    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        pboard.declareTypes([.string], owner: nil)
        return writeSelection(to: pboard, type: .string)
    }

    private func plainText(from pboard: NSPasteboard) -> String? {
        if let s = pboard.string(forType: .string) { return s }
        // 다른 앱이 RTF/HTML만 올려둔 경우에도 문자열만 추출
        if let d = pboard.data(forType: .rtf), let a = NSAttributedString(rtf: d, documentAttributes: nil) { return a.string }
        if let d = pboard.data(forType: .html), let a = NSAttributedString(html: d, documentAttributes: nil) { return a.string }
        return nil
    }

    private func insertPlain(_ raw: String) {
        let s = TextFile.normalizeNewlines(raw)
        let range = selectedRange()
        if shouldChangeText(in: range, replacementString: s) {
            textStorage?.replaceCharacters(in: range, with: s)
            if let ts = textStorage { ts.setAttributes(typingAttributes, range: NSRange(location: range.location, length: (s as NSString).length)) }
            didChangeText()
            setSelectedRange(NSRange(location: range.location + (s as NSString).length, length: 0))
            scrollRangeToVisible(selectedRange())
        }
    }

    override func paste(_ sender: Any?) {
        guard let s = plainText(from: .general) else { return }
        insertPlain(s)
    }
    override func pasteAsPlainText(_ sender: Any?) { paste(sender) }
    override func pasteAsRichText(_ sender: Any?) { paste(sender) }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard let s = plainText(from: pboard) else { return false }
        insertPlain(s)
        return true
    }

    // 파일을 끌어다 놓으면 열기, 텍스트는 순수 텍스트로
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            host?.editorOpenFiles(urls)
            return true
        }
        if sender.draggingSource as? EditorTextView === self {
            return super.performDragOperation(sender)
        }
        guard let s = plainText(from: pb) else { return false }
        let p = convert(sender.draggingLocation, from: nil)
        let idx = characterIndexForInsertion(at: p)
        setSelectedRange(NSRange(location: idx, length: 0))
        insertPlain(s)
        return true
    }

    // MARK: Windows 키 동작

    override func keyDown(with event: NSEvent) {
        let f = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let ctrl = f.contains(.control) || f.contains(.command)
        let shift = f.contains(.shift)
        switch event.keyCode {
        case 115: // Home
            if ctrl { shift ? moveToBeginningOfDocumentAndModifySelection(nil) : moveToBeginningOfDocument(nil) }
            else { shift ? moveToLeftEndOfLineAndModifySelection(nil) : moveToLeftEndOfLine(nil) }
            return
        case 119: // End
            if ctrl { shift ? moveToEndOfDocumentAndModifySelection(nil) : moveToEndOfDocument(nil) }
            else { shift ? moveToRightEndOfLineAndModifySelection(nil) : moveToRightEndOfLine(nil) }
            return
        case 116: // PageUp
            shift ? pageUpAndModifySelection(nil) : pageUp(nil); return
        case 121: // PageDown
            shift ? pageDownAndModifySelection(nil) : pageDown(nil); return
        case 123 where f.contains(.control): // Ctrl+←
            shift ? moveWordLeftAndModifySelection(nil) : moveWordLeft(nil); return
        case 124 where f.contains(.control): // Ctrl+→
            shift ? moveWordRightAndModifySelection(nil) : moveWordRight(nil); return
        case 126 where f.contains(.control): // Ctrl+↑
            shift ? moveParagraphBackwardAndModifySelection(nil) : moveToBeginningOfParagraph(nil); return
        case 125 where f.contains(.control): // Ctrl+↓
            shift ? moveParagraphForwardAndModifySelection(nil) : moveToEndOfParagraph(nil); return
        case 51 where f.contains(.control): // Ctrl+Backspace
            deleteWordBackward(nil); return
        case 117 where f.contains(.control): // Ctrl+Delete
            deleteWordForward(nil); return
        default: break
        }
        super.keyDown(with: event)
    }

    override func insertNewline(_ sender: Any?) { insertText("\n", replacementRange: selectedRange()) }

    // MARK: 확대/축소 (Ctrl/Cmd + 휠, 핀치)

    override func scrollWheel(with event: NSEvent) {
        let f = event.modifierFlags
        if f.contains(.control) || f.contains(.command) {
            let dy = event.scrollingDeltaY
            if abs(dy) > 0.1 {
                if event.hasPreciseScrollingDeltas {
                    magnifyAccumulator += dy
                    if abs(magnifyAccumulator) >= 12 {
                        host?.editorRequestsZoom(delta: magnifyAccumulator > 0 ? 1 : -1)
                        magnifyAccumulator = 0
                    }
                } else {
                    host?.editorRequestsZoom(delta: dy > 0 ? 1 : -1)
                }
            }
            return
        }
        super.scrollWheel(with: event)
    }

    override func magnify(with event: NSEvent) {
        magnifyAccumulator += event.magnification
        if abs(magnifyAccumulator) > 0.1 {
            host?.editorRequestsZoom(delta: magnifyAccumulator > 0 ? 1 : -1)
            magnifyAccumulator = 0
        }
    }

    // MARK: Windows 스타일 상황 메뉴

    override func menu(for event: NSEvent) -> NSMenu? { nil }

    override func rightMouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let idx = characterIndexForInsertion(at: p)
        let sel = selectedRange()
        if !(sel.length > 0 && idx >= sel.location && idx <= NSMaxRange(sel)) {
            setSelectedRange(NSRange(location: idx, length: 0))
        }
        window?.makeFirstResponder(self)
        host?.editorContextMenu(self, event: event)
    }
}

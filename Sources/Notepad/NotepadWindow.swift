import AppKit

/// 모서리가 각진 Windows 스타일 창 (타이틀 바 없는 borderless 창)
final class NotepadWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .resizable, .miniaturizable], backing: .buffered, defer: false)
        isOpaque = true
        hasShadow = true
        backgroundColor = Theme.micaBase
        isMovable = true
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        minSize = NSSize(width: 460, height: 260)
        collectionBehavior = [.managed, .participatesInCycle]
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    private var controller: NotepadWindowController? { windowController as? NotepadWindowController }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, handleWindowsShortcut(event) { return }
        super.sendEvent(event)
    }

    /// Ctrl 키 조합을 Windows 단축키로 처리 (Cmd 조합과 동일한 동작)
    private func handleWindowsShortcut(_ event: NSEvent) -> Bool {
        if FlyoutMenu.isOpen { return false }
        let f = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let ctrl = f.contains(.control), cmd = f.contains(.command)
        guard let c = controller else { return false }
        if c.isDialogOpen { return false }

        // Ctrl+Tab / Ctrl+Shift+Tab : 탭 전환
        if ctrl && event.keyCode == 48 { c.cycleTab(f.contains(.shift) ? -1 : 1); return true }
        // Ctrl+Y / Cmd+Shift+Z : 다시 실행
        if (ctrl || cmd) && !f.contains(.shift) && event.charactersIgnoringModifiers?.lowercased() == "y" {
            NSApp.sendAction(Selector(("redo:")), to: nil, from: self); return true
        }
        // Ctrl/Cmd + 숫자패드 +/- 확대 축소
        if ctrl || cmd {
            switch event.keyCode {
            case 69, 24: c.zoomIn(nil); return true      // +, =
            case 78, 27: c.zoomOut(nil); return true     // -, 숫자패드 -
            case 82, 29: if !f.contains(.shift) { c.zoomReset(nil); return true }
            default: break
            }
        }
        guard ctrl && !cmd else { return false }
        // 커서 이동 키는 편집기에서 처리
        let navKeys: Set<UInt16> = [123, 124, 125, 126, 115, 119, 116, 121, 51, 117]
        if navKeys.contains(event.keyCode) { return false }
        guard let chars = event.charactersIgnoringModifiers, !chars.isEmpty else { return false }
        var flags = f.subtracting(.control)
        flags.insert(.command)
        guard let cmdEvent = NSEvent.keyEvent(with: .keyDown, location: event.locationInWindow, modifierFlags: flags,
                                              timestamp: event.timestamp, windowNumber: event.windowNumber, context: nil,
                                              characters: chars, charactersIgnoringModifiers: chars,
                                              isARepeat: event.isARepeat, keyCode: event.keyCode) else { return false }
        if NSApp.mainMenu?.performKeyEquivalent(with: cmdEvent) == true { return true }
        return false
    }
}

/// 창 테두리 1px (클릭 통과)
final class WindowBorderView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        guard let w = window, !w.styleMask.contains(.fullScreen) else { return }
        if w.isZoomedWindows { return }
        Theme.windowBorder.setStroke()
        let p = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        p.lineWidth = 1
        p.stroke()
    }
}

extension NSWindow {
    var isZoomedWindows: Bool {
        guard let s = screen else { return false }
        return frame == s.visibleFrame
    }
}

/// 루트 뷰 (모든 하위 뷰의 배치 담당)
final class RootView: NSView {
    weak var controller: NotepadWindowController?
    override var isFlipped: Bool { true }
    override func layout() {
        super.layout()
        controller?.layoutViews()
    }
}

import AppKit

protocol TitleBarDelegate: AnyObject {
    var tabs: [TabDocument] { get }
    var selectedTabIndex: Int { get }
    var isSettingsMode: Bool { get }
    var isMaximized: Bool { get }
    func titleBarSelectTab(_ index: Int)
    func titleBarCloseTab(_ index: Int)
    func titleBarNewTab()
    func titleBarMoveTab(from: Int, to: Int)
    func titleBarDropTab(_ index: Int, screenPoint: NSPoint)
    func titleBarTabContextMenu(_ index: Int, event: NSEvent)
    func titleBarMinimize()
    func titleBarToggleMaximize()
    func titleBarClose()
    func titleBarBack()
}

/// 탭 표시줄 + Windows 캡션 버튼 (높이 43)
final class TitleBarView: NSView {
    static let height: CGFloat = 43
    weak var delegate: TitleBarDelegate?

    private enum Part: Equatable {
        case none, tab(Int), tabClose(Int), add, minimize, maximize, close, back
    }

    private var hover: Part = .none { didSet { if hover != oldValue { needsDisplay = true; updateToolTip() } } }
    private var pressed: Part = .none { didSet { if pressed != oldValue { needsDisplay = true } } }
    private var tracking: NSTrackingArea?
    private let titleFont = Theme.ui(13)

    // 드래그 상태
    private var dragIndex: Int?
    private var dragStart: NSPoint = .zero
    private var dragging = false
    private var dragOutside = false

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }

    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }

    // MARK: 레이아웃

    private let tabsX: CGFloat = 49
    private let tabY: CGFloat = 11
    private let tabH: CGFloat = 32
    private let captionW: CGFloat = 46
    private let captionH: CGFloat = 32

    var minimizeRect: NSRect { NSRect(x: bounds.width - captionW * 3, y: 0, width: captionW, height: captionH) }
    var maximizeRect: NSRect { NSRect(x: bounds.width - captionW * 2, y: 0, width: captionW, height: captionH) }
    var closeRect: NSRect { NSRect(x: bounds.width - captionW, y: 0, width: captionW, height: captionH) }
    private var backRect: NSRect { NSRect(x: 4, y: 6, width: 40, height: 32) }

    private var tabWidth: CGFloat {
        let n = max(1, delegate?.tabs.count ?? 1)
        let avail = bounds.width - tabsX - 6 - 32 - captionW * 3 - 40
        return floor(min(240, max(64, avail / CGFloat(n))))
    }

    func tabRect(_ i: Int) -> NSRect {
        NSRect(x: tabsX + CGFloat(i) * tabWidth, y: tabY, width: tabWidth, height: tabH)
    }

    private func closeButtonRect(_ i: Int) -> NSRect {
        let t = tabRect(i)
        return NSRect(x: t.maxX - 38, y: t.minY + 4, width: 32, height: 24)
    }

    private var addRect: NSRect {
        let n = delegate?.tabs.count ?? 0
        return NSRect(x: tabsX + CGFloat(n) * tabWidth + 6, y: 12, width: 32, height: 32)
    }

    private func part(at p: NSPoint) -> Part {
        if closeRect.contains(p) { return .close }
        if maximizeRect.contains(p) { return .maximize }
        if minimizeRect.contains(p) { return .minimize }
        guard let d = delegate else { return .none }
        if d.isSettingsMode { return backRect.contains(p) ? .back : .none }
        for i in d.tabs.indices {
            if tabRect(i).contains(p) {
                return closeButtonRect(i).contains(p) ? .tabClose(i) : .tab(i)
            }
        }
        if addRect.contains(p) { return .add }
        return .none
    }

    // MARK: 그리기

    override func draw(_ dirtyRect: NSRect) {
        Theme.micaBase.setFill()
        bounds.fill()
        guard let d = delegate else { return }

        if d.isSettingsMode {
            drawSettingsHeader()
        } else {
            // 앱 아이콘
            Theme.appIcon.draw(in: NSRect(x: 18, y: 19, width: 16, height: 16), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            drawTabs(d)
            drawAddButton()
        }
        drawCaptionButtons()
    }

    private func drawSettingsHeader() {
        if hover == .back || pressed == .back {
            (pressed == .back ? Theme.subtlePressed : Theme.subtleHover).setFill()
            NSBezierPath(roundedRect: backRect, xRadius: 4, yRadius: 4).fill()
        }
        // ← 화살표
        let c = NSPoint(x: backRect.midX, y: backRect.midY)
        let p = NSBezierPath()
        p.move(to: NSPoint(x: c.x + 6, y: c.y)); p.line(to: NSPoint(x: c.x - 6, y: c.y))
        p.move(to: NSPoint(x: c.x - 1, y: c.y - 5)); p.line(to: NSPoint(x: c.x - 6, y: c.y)); p.line(to: NSPoint(x: c.x - 1, y: c.y + 5))
        p.lineWidth = 1.1; p.lineCapStyle = .round; p.lineJoinStyle = .round
        Theme.textPrimary.setStroke(); p.stroke()
        Theme.appIcon.draw(in: NSRect(x: 56, y: 14, width: 16, height: 16), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        drawText("메모장", x: 84, centerY: 22, font: Theme.ui(12), color: Theme.textPrimary)
    }

    private func selectedTabPath(_ r: NSRect) -> NSBezierPath {
        let rad: CGFloat = 8
        let p = NSBezierPath()
        let bottom = bounds.height
        p.move(to: NSPoint(x: r.minX - rad, y: bottom))
        p.appendArc(withCenter: NSPoint(x: r.minX - rad, y: bottom - rad), radius: rad, startAngle: 90, endAngle: 0, clockwise: true)
        p.line(to: NSPoint(x: r.minX, y: r.minY + rad))
        p.appendArc(withCenter: NSPoint(x: r.minX + rad, y: r.minY + rad), radius: rad, startAngle: 180, endAngle: 270, clockwise: false)
        p.line(to: NSPoint(x: r.maxX - rad, y: r.minY))
        p.appendArc(withCenter: NSPoint(x: r.maxX - rad, y: r.minY + rad), radius: rad, startAngle: 270, endAngle: 360, clockwise: false)
        p.line(to: NSPoint(x: r.maxX, y: bottom - rad))
        p.appendArc(withCenter: NSPoint(x: r.maxX + rad, y: bottom - rad), radius: rad, startAngle: 180, endAngle: 90, clockwise: true)
        return p
    }

    private func drawTabs(_ d: TitleBarDelegate) {
        let sel = d.selectedTabIndex
        let count = d.tabs.count
        // 구분선 (선택/호버되지 않은 인접 탭 사이)
        for i in 0..<count {
            let r = tabRect(i)
            let hovered = isHovered(tab: i)
            if i != sel && hovered {
                Theme.subtleHover.setFill()
                let hr = NSRect(x: r.minX, y: r.minY, width: r.width, height: r.height - 4)
                NSBezierPath(roundedRect: hr, xRadius: 6, yRadius: 6).fill()
            }
            if i < count - 1, i != sel, i + 1 != sel, !hovered, !isHovered(tab: i + 1) {
                Theme.separator.setFill()
                NSRect(x: r.maxX - 0.5, y: r.minY + 8, width: 1, height: 16).fill()
            }
        }
        if sel >= 0 && sel < count {
            let r = tabRect(sel).insetBy(dx: 0.5, dy: 0)
            let path = selectedTabPath(r)
            Theme.layer.setFill()
            path.fill()
            Theme.tabStroke.setStroke()
            path.lineWidth = 1
            NSGraphicsContext.saveGraphicsState()
            NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - 0.5).clip()
            path.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
        for i in 0..<count {
            let doc = d.tabs[i]
            let r = tabRect(i)
            let cb = closeButtonRect(i)
            let selected = i == sel
            let titleMax = cb.minX - (r.minX + 10) + 4
            drawText(doc.title, x: r.minX + 10, centerY: r.midY - 0.5, font: titleFont,
                     color: selected ? Theme.textPrimary : Theme.textSecondary, maxWidth: titleMax)

            let hovered = isHovered(tab: i)
            let closeHovered = hover == .tabClose(i)
            let c = NSPoint(x: cb.midX, y: cb.midY)
            if hovered || (selected && !doc.isModified) {
                if closeHovered {
                    (pressed == .tabClose(i) ? Theme.subtlePressed : Theme.subtleHover).setFill()
                    NSBezierPath(roundedRect: cb.insetBy(dx: 2, dy: 0), xRadius: 4, yRadius: 4).fill()
                }
                drawGlyph(.cancel, center: c, size: 12, color: selected || hovered ? Theme.textPrimary : Theme.textSecondary)
            } else if doc.isModified {
                drawGlyph(.dot, center: c, size: 12, color: Theme.modifiedDot)
            }
        }
    }

    private func isHovered(tab i: Int) -> Bool {
        if case .tab(let h) = hover, h == i { return true }
        if case .tabClose(let h) = hover, h == i { return true }
        return false
    }

    private func drawAddButton() {
        let r = addRect
        if hover == .add || pressed == .add {
            (pressed == .add ? Theme.subtlePressed : Theme.subtleHover).setFill()
            NSBezierPath(roundedRect: NSRect(x: r.minX, y: r.minY + 2, width: r.width, height: r.height - 6), xRadius: 4, yRadius: 4).fill()
        }
        let c = NSPoint(x: r.midX, y: r.midY - 1)
        let p = NSBezierPath()
        p.move(to: NSPoint(x: c.x - 4.5, y: c.y)); p.line(to: NSPoint(x: c.x + 4.5, y: c.y))
        p.move(to: NSPoint(x: c.x, y: c.y - 4.5)); p.line(to: NSPoint(x: c.x, y: c.y + 4.5))
        p.lineWidth = 1
        Theme.textPrimary.setStroke()
        p.stroke()
    }

    private func drawCaptionButtons() {
        let active = window?.isKeyWindow ?? true
        let glyphColor = active ? Theme.textPrimary : Theme.textTertiary
        for (part, rect) in [(Part.minimize, minimizeRect), (.maximize, maximizeRect), (.close, closeRect)] {
            var color = glyphColor
            if hover == part || pressed == part {
                if part == .close {
                    (pressed == part ? Theme.captionClosePressed : Theme.captionCloseHover).setFill()
                    color = .white
                } else {
                    (pressed == part ? Theme.subtlePressed : Theme.subtleHover).setFill()
                }
                rect.fill()
            }
            color.setStroke()
            let cx = rect.midX.rounded(.down), cy = rect.midY.rounded(.down)
            let p = NSBezierPath()
            p.lineWidth = 1
            switch part {
            case .minimize:
                p.move(to: NSPoint(x: cx - 5, y: cy + 0.5)); p.line(to: NSPoint(x: cx + 5, y: cy + 0.5))
            case .maximize:
                if delegate?.isMaximized == true {
                    p.append(NSBezierPath(roundedRect: NSRect(x: cx - 4.5, y: cy - 2.5, width: 7, height: 7), xRadius: 1, yRadius: 1))
                    p.move(to: NSPoint(x: cx - 2.5, y: cy - 4.5)); p.line(to: NSPoint(x: cx + 3.5, y: cy - 4.5))
                    p.curve(to: NSPoint(x: cx + 4.5, y: cy - 3.5), controlPoint1: NSPoint(x: cx + 4.1, y: cy - 4.5), controlPoint2: NSPoint(x: cx + 4.5, y: cy - 4.1))
                    p.line(to: NSPoint(x: cx + 4.5, y: cy + 2.5))
                } else {
                    p.append(NSBezierPath(roundedRect: NSRect(x: cx - 4.5, y: cy - 4.5, width: 10, height: 10), xRadius: 1, yRadius: 1))
                }
            default:
                p.move(to: NSPoint(x: cx - 4.5, y: cy - 4.5)); p.line(to: NSPoint(x: cx + 5.5, y: cy + 5.5))
                p.move(to: NSPoint(x: cx + 5.5, y: cy - 4.5)); p.line(to: NSPoint(x: cx - 4.5, y: cy + 5.5))
            }
            p.stroke()
        }
    }

    // MARK: 마우스

    private func updateToolTip() {
        if case .tab(let i) = hover, let d = delegate, i < d.tabs.count {
            toolTip = d.tabs[i].url?.path ?? d.tabs[i].title
        } else if case .tabClose = hover {
            toolTip = "탭 닫기"
        } else if hover == .add {
            toolTip = "새 탭 추가"
        } else if hover == .minimize {
            toolTip = "최소화"
        } else if hover == .maximize {
            toolTip = delegate?.isMaximized == true ? "이전 크기로 복원" : "최대화"
        } else if hover == .close {
            toolTip = "닫기"
        } else if hover == .back {
            toolTip = "뒤로"
        } else {
            toolTip = nil
        }
    }

    override func mouseMoved(with event: NSEvent) {
        hover = part(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        if pressed == .none { hover = .none }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let pt = part(at: p)
        switch pt {
        case .none:
            if event.clickCount == 2 { delegate?.titleBarToggleMaximize() } else { window?.performDrag(with: event) }
        case .tab(let i):
            delegate?.titleBarSelectTab(i)
            if (delegate?.tabs.count ?? 0) <= 1 {
                if event.clickCount == 2 { delegate?.titleBarToggleMaximize() } else { window?.performDrag(with: event) }
                return
            }
            dragIndex = i
            dragStart = p
            dragging = false
            dragOutside = false
        default:
            pressed = pt
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let di = dragIndex, let d = delegate {
            if !dragging && hypot(p.x - dragStart.x, p.y - dragStart.y) > 4 { dragging = true }
            guard dragging else { return }
            dragOutside = p.y < -20 || p.y > bounds.height + 24
            if dragOutside {
                NSCursor.closedHand.set()
                return
            }
            NSCursor.arrow.set()
            let target = max(0, min(d.tabs.count - 1, Int(floor((p.x - tabsX) / tabWidth))))
            if target != di {
                d.titleBarMoveTab(from: di, to: target)
                dragIndex = target
            }
            return
        }
        let pt = part(at: p)
        hover = pt
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let di = dragIndex {
            dragIndex = nil
            if dragging && dragOutside, let w = window {
                NSCursor.arrow.set()
                let sp = w.convertPoint(toScreen: event.locationInWindow)
                delegate?.titleBarDropTab(di, screenPoint: sp)
            }
            dragging = false
            return
        }
        let pt = part(at: p)
        let was = pressed
        pressed = .none
        guard pt == was else { return }
        switch pt {
        case .tabClose(let i): delegate?.titleBarCloseTab(i)
        case .add: delegate?.titleBarNewTab()
        case .minimize: hover = .none; delegate?.titleBarMinimize()
        case .maximize: hover = .none; delegate?.titleBarToggleMaximize()
        case .close: delegate?.titleBarClose()
        case .back: delegate?.titleBarBack()
        default: break
        }
    }

    override func otherMouseUp(with event: NSEvent) {
        // 가운데 클릭으로 탭 닫기
        let p = convert(event.locationInWindow, from: nil)
        switch part(at: p) {
        case .tab(let i), .tabClose(let i): delegate?.titleBarCloseTab(i)
        default: break
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        switch part(at: p) {
        case .tab(let i), .tabClose(let i): delegate?.titleBarTabContextMenu(i, event: event)
        default: break
        }
    }

    // 파일을 탭 표시줄에 놓아도 열기
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] else { return false }
        (window?.windowController as? NotepadWindowController)?.openFiles(urls)
        return true
    }
}

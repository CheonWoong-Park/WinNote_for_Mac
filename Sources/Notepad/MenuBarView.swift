import AppKit

protocol MenuBarDelegate: AnyObject {
    func menuBarItems(for index: Int) -> [FlyoutItem]
    func menuBarOpenSettings()
}

/// 파일 / 편집 / 보기 메뉴 바와 오른쪽 설정 버튼 (높이 32 + 구분선 1)
final class MenuBarView: NSView {
    static let height: CGFloat = 33
    weak var delegate: MenuBarDelegate?

    let titles = ["파일", "편집", "보기"]
    private let font = Theme.ui(14)
    private var hover: Int? { didSet { if hover != oldValue { needsDisplay = true } } }
    private var gearHover = false { didSet { if gearHover != oldValue { needsDisplay = true } } }
    private var gearPressed = false { didSet { needsDisplay = true } }
    private(set) var openIndex: Int? { didSet { needsDisplay = true } }
    private var tracking: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }

    func itemRect(_ i: Int) -> NSRect {
        let w = textWidth(titles[i], font) + 24
        return NSRect(x: 4 + CGFloat(i) * 56, y: 3, width: w, height: 26)
    }

    var gearRect: NSRect { NSRect(x: bounds.width - 37, y: 2, width: 33, height: 28) }

    override func draw(_ dirtyRect: NSRect) {
        Theme.layer.setFill()
        bounds.fill()
        Theme.divider.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()

        for i in titles.indices {
            let r = itemRect(i)
            if openIndex == i {
                Theme.subtlePressed.setFill()
                NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4).fill()
            } else if hover == i {
                Theme.subtleHover.setFill()
                NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4).fill()
            }
            drawText(titles[i], x: r.minX + 12, centerY: 16, font: font, color: Theme.textPrimary)
        }

        if gearHover || gearPressed {
            (gearPressed ? Theme.subtlePressed : Theme.subtleHover).setFill()
            NSBezierPath(roundedRect: gearRect, xRadius: 4, yRadius: 4).fill()
        }
        drawGlyph(.settings, center: NSPoint(x: gearRect.midX, y: 16), size: 16, color: Theme.textPrimary)
    }

    private func index(at p: NSPoint) -> Int? {
        titles.indices.first { itemRect($0).insetBy(dx: 0, dy: -3).contains(p) }
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let i = index(at: p)
        hover = i
        gearHover = gearRect.contains(p)
        if let i, let o = openIndex, i != o, FlyoutMenu.isOpen { open(i, keyboard: false) }
    }

    override func mouseExited(with event: NSEvent) {
        hover = nil
        gearHover = false
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if gearRect.contains(p) { gearPressed = true; return }
        guard let i = index(at: p) else {
            if event.clickCount == 2 { (window?.windowController as? NotepadWindowController)?.titleBarToggleMaximize() }
            return
        }
        // 같은 메뉴를 다시 누르면 닫기만 한다
        if FlyoutMenu.lastCloseAnchor === self, event.timestamp - FlyoutMenu.lastCloseTime < 0.05, lastClosedIndex == i {
            return
        }
        open(i, keyboard: false)
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if gearPressed {
            gearPressed = false
            if gearRect.contains(p) { delegate?.menuBarOpenSettings() }
        }
    }

    private var lastClosedIndex: Int?

    func open(_ i: Int, keyboard: Bool) {
        guard let window, let delegate else { return }
        let r = itemRect(i)
        let bottomLeft = convert(NSPoint(x: r.minX, y: bounds.height + 1), to: nil)
        let sp = window.convertPoint(toScreen: bottomLeft)
        let m = FlyoutMenu.show(items: delegate.menuBarItems(for: i), topLeft: sp, parentWindow: window, minWidth: 200,
                                anchor: self, selectFirst: keyboard) { [weak self] in
            self?.lastClosedIndex = self?.openIndex
            self?.openIndex = nil
        }
        openIndex = i
        m.onNavigateHorizontal = { [weak self] dir in
            guard let self else { return }
            let n = self.titles.count
            self.open(((self.openIndex ?? i) + dir + n) % n, keyboard: true)
        }
    }
}

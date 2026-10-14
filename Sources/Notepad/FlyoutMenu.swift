import AppKit

/// WinUI MenuFlyout 항목
final class FlyoutItem {
    let title: String
    let shortcut: String?
    let isSeparator: Bool
    var isEnabled: () -> Bool
    var isChecked: (() -> Bool)?
    var action: (() -> Void)?
    var submenu: (() -> [FlyoutItem])?

    init(_ title: String, shortcut: String? = nil, enabled: @escaping () -> Bool = { true },
         checked: (() -> Bool)? = nil, submenu: (() -> [FlyoutItem])? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.shortcut = shortcut
        self.isSeparator = false
        self.isEnabled = enabled
        self.isChecked = checked
        self.submenu = submenu
        self.action = action
    }

    private init(separator: Void) {
        title = ""; shortcut = nil; isSeparator = true; isEnabled = { false }
    }

    static func separator() -> FlyoutItem { FlyoutItem(separator: ()) }
}

/// Windows 11 스타일 메뉴 팝업 (둥근 모서리 8, 아크릴 배경, 그림자)
final class FlyoutMenu: NSPanel {
    private(set) static var root: FlyoutMenu?
    static var lastCloseTime: TimeInterval = 0
    static var lastCloseAnchor: AnyObject?

    let items: [FlyoutItem]
    private let menuView: FlyoutMenuView
    weak var parentMenu: FlyoutMenu?
    var child: FlyoutMenu?
    var onClose: (() -> Void)?
    /// 메뉴 바 좌우 이동 (방향 -1/+1)
    var onNavigateHorizontal: ((Int) -> Void)?
    weak var anchor: AnyObject?
    private var monitors: [Any] = []
    private var resignObserver: Any?

    static let rowHeight: CGFloat = 32
    static let separatorHeight: CGFloat = 9
    static let padding: CGFloat = 4

    private init(items: [FlyoutItem], minWidth: CGFloat) {
        self.items = items
        menuView = FlyoutMenuView(items: items, minWidth: minWidth)
        let maxH: CGFloat = 480
        var size = menuView.frame.size
        if size.height > maxH { size.height = maxH }
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        if size.height < menuView.frame.height {
            let container = FlyoutContainerView(frame: NSRect(origin: .zero, size: size))
            let sv = NSScrollView(frame: container.bounds.insetBy(dx: 1, dy: 4))
            sv.drawsBackground = false
            sv.hasVerticalScroller = true
            sv.scrollerStyle = .overlay
            sv.autohidesScrollers = true
            menuView.drawsChrome = false
            menuView.frame.size.width = sv.contentSize.width
            sv.documentView = menuView
            container.addSubview(sv)
            contentView = container
        } else {
            contentView = menuView
        }
        menuView.menu_ = self
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// 화면 좌표 기준 왼쪽 위 점에 메뉴 표시
    @discardableResult
    static func show(items: [FlyoutItem], topLeft: NSPoint, parentWindow: NSWindow?, minWidth: CGFloat = 120,
                     anchor: AnyObject? = nil, selectFirst: Bool = false, highlight: Int? = nil, onClose: (() -> Void)? = nil) -> FlyoutMenu {
        closeAll()
        let m = FlyoutMenu(items: items, minWidth: minWidth)
        m.anchor = anchor
        m.onClose = onClose
        m.appearance = parentWindow?.effectiveAppearance
        m.place(topLeft: topLeft, alternateRightEdge: nil)
        parentWindow?.addChildWindow(m, ordered: .above)
        m.orderFront(nil)
        m.invalidateShadow()
        root = m
        m.installMonitors()
        if selectFirst { m.menuView.moveHighlight(1) }
        if let h = highlight, items.indices.contains(h) {
            m.menuView.highlighted = h
            m.menuView.scrollToVisible(m.menuView.rect(forItem: h).insetBy(dx: 0, dy: -160))
        }
        return m
    }

    static func closeAll() {
        guard let r = root else { return }
        root = nil
        r.dismiss()
    }

    static var isOpen: Bool { root != nil }

    private func place(topLeft: NSPoint, alternateRightEdge: CGFloat?) {
        let size = frame.size
        var origin = NSPoint(x: topLeft.x, y: topLeft.y - size.height)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(topLeft) }) ?? NSScreen.main {
            let vf = screen.visibleFrame
            if origin.x + size.width > vf.maxX {
                if let alt = alternateRightEdge { origin.x = alt - size.width } else { origin.x = vf.maxX - size.width }
            }
            origin.x = max(vf.minX, origin.x)
            if origin.y < vf.minY { origin.y = vf.minY }
            if origin.y + size.height > vf.maxY { origin.y = vf.maxY - size.height }
        }
        setFrameOrigin(origin)
    }

    private func installMonitors() {
        let down = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] e in
            guard let self else { return e }
            if e.window is FlyoutMenu { return e }
            FlyoutMenu.lastCloseTime = e.timestamp
            FlyoutMenu.lastCloseAnchor = self.anchor
            FlyoutMenu.closeAll()
            return e
        }
        let key = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] e in
            guard let self else { return e }
            return self.handleKey(e) ? nil : e
        }
        let scroll = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { e in
            if e.window is FlyoutMenu { return e }
            FlyoutMenu.closeAll(); return e
        }
        monitors = [down, key, scroll].compactMap { $0 }
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            FlyoutMenu.closeAll()
        }
    }

    private func dismiss() {
        child?.dismiss()
        child = nil
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        if let o = resignObserver { NotificationCenter.default.removeObserver(o) }
        parent?.removeChildWindow(self)
        orderOut(nil)
        onClose?()
        onClose = nil
    }

    private var deepest: FlyoutMenu { child?.deepest ?? self }

    private func handleKey(_ e: NSEvent) -> Bool {
        let m = deepest
        switch e.keyCode {
        case 125: m.menuView.moveHighlight(1); return true          // ↓
        case 126: m.menuView.moveHighlight(-1); return true         // ↑
        case 124:                                                    // →
            if let i = m.menuView.highlighted, m.items[i].submenu != nil, m.items[i].isEnabled() {
                m.openSubmenu(at: i, selectFirst: true)
            } else { onNavigateHorizontal?(1) }
            return true
        case 123:                                                    // ←
            if let p = m.parentMenu { p.closeChild() } else { onNavigateHorizontal?(-1) }
            return true
        case 36, 76, 49:                                             // Enter, Space
            if let i = m.menuView.highlighted { m.activate(i) }
            return true
        case 53:                                                     // Esc
            if let p = m.parentMenu { p.closeChild() } else { FlyoutMenu.closeAll() }
            return true
        default:
            // 메뉴가 열린 동안 다른 키는 삼킨다 (Windows 동작)
            return !e.modifierFlags.contains(.command)
        }
    }

    func closeChild() {
        child?.dismiss()
        child = nil
    }

    func openSubmenu(at index: Int, selectFirst: Bool = false) {
        guard let sub = items[index].submenu else { return }
        if child != nil, menuView.submenuIndex == index { if selectFirst { child?.menuView.moveHighlight(1) }; return }
        closeChild()
        let subItems = sub()
        if subItems.isEmpty { return }
        let m = FlyoutMenu(items: subItems, minWidth: 120)
        m.parentMenu = self
        m.appearance = appearance
        let rowRect = menuView.rect(forItem: index)
        let screenRect = convertToScreen(menuView.convert(rowRect, to: nil))
        m.place(topLeft: NSPoint(x: frame.maxX - 4, y: screenRect.maxY + FlyoutMenu.padding), alternateRightEdge: frame.minX + 4)
        addChildWindow(m, ordered: .above)
        m.orderFront(nil)
        m.invalidateShadow()
        child = m
        menuView.submenuIndex = index
        if selectFirst { m.menuView.moveHighlight(1) }
    }

    func activate(_ index: Int) {
        let item = items[index]
        guard item.isEnabled(), !item.isSeparator else { return }
        if item.submenu != nil { openSubmenu(at: index, selectFirst: true); return }
        let action = item.action
        FlyoutMenu.closeAll()
        DispatchQueue.main.async { action?() }
    }
}

final class FlyoutMenuView: NSView {
    let items: [FlyoutItem]
    weak var menu_: FlyoutMenu?
    var highlighted: Int? { didSet { needsDisplay = true } }
    var submenuIndex: Int?
    private let hasChecks: Bool
    private let titleFont = Theme.ui(14)
    private let shortcutFont = Theme.ui(12)
    private var tracking: NSTrackingArea?

    override var isFlipped: Bool { true }

    init(items: [FlyoutItem], minWidth: CGFloat) {
        self.items = items
        hasChecks = items.contains { $0.isChecked != nil }
        var w: CGFloat = minWidth
        var h: CGFloat = FlyoutMenu.padding * 2
        let left: CGFloat = hasChecks ? 44 : 16
        for it in items {
            if it.isSeparator { h += FlyoutMenu.separatorHeight; continue }
            h += FlyoutMenu.rowHeight
            var iw = left + textWidth(it.title, Theme.ui(14)) + 16
            if let s = it.shortcut { iw += 40 + textWidth(s, Theme.ui(12)) }
            if it.submenu != nil { iw += 40 }
            w = max(w, iw)
        }
        super.init(frame: NSRect(x: 0, y: 0, width: ceil(w), height: ceil(h)))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }

    var drawsChrome = true

    func rect(forItem index: Int) -> NSRect {
        var y = FlyoutMenu.padding
        for (i, it) in items.enumerated() {
            let h = it.isSeparator ? FlyoutMenu.separatorHeight : FlyoutMenu.rowHeight
            if i == index { return NSRect(x: 0, y: y, width: bounds.width, height: h) }
            y += h
        }
        return .zero
    }

    private func index(at p: NSPoint) -> Int? {
        for i in items.indices where !items[i].isSeparator {
            if rect(forItem: i).contains(p) { return i }
        }
        return nil
    }

    func moveHighlight(_ dir: Int) {
        let n = items.count
        guard n > 0 else { return }
        var i = highlighted ?? (dir > 0 ? -1 : n)
        for _ in 0..<n {
            i = (i + dir + n) % n
            if !items[i].isSeparator && items[i].isEnabled() { highlighted = i; scrollToVisible(rect(forItem: i)); return }
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let i = index(at: p)
        if i != highlighted { highlighted = i }
        if let i, items[i].submenu != nil, items[i].isEnabled() {
            menu_?.openSubmenu(at: i)
        } else if i != nil, menu_?.child != nil {
            menu_?.closeChild()
            submenuIndex = nil
        }
    }

    override func mouseExited(with event: NSEvent) {
        if menu_?.child == nil { highlighted = nil }
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let i = index(at: p) { menu_?.activate(i) }
    }

    override func draw(_ dirtyRect: NSRect) {
        if drawsChrome { FlyoutContainerView.drawChrome(in: bounds) }

        let left: CGFloat = hasChecks ? 44 : 16
        for (i, it) in items.enumerated() {
            let rr = rect(forItem: i)
            if it.isSeparator {
                Theme.separator.setFill()
                NSRect(x: 0, y: rr.midY.rounded(.down), width: bounds.width, height: 1).fill()
                continue
            }
            let enabled = it.isEnabled()
            if i == highlighted && enabled {
                Theme.subtleHover.setFill()
                NSBezierPath(roundedRect: rr.insetBy(dx: 4, dy: 2), xRadius: 4, yRadius: 4).fill()
            }
            let color = enabled ? Theme.textPrimary : Theme.textDisabled
            if let c = it.isChecked, c() {
                drawCheck(center: NSPoint(x: 26, y: rr.midY), color: color)
            }
            drawText(it.title, x: left, centerY: rr.midY, font: titleFont, color: color)
            if let s = it.shortcut {
                let w = textWidth(s, shortcutFont)
                drawText(s, x: bounds.width - 16 - w, centerY: rr.midY, font: shortcutFont, color: enabled ? Theme.textSecondary : Theme.textDisabled)
            }
            if it.submenu != nil {
                drawGlyph(.chevronRight, center: NSPoint(x: bounds.width - 22, y: rr.midY), size: 12, color: color)
            }
        }
    }

    private func drawCheck(center c: NSPoint, color: NSColor) {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: c.x - 6, y: c.y))
        p.line(to: NSPoint(x: c.x - 2, y: c.y + 4))
        p.line(to: NSPoint(x: c.x + 6, y: c.y - 5))
        p.lineWidth = 1.3
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        color.setStroke()
        p.stroke()
    }
}

final class FlyoutContainerView: NSView {
    override var isFlipped: Bool { true }
    static func drawChrome(in bounds: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        Theme.flyoutBackground.setFill()
        path.fill()
        Theme.flyoutStroke.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
    override func draw(_ dirtyRect: NSRect) { FlyoutContainerView.drawChrome(in: bounds) }
}

import AppKit

/// 클릭 가능한 WinUI 스타일 컨트롤의 공통 기반
class WinControl: NSView {
    var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }
    var isPressed = false { didSet { if isPressed != oldValue { needsDisplay = true } } }
    var isEnabled = true { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?
    private var tracking: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseDown(with event: NSEvent) { if isEnabled { isPressed = true } }
    override func mouseDragged(with event: NSEvent) {
        isPressed = isEnabled && bounds.contains(convert(event.locationInWindow, from: nil))
    }
    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        if inside && isEnabled { clicked() }
    }
    func clicked() { onClick?() }
}

/// WinUI Button (표준 / 강조)
final class WinButton: WinControl {
    enum Style { case standard, accent, subtle }
    var title: String { didSet { needsDisplay = true } }
    var style: Style
    var glyph: Glyph?
    var glyphSize: CGFloat = 16
    var font = Theme.ui(14)

    init(title: String = "", style: Style = .standard, glyph: Glyph? = nil) {
        self.title = title
        self.style = style
        self.glyph = glyph
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    var preferredWidth: CGFloat { glyph != nil && title.isEmpty ? 32 : max(96, textWidth(title, font) + 24) }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4)
        var textColor = Theme.textPrimary
        switch style {
        case .accent:
            (isEnabled ? (isPressed ? Theme.accentHover.withAlphaComponent(0.8) : isHovered ? Theme.accentHover : Theme.accent) : Theme.textDisabled).setFill()
            path.fill()
            textColor = isEnabled ? Theme.textOnAccent : Theme.textOnAccent.withAlphaComponent(0.7)
        case .standard:
            (isPressed ? Theme.subtlePressed : isHovered ? Theme.controlFillHover : Theme.controlFill).setFill()
            path.fill()
            Theme.controlStroke.setStroke()
            path.lineWidth = 1
            path.stroke()
            Theme.controlStrokeSecondary.setFill()
            if !isPressed {
                NSBezierPath(roundedRect: NSRect(x: r.minX + 3, y: r.maxY - 0.5, width: r.width - 6, height: 1), xRadius: 0.5, yRadius: 0.5).fill()
            }
            if isPressed { textColor = Theme.textSecondary }
        case .subtle:
            if isHovered || isPressed {
                (isPressed ? Theme.subtlePressed : Theme.subtleHover).setFill()
                path.fill()
            }
        }
        if !isEnabled && style != .accent { textColor = Theme.textDisabled }
        if let g = glyph, title.isEmpty {
            drawGlyph(g, center: NSPoint(x: bounds.midX, y: bounds.midY), size: glyphSize, color: textColor)
        } else {
            let w = textWidth(title, font)
            drawText(title, x: round(bounds.midX - w / 2), centerY: bounds.midY, font: font, color: textColor)
        }
    }
}

/// 포커스 상태를 컨테이너에 알리는 NSTextField
final class InnerTextField: NSTextField {
    var onFocusChange: ((Bool) -> Void)?
    var onKey: ((NSEvent) -> Bool)?

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocusChange?(true) }
        return ok
    }
    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        onFocusChange?(false)
    }
}

/// WinUI TextBox (높이 32, 아래 강조선)
final class WinTextBox: NSView, NSTextFieldDelegate {
    let field = InnerTextField()
    private(set) var focused = false { didSet { needsDisplay = true } }
    var onChange: ((String) -> Void)?
    var onEnter: ((_ shift: Bool) -> Void)?
    var onEscape: (() -> Void)?
    var rightInset: CGFloat = 0 { didSet { needsLayout = true } }

    override var isFlipped: Bool { true }

    init(placeholder: String = "") {
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 32))
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Theme.ui(14)
        field.textColor = Theme.textPrimary
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [.font: Theme.ui(14), .foregroundColor: Theme.textSecondary])
        field.delegate = self
        field.onFocusChange = { [weak self] f in self?.focused = f }
        addSubview(field)
    }
    required init?(coder: NSCoder) { fatalError() }

    var stringValue: String {
        get { field.stringValue }
        set { field.stringValue = newValue }
    }

    override func layout() {
        super.layout()
        let h: CGFloat = 20
        field.frame = NSRect(x: 9, y: round((bounds.height - h) / 2), width: bounds.width - 18 - rightInset, height: h)
    }

    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4)
        (focused ? Theme.controlFillInputActive : Theme.controlFill).setFill()
        path.fill()
        Theme.controlStroke.setStroke()
        path.lineWidth = 1
        path.stroke()
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        if focused {
            Theme.accent.setFill()
            NSRect(x: 0, y: bounds.height - 2, width: bounds.width, height: 2).fill()
        } else {
            Theme.controlStrongStroke.setFill()
            NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(field) }

    func focus(selectAll: Bool = true) {
        window?.makeFirstResponder(field)
        if selectAll { field.currentEditor()?.selectAll(nil) }
    }

    func controlTextDidChange(_ obj: Notification) { onChange?(field.stringValue) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) {
            onEnter?(NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false); return true
        }
        if sel == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) { onEnter?(true); return true }
        if sel == #selector(NSResponder.cancelOperation(_:)) { onEscape?(); return onEscape != nil }
        return false
    }
}

/// WinUI ToggleSwitch ("켬"/"끔" 레이블 포함)
final class WinToggle: WinControl {
    var isOn: Bool { didSet { needsDisplay = true } }
    var onToggle: ((Bool) -> Void)?

    init(isOn: Bool) {
        self.isOn = isOn
        super.init(frame: NSRect(x: 0, y: 0, width: 80, height: 32))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func clicked() {
        isOn.toggle()
        onToggle?(isOn)
    }

    override func draw(_ dirtyRect: NSRect) {
        let label = isOn ? "켬" : "끔"
        let font = Theme.ui(14)
        let sw = NSRect(x: bounds.width - 40, y: round(bounds.midY - 10), width: 40, height: 20)
        drawText(label, x: sw.minX - 12 - textWidth(label, font), centerY: bounds.midY, font: font, color: Theme.textPrimary)
        let pill = NSBezierPath(roundedRect: sw.insetBy(dx: 0.5, dy: 0.5), xRadius: 9.5, yRadius: 9.5)
        let knobD: CGFloat = isPressed ? 14 : (isHovered ? 14 : 12)
        if isOn {
            (isHovered ? Theme.accentHover : Theme.accent).setFill()
            pill.fill()
            Theme.textOnAccent.setFill()
            NSBezierPath(ovalIn: NSRect(x: sw.maxX - 10 - knobD / 2, y: sw.midY - knobD / 2, width: knobD, height: knobD)).fill()
        } else {
            (isHovered ? Theme.subtleHover : Theme.controlFill).setFill()
            pill.fill()
            Theme.textSecondary.setStroke()
            pill.lineWidth = 1
            pill.stroke()
            Theme.textSecondary.setFill()
            NSBezierPath(ovalIn: NSRect(x: sw.minX + 10 - knobD / 2, y: sw.midY - knobD / 2, width: knobD, height: knobD)).fill()
        }
    }
}

/// WinUI RadioButton
final class WinRadio: WinControl {
    let title: String
    var isSelected: Bool { didSet { needsDisplay = true } }

    init(title: String, selected: Bool) {
        self.title = title
        self.isSelected = selected
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 32))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let c = NSRect(x: 0.5, y: round(bounds.midY - 10) + 0.5, width: 19, height: 19)
        let outer = NSBezierPath(ovalIn: c)
        if isSelected {
            Theme.accent.setFill()
            outer.fill()
            Theme.textOnAccent.setFill()
            let d: CGFloat = isPressed ? 8 : (isHovered ? 12 : 10)
            NSBezierPath(ovalIn: NSRect(x: c.midX - d / 2, y: c.midY - d / 2, width: d, height: d)).fill()
        } else {
            (isHovered ? Theme.subtleHover : Theme.controlFill).setFill()
            outer.fill()
            Theme.controlStrongStroke.setStroke()
            outer.lineWidth = 1
            outer.stroke()
        }
        drawText(title, x: 28, centerY: bounds.midY, font: Theme.ui(14), color: Theme.textPrimary)
    }
}

/// WinUI ComboBox (펼침 목록은 FlyoutMenu 사용)
final class WinComboBox: WinControl {
    var options: [String] { didSet { needsDisplay = true } }
    var displayNames: [String]?
    var selectedIndex: Int { didSet { needsDisplay = true } }
    var onSelect: ((Int) -> Void)?

    init(options: [String], selected: Int) {
        self.options = options
        self.selectedIndex = selected
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 32))
    }
    required init?(coder: NSCoder) { fatalError() }

    private func name(_ i: Int) -> String { (displayNames?[i]) ?? options[i] }

    override func clicked() {
        guard let window, !options.isEmpty else { return }
        let items = options.indices.map { i in
            FlyoutItem(name(i), checked: { [weak self] in self?.selectedIndex == i }) { [weak self] in
                self?.selectedIndex = i
                self?.onSelect?(i)
            }
        }
        let p = window.convertPoint(toScreen: convert(NSPoint(x: 0, y: bounds.height + 2), to: nil))
        FlyoutMenu.show(items: items, topLeft: p, parentWindow: window, minWidth: bounds.width, highlight: selectedIndex)
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4)
        (isPressed ? Theme.subtlePressed : isHovered ? Theme.controlFillHover : Theme.controlFill).setFill()
        path.fill()
        Theme.controlStroke.setStroke()
        path.lineWidth = 1
        path.stroke()
        Theme.controlStrokeSecondary.setFill()
        NSBezierPath(roundedRect: NSRect(x: r.minX + 3, y: r.maxY - 0.5, width: r.width - 6, height: 1), xRadius: 0.5, yRadius: 0.5).fill()
        if options.indices.contains(selectedIndex) {
            drawText(name(selectedIndex), x: 11, centerY: bounds.midY, font: Theme.ui(14), color: Theme.textPrimary, maxWidth: bounds.width - 44)
        }
        drawGlyph(.chevronDown, center: NSPoint(x: bounds.width - 20, y: bounds.midY), size: 12, color: Theme.textSecondary)
    }
}

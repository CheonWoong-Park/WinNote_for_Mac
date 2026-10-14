import AppKit

/// Windows 11 메모장 찾기/바꾸기 상자
final class FindBar: NSView {
    let findBox = WinTextBox(placeholder: "찾기")
    let replaceBox = WinTextBox(placeholder: "바꾸기")
    private let expandButton = WinButton(style: .subtle, glyph: .chevronDown)
    private let nextButton = WinButton(style: .subtle, glyph: .down)
    private let prevButton = WinButton(style: .subtle, glyph: .up)
    private let optionsButton = WinButton(style: .subtle, glyph: .equalizer)
    private let closeButton = WinButton(style: .subtle, glyph: .cancel)
    private let replaceButton = WinButton(title: "바꾸기")
    private let replaceAllButton = WinButton(title: "모두 바꾸기")

    var matchCase = false
    var wrapAround = true
    private(set) var isReplaceVisible = false

    var onSearch: ((_ forward: Bool, _ incremental: Bool) -> Void)?
    var onReplace: (() -> Void)?
    var onReplaceAll: (() -> Void)?
    var onClose: (() -> Void)?
    var onLayoutChange: (() -> Void)?

    static let width: CGFloat = 452
    static let rowHeight: CGFloat = 40

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: FindBar.width, height: FindBar.rowHeight + 8))
        wantsLayer = true
        shadow = {
            let s = NSShadow()
            s.shadowColor = NSColor.black.withAlphaComponent(0.14)
            s.shadowBlurRadius = 16
            s.shadowOffset = NSSize(width: 0, height: -6)
            return s
        }()
        for b in [expandButton, nextButton, prevButton, optionsButton, closeButton] { b.glyphSize = 14 }
        expandButton.glyphSize = 12
        closeButton.glyphSize = 12
        nextButton.toolTip = "다음 찾기"
        prevButton.toolTip = "이전 찾기"
        optionsButton.toolTip = "추가 옵션"
        closeButton.toolTip = "찾기 및 바꾸기 닫기"
        expandButton.toolTip = "바꾸기 옵션 토글"
        [expandButton, findBox, nextButton, prevButton, optionsButton, closeButton, replaceBox, replaceButton, replaceAllButton].forEach(addSubview)
        replaceBox.isHidden = true
        replaceButton.isHidden = true
        replaceAllButton.isHidden = true

        expandButton.onClick = { [weak self] in self?.setReplaceVisible(!(self?.isReplaceVisible ?? false)) }
        nextButton.onClick = { [weak self] in self?.onSearch?(true, false) }
        prevButton.onClick = { [weak self] in self?.onSearch?(false, false) }
        closeButton.onClick = { [weak self] in self?.onClose?() }
        optionsButton.onClick = { [weak self] in self?.showOptions() }
        replaceButton.onClick = { [weak self] in self?.onReplace?() }
        replaceAllButton.onClick = { [weak self] in self?.onReplaceAll?() }
        findBox.onChange = { [weak self] _ in self?.onSearch?(true, true) }
        findBox.onEnter = { [weak self] shift in self?.onSearch?(!shift, false) }
        findBox.onEscape = { [weak self] in self?.onClose?() }
        replaceBox.onEnter = { [weak self] _ in self?.onReplace?() }
        replaceBox.onEscape = { [weak self] in self?.onClose?() }
    }
    required init?(coder: NSCoder) { fatalError() }

    func setReplaceVisible(_ v: Bool) {
        isReplaceVisible = v
        replaceBox.isHidden = !v
        replaceButton.isHidden = !v
        replaceAllButton.isHidden = !v
        expandButton.glyph = v ? .chevronUp : .chevronDown
        expandButton.needsDisplay = true
        setFrameSize(NSSize(width: FindBar.width, height: FindBar.rowHeight * (v ? 2 : 1) + 8))
        needsLayout = true
        onLayoutChange?()
    }

    private func showOptions() {
        guard let window else { return }
        let items = [
            FlyoutItem("대/소문자 구분", checked: { [weak self] in self?.matchCase ?? false }) { [weak self] in self?.matchCase.toggle() },
            FlyoutItem("줄 바꿈", checked: { [weak self] in self?.wrapAround ?? false }) { [weak self] in self?.wrapAround.toggle() },
        ]
        let p = window.convertPoint(toScreen: optionsButton.convert(NSPoint(x: 0, y: optionsButton.bounds.height + 4), to: nil))
        FlyoutMenu.show(items: items, topLeft: p, parentWindow: window, minWidth: 160)
    }

    override func layout() {
        super.layout()
        let pad: CGFloat = 4
        let b: CGFloat = 32
        let y1 = pad + 4
        expandButton.frame = NSRect(x: pad + 4, y: y1, width: b, height: b)
        closeButton.frame = NSRect(x: bounds.width - pad - 4 - b, y: y1, width: b, height: b)
        optionsButton.frame = closeButton.frame.offsetBy(dx: -(b + 4), dy: 0)
        prevButton.frame = optionsButton.frame.offsetBy(dx: -(b + 4), dy: 0)
        nextButton.frame = prevButton.frame.offsetBy(dx: -(b + 2), dy: 0)
        let fx = expandButton.frame.maxX + 4
        findBox.frame = NSRect(x: fx, y: y1, width: nextButton.frame.minX - 6 - fx, height: b)
        let y2 = y1 + FindBar.rowHeight
        let raW = replaceAllButton.preferredWidth
        let rW = max(72, replaceButton.preferredWidth - 24)
        replaceAllButton.frame = NSRect(x: bounds.width - pad - 4 - raW, y: y2, width: raW, height: b)
        replaceButton.frame = NSRect(x: replaceAllButton.frame.minX - 6 - rW, y: y2, width: rW, height: b)
        replaceBox.frame = NSRect(x: fx, y: y2, width: replaceButton.frame.minX - 6 - fx, height: b)
    }

    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        Theme.flyoutBackground.setFill()
        path.fill()
        Theme.flyoutStroke.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    // 찾기 상자 위 클릭이 아래 편집기로 전달되지 않게
    override func mouseDown(with event: NSEvent) {}
}

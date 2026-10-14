import AppKit

/// WinUI ContentDialog (창 안에서 뜨는 모달)
final class ContentDialog: NSView {
    enum Result { case primary, secondary, close }

    private let card = DialogCard()
    private var buttons: [(WinButton, Result)] = []
    private let completion: (Result) -> Void
    private let defaultResult: Result?
    private let content: NSView?
    private let messageField: NSTextField?
    private let titleField: NSTextField
    var initialFocus: NSView?
    var shouldClose: ((Result) -> Bool)?

    private let cardWidth: CGFloat
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(title: String, message: String? = nil, content: NSView? = nil, primary: String? = nil, secondary: String? = nil,
         close: String? = nil, defaultResult: Result? = .primary, width: CGFloat = 448, completion: @escaping (Result) -> Void) {
        self.completion = completion
        self.defaultResult = defaultResult
        self.content = content
        self.cardWidth = width
        titleField = NSTextField(labelWithString: title)
        titleField.font = Theme.semibold(20)
        titleField.textColor = Theme.textPrimary
        titleField.lineBreakMode = .byTruncatingTail
        if let message {
            let m = NSTextField(wrappingLabelWithString: message)
            m.font = Theme.ui(14)
            m.textColor = Theme.textPrimary
            m.isSelectable = false
            messageField = m
        } else { messageField = nil }
        super.init(frame: .zero)

        addSubview(card)
        card.addSubview(titleField)
        if let m = messageField { card.addSubview(m) }
        if let content { card.addSubview(content) }
        for (t, r) in [(primary, Result.primary), (secondary, .secondary), (close, .close)] {
            guard let t else { continue }
            let b = WinButton(title: t, style: r == defaultResult ? .accent : .standard)
            b.onClick = { [weak self] in self?.finish(r) }
            card.addSubview(b)
            buttons.append((b, r))
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    func present(in host: NSView) {
        frame = host.bounds
        autoresizingMask = [.width, .height]
        host.addSubview(self)
        needsLayout = true
        layoutSubtreeIfNeeded()
        window?.makeFirstResponder(initialFocus ?? self)
        if let tb = initialFocus as? WinTextBox { tb.focus() }
    }

    func finish(_ r: Result) {
        if let s = shouldClose, !s(r) { return }
        removeFromSuperview()
        completion(r)
    }

    override func layout() {
        super.layout()
        let pad: CGFloat = 24
        let innerW = cardWidth - pad * 2
        var y = pad
        titleField.frame = NSRect(x: pad, y: y, width: innerW, height: 28)
        y += 28 + 12
        if let m = messageField {
            m.preferredMaxLayoutWidth = innerW
            let h = ceil(m.sizeThatFits(NSSize(width: innerW, height: 1000)).height)
            m.frame = NSRect(x: pad, y: y, width: innerW, height: h)
            y += h + 8
        }
        if let c = content {
            c.frame = NSRect(x: pad, y: y, width: innerW, height: c.frame.height)
            y += c.frame.height + 8
        }
        y += 16
        let footerH: CGFloat = 80
        card.footerTop = y
        let n = CGFloat(buttons.count)
        let gap: CGFloat = 8
        let bw = floor((innerW - gap * (n - 1)) / max(1, n))
        for (i, (b, _)) in buttons.enumerated() {
            b.frame = NSRect(x: pad + CGFloat(i) * (bw + gap), y: y + pad, width: bw, height: 32)
        }
        let h = y + footerH
        card.frame = NSRect(x: round((bounds.width - cardWidth) / 2), y: round((bounds.height - h) / 2), width: cardWidth, height: h)
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.smoke.setFill()
        bounds.fill()
    }

    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: if let d = defaultResult { finish(d) }
        case 53: finish(buttons.contains { $0.1 == .close } ? .close : (buttons.last?.1 ?? .close))
        default: break
        }
    }

    override func cancelOperation(_ sender: Any?) {
        finish(buttons.contains { $0.1 == .close } ? .close : (buttons.last?.1 ?? .close))
    }
}

private final class DialogCard: NSView {
    var footerTop: CGFloat = 0 { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        shadow = {
            let s = NSShadow()
            s.shadowColor = NSColor.black.withAlphaComponent(0.26)
            s.shadowBlurRadius = 32
            s.shadowOffset = NSSize(width: 0, height: -16)
            return s
        }()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        Theme.dialogBackground.setFill()
        path.fill()
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        Theme.dialogFooter.setFill()
        NSRect(x: 0, y: footerTop, width: bounds.width, height: bounds.height - footerTop).fill()
        Theme.cardStroke.setFill()
        NSRect(x: 0, y: footerTop, width: bounds.width, height: 1).fill()
        NSGraphicsContext.restoreGraphicsState()
        Theme.flyoutStroke.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

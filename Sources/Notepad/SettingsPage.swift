import AppKit

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// 설정 카드 (아이콘, 제목, 설명, 오른쪽 컨트롤)
class SettingsCard: NSView {
    let glyph: Glyph?
    let title: String
    let desc: String?
    var trailing: NSView? { didSet { oldValue?.removeFromSuperview(); if let t = trailing { addSubview(t) }; needsLayout = true } }
    static let headerHeight: CGFloat = 68
    var roundBottom = true

    override var isFlipped: Bool { true }

    init(glyph: Glyph?, title: String, desc: String? = nil, trailing: NSView? = nil) {
        self.glyph = glyph
        self.title = title
        self.desc = desc
        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: SettingsCard.headerHeight))
        self.trailing = trailing
        if let t = trailing { addSubview(t) }
    }
    required init?(coder: NSCoder) { fatalError() }

    var headerHeight: CGFloat { SettingsCard.headerHeight }

    override func layout() {
        super.layout()
        if let t = trailing {
            t.frame = NSRect(x: bounds.width - 16 - t.frame.width, y: round((headerHeight - t.frame.height) / 2), width: t.frame.width, height: t.frame.height)
        }
    }

    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }

    func drawHeader(hovered: Bool) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        Theme.cardBackground.setFill()
        path.fill()
        if hovered {
            Theme.subtleHover.setFill()
            NSBezierPath(roundedRect: NSRect(x: 0.5, y: 0.5, width: bounds.width - 1, height: headerHeight - 1), xRadius: 4, yRadius: 4).fill()
        }
        Theme.cardStroke.setStroke()
        path.lineWidth = 1
        path.stroke()
        if let g = glyph { drawGlyph(g, center: NSPoint(x: 28, y: headerHeight / 2), size: 16, color: Theme.textPrimary) }
        let tx: CGFloat = glyph == nil ? 16 : 56
        let maxW = bounds.width - tx - 16 - (trailing?.frame.width ?? 0) - 120
        if let d = desc {
            drawText(title, x: tx, centerY: headerHeight / 2 - 9, font: Theme.ui(14), color: Theme.textPrimary, maxWidth: max(80, maxW))
            drawText(d, x: tx, centerY: headerHeight / 2 + 10, font: Theme.ui(12), color: Theme.textSecondary, maxWidth: max(80, maxW))
        } else {
            drawText(title, x: tx, centerY: headerHeight / 2, font: Theme.ui(14), color: Theme.textPrimary)
        }
    }

    override func draw(_ dirtyRect: NSRect) { drawHeader(hovered: false) }
}

/// 펼침 카드 (WinUI Expander)
final class ExpanderCard: SettingsCard {
    var value: (() -> String)?
    let body: NSView
    let bodyHeight: CGFloat
    var expanded = false { didSet { onToggle?(); needsDisplay = true } }
    var onToggle: (() -> Void)?
    private var hovered = false { didSet { if hovered != oldValue { needsDisplay = true } } }
    private var tracking: NSTrackingArea?

    init(glyph: Glyph?, title: String, desc: String? = nil, body: NSView, bodyHeight: CGFloat, value: (() -> String)? = nil) {
        self.body = body
        self.bodyHeight = bodyHeight
        self.value = value
        super.init(glyph: glyph, title: title, desc: desc)
        addSubview(body)
        body.isHidden = true
    }
    required init?(coder: NSCoder) { fatalError() }

    var totalHeight: CGFloat { headerHeight + (expanded ? bodyHeight : 0) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }
    override func mouseMoved(with event: NSEvent) { hovered = convert(event.locationInWindow, from: nil).y < headerHeight }
    override func mouseExited(with event: NSEvent) { hovered = false }

    override func layout() {
        super.layout()
        body.isHidden = !expanded
        body.frame = NSRect(x: 0, y: headerHeight, width: bounds.width, height: bodyHeight)
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if p.y < headerHeight { expanded.toggle() }
    }

    override func draw(_ dirtyRect: NSRect) {
        drawHeader(hovered: hovered)
        if expanded {
            Theme.cardStroke.setFill()
            NSRect(x: 1, y: headerHeight, width: bounds.width - 2, height: 1).fill()
        }
        drawGlyph(expanded ? .chevronUp : .chevronDown, center: NSPoint(x: bounds.width - 30, y: headerHeight / 2), size: 12, color: Theme.textPrimary)
        if let v = value?() {
            let w = textWidth(v, Theme.ui(14))
            drawText(v, x: bounds.width - 56 - w, centerY: headerHeight / 2, font: Theme.ui(14), color: Theme.textSecondary)
        }
    }
}

/// 설정 페이지
final class SettingsPage: NSView {
    private let scroll = NSScrollView()
    private let doc = FlippedView()
    private var rows: [(NSView, CGFloat)] = []   // (뷰, 위쪽 간격)
    private var themeCard: ExpanderCard!
    private var startupCard: ExpanderCard!
    private var openCard: ExpanderCard!
    private var fontCard: ExpanderCard!
    private var familyCombo: WinComboBox!
    private var faceCombo: WinComboBox!
    private var sizeCombo: WinComboBox!
    private var preview: NSTextField!

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = doc
        addSubview(scroll)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        Theme.layer.setFill()
        bounds.fill()
    }

    private func label(_ s: String, font: NSFont, color: NSColor = Theme.textPrimary, height: CGFloat) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = font
        l.textColor = color
        l.frame.size.height = height
        return l
    }

    private func toggle(_ get: @escaping () -> Bool, _ set: @escaping (Bool) -> Void) -> WinToggle {
        let t = WinToggle(isOn: get())
        t.frame.size = NSSize(width: 90, height: 32)
        t.onToggle = set
        return t
    }

    private func radioGroup(_ titles: [String], selected: Int, onSelect: @escaping (Int) -> Void) -> (NSView, CGFloat) {
        let v = FlippedView()
        var radios: [WinRadio] = []
        for (i, t) in titles.enumerated() {
            let r = WinRadio(title: t, selected: i == selected)
            r.frame = NSRect(x: 56, y: 12 + CGFloat(i) * 36, width: 480, height: 32)
            v.addSubview(r)
            radios.append(r)
        }
        for (i, r) in radios.enumerated() {
            r.onClick = {
                radios.forEach { $0.isSelected = false }
                r.isSelected = true
                onSelect(i)
            }
        }
        return (v, CGFloat(titles.count) * 36 + 20)
    }

    private func section(_ s: String) -> NSView {
        label(s, font: Theme.semibold(14), height: 20)
    }

    private func build() {
        let st = Settings.shared
        rows.append((label("설정", font: Theme.semibold(28), height: 40), 0))

        // 모양
        rows.append((section("모양"), 28))
        let themeNames = ["밝게", "어둡게", "시스템 설정 사용"]
        let (themeBody, themeH) = radioGroup(themeNames, selected: st.theme.rawValue) { i in
            st.theme = Settings.ThemeMode(rawValue: i) ?? .system
        }
        themeCard = ExpanderCard(glyph: .palette, title: "앱 테마", desc: "표시할 앱 테마 선택", body: themeBody, bodyHeight: themeH) {
            themeNames[Settings.shared.theme.rawValue]
        }
        rows.append((themeCard, 8))

        // 텍스트 서식
        rows.append((section("텍스트 서식"), 28))
        let fontBody = FlippedView(frame: NSRect(x: 0, y: 0, width: 1000, height: 220))
        let families = NSFontManager.shared.availableFontFamilies.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        familyCombo = WinComboBox(options: families, selected: families.firstIndex(of: st.fontFamily) ?? 0)
        let faces = Settings.faces(of: st.fontFamily)
        faceCombo = WinComboBox(options: faces, selected: faces.firstIndex(of: st.fontFace) ?? 0)
        faceCombo.displayNames = faces.map(Settings.localizedFace)
        let sizes = [8, 9, 10, 11, 12, 14, 16, 18, 20, 22, 24, 26, 28, 36, 48, 72].map(String.init)
        sizeCombo = WinComboBox(options: sizes, selected: sizes.firstIndex(of: String(Int(st.fontSize))) ?? 3)
        let rowsSpec: [(String, WinComboBox)] = [("패밀리", familyCombo), ("스타일", faceCombo), ("크기", sizeCombo)]
        for (i, (name, combo)) in rowsSpec.enumerated() {
            let y = 12 + CGFloat(i) * 48
            let l = label(name, font: Theme.ui(14), height: 20)
            l.frame = NSRect(x: 56, y: y + 6, width: 120, height: 20)
            fontBody.addSubview(l)
            combo.frame = NSRect(x: 1000 - 16 - 260, y: y, width: 260, height: 32)
            combo.autoresizingMask = [.minXMargin]
            fontBody.addSubview(combo)
        }
        preview = NSTextField(labelWithString: "다람쥐 헌 쳇바퀴에 타고파. The quick brown fox jumps over the lazy dog.")
        preview.textColor = Theme.textPrimary
        preview.lineBreakMode = .byTruncatingTail
        preview.frame = NSRect(x: 56, y: 12 + 3 * 48 + 8, width: 600, height: 40)
        fontBody.addSubview(preview)
        familyCombo.onSelect = { [weak self] i in
            guard let self else { return }
            let fam = families[i]
            st.fontFamily = fam
            let f = Settings.faces(of: fam)
            self.faceCombo.options = f
            self.faceCombo.displayNames = f.map(Settings.localizedFace)
            let idx = f.firstIndex(where: { ["regular", "normal", "roman", "book", "medium"].contains($0.lowercased()) }) ?? 0
            self.faceCombo.selectedIndex = idx
            if !f.isEmpty { st.fontFace = f[idx] }
            self.updatePreview()
        }
        faceCombo.onSelect = { [weak self] i in
            guard let self, self.faceCombo.options.indices.contains(i) else { return }
            st.fontFace = self.faceCombo.options[i]
            self.updatePreview()
        }
        sizeCombo.onSelect = { [weak self] i in
            st.fontSize = CGFloat(Double(sizes[i]) ?? 11)
            self?.updatePreview()
        }
        fontCard = ExpanderCard(glyph: .font, title: "글꼴", body: fontBody, bodyHeight: 12 + 3 * 48 + 64) {
            "\(Settings.shared.fontFamily), \(Int(Settings.shared.fontSize))pt"
        }
        rows.append((fontCard, 8))
        for (g, t, d, get, set) in [
            (Glyph.wordWrap, "자동 줄 바꿈", "창에 맞게 텍스트를 자동으로 줄 바꿈", { st.wordWrap }, { (v: Bool) in st.wordWrap = v }),
        ] as [(Glyph, String, String, () -> Bool, (Bool) -> Void)] {
            rows.append((SettingsCard(glyph: g, title: t, desc: d, trailing: toggle(get, set)), 4))
        }

        // 맞춤법
        rows.append((section("맞춤법"), 28))
        rows.append((SettingsCard(glyph: .spell, title: "맞춤법 검사", desc: "맞춤법이 틀린 단어 강조 표시",
                                  trailing: toggle({ st.spellCheck }, { st.spellCheck = $0 })), 8))
        rows.append((SettingsCard(glyph: .autocorrect, title: "자동 고침", desc: "맞춤법이 틀린 단어 자동 수정",
                                  trailing: toggle({ st.autoCorrect }, { st.autoCorrect = $0 })), 4))

        // 메모장 시작
        rows.append((section("메모장 시작"), 28))
        let startupNames = ["이전 세션 계속", "새 세션 시작 및 저장되지 않은 변경 내용 삭제"]
        let (sb, sh) = radioGroup(startupNames, selected: st.startupRestore ? 0 : 1) { i in st.startupRestore = i == 0 }
        startupCard = ExpanderCard(glyph: .document, title: "메모장이 시작되는 경우", desc: "메모장을 시작할 때 표시되는 내용 선택", body: sb, bodyHeight: sh) {
            Settings.shared.startupRestore ? "이전 세션 계속" : "새 세션 시작"
        }
        rows.append((startupCard, 8))

        // 파일 열기
        rows.append((section("파일 열기"), 28))
        let openNames = ["새 탭에서 열기", "새 창에서 열기"]
        let (ob, oh) = radioGroup(openNames, selected: st.openInNewWindow ? 1 : 0) { i in st.openInNewWindow = i == 1 }
        openCard = ExpanderCard(glyph: .openWindow, title: "파일 열기", desc: "파일을 여는 위치 선택", body: ob, bodyHeight: oh) {
            Settings.shared.openInNewWindow ? "새 창에서 열기" : "새 탭에서 열기"
        }
        rows.append((openCard, 8))
        rows.append((SettingsCard(glyph: .clock, title: "최근 파일", desc: "파일 메뉴에 최근 파일 표시",
                                  trailing: toggle({ st.showRecentFiles }, { st.showRecentFiles = $0 })), 4))

        // 정보
        rows.append((section("이 앱 정보"), 28))
        let about = SettingsCard(glyph: .info, title: "메모장 11.2607.14.0", desc: "Windows 11 메모장의 macOS 이식판")
        rows.append((about, 8))

        for card in [themeCard!, fontCard!, startupCard!, openCard!] {
            card.onToggle = { [weak self] in self?.needsLayout = true }
        }
        rows.forEach { doc.addSubview($0.0) }
        updatePreview()
    }

    private func updatePreview() {
        let st = Settings.shared
        preview.font = Settings.font(family: st.fontFamily, face: st.fontFace, size: Settings.pixelSize(st.fontSize))
        preview.textColor = Theme.textPrimary
        fontCard?.needsDisplay = true
    }

    override func layout() {
        super.layout()
        scroll.frame = bounds
        let margin: CGFloat = bounds.width > 720 ? 56 : 16
        let w = min(1000, bounds.width - margin * 2)
        var y: CGFloat = 32
        for (v, gap) in rows {
            y += gap
            var h = v.frame.height
            if let e = v as? ExpanderCard { h = e.totalHeight }
            else if v is SettingsCard { h = SettingsCard.headerHeight }
            v.frame = NSRect(x: margin, y: y, width: w, height: h)
            v.needsLayout = true
            y += h
        }
        doc.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(bounds.height, y + 40))
    }
}

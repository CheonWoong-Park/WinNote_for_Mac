import AppKit

/// Windows 11 (WinUI 3 / Mica) 색상 및 폰트 토큰
enum Theme {
    static func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: a)
    }

    static func dyn(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { ap in
            ap.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    static func dyn(_ light: UInt32, _ dark: UInt32) -> NSColor { dyn(hex(light), hex(dark)) }

    static var isDark: Bool {
        NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    // 표면
    static let micaBase = dyn(0xE8E8E8, 0x202020)          // 타이틀(탭) 영역
    static let layer = dyn(0xF8F8F8, 0x2C2C2C)             // 선택된 탭, 메뉴 바, 상태 표시줄
    static let editorBackground = dyn(0xF9F9F9, 0x272727)  // 편집 영역
    static let divider = dyn(0xEBEBEB, 0x1D1D1D)           // 메뉴 바 아래 선
    static let statusDivider = dyn(0xEAEAEA, 0x1D1D1D)
    static let cardStroke = dyn(hex(0x000000, 0.0578), hex(0x000000, 0.19))
    static let tabStroke = dyn(hex(0x000000, 0.06), hex(0xFFFFFF, 0.07))
    static let windowBorder = dyn(hex(0x000000, 0.28), hex(0x6B6B6B, 0.75))
    static let separator = dyn(hex(0x000000, 0.0803), hex(0xFFFFFF, 0.0837))

    // 텍스트
    static let textPrimary = dyn(hex(0x000000, 0.896), hex(0xFFFFFF, 1))
    static let textSecondary = dyn(hex(0x000000, 0.606), hex(0xFFFFFF, 0.786))
    static let textTertiary = dyn(hex(0x000000, 0.446), hex(0xFFFFFF, 0.544))
    static let textDisabled = dyn(hex(0x000000, 0.361), hex(0xFFFFFF, 0.363))
    static let editorText = dyn(0x000000, 0xFFFFFF)
    static let modifiedDot = dyn(0x898989, 0x9E9E9E)

    // 상호작용 채우기
    static let subtleHover = dyn(hex(0x000000, 0.0373), hex(0xFFFFFF, 0.0605))
    static let subtlePressed = dyn(hex(0x000000, 0.0241), hex(0xFFFFFF, 0.0419))
    static let tabHover = dyn(hex(0xF3F3F3, 0.75), hex(0x2D2D2D, 0.75))
    static let captionCloseHover = hex(0xC42B1C)
    static let captionClosePressed = hex(0xC42B1C, 0.9)

    // 컨트롤
    static let controlFill = dyn(hex(0xFFFFFF, 0.7), hex(0xFFFFFF, 0.0605))
    static let controlFillHover = dyn(hex(0xF9F9F9, 0.5), hex(0xFFFFFF, 0.0837))
    static let controlFillInputActive = dyn(hex(0xFFFFFF, 1), hex(0x1E1E1E, 0.7))
    static let controlStroke = dyn(hex(0x000000, 0.0578), hex(0xFFFFFF, 0.0698))
    static let controlStrokeSecondary = dyn(hex(0x000000, 0.1622), hex(0xFFFFFF, 0.0930))
    static let controlStrongStroke = dyn(hex(0x000000, 0.446), hex(0xFFFFFF, 0.544))
    static let accent = dyn(0x005FB8, 0x60CDFF)
    static let accentHover = dyn(hex(0x005FB8, 0.9), hex(0x60CDFF, 0.9))
    static let textOnAccent = dyn(0xFFFFFF, 0x000000)
    static let selectionBackground = hex(0x0078D4)
    static let flyoutBackground = dyn(0xF9F9F9, 0x2C2C2C)
    static let flyoutStroke = dyn(hex(0x000000, 0.0578), hex(0x000000, 0.2))
    static let smoke = dyn(hex(0x000000, 0.3), hex(0x000000, 0.3))
    static let dialogBackground = dyn(0xFFFFFF, 0x2B2B2B)
    static let dialogFooter = dyn(0xF3F3F3, 0x202020)
    static let cardBackground = dyn(hex(0xFFFFFF, 0.7), hex(0xFFFFFF, 0.0512))
    static let settingsBackground = dyn(0xF3F3F3, 0x202020)

    // 폰트
    static let uiFamily = "MalgunGothic"
    static func ui(_ size: CGFloat, bold: Bool = false) -> NSFont {
        NSFont(name: bold ? "MalgunGothicBold" : uiFamily, size: size) ?? .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
    }
    static func semibold(_ size: CGFloat) -> NSFont { ui(size, bold: true) }
    static func icon(_ size: CGFloat) -> NSFont {
        NSFont(name: "NotepadFluentIcons", size: size) ?? .systemFont(ofSize: size)
    }

    static func registerFonts() {
        let names = ["malgun", "malgunbd", "malgunsl", "NotepadIcons"]
        for n in names {
            let url = Bundle.main.url(forResource: n, withExtension: "ttf", subdirectory: "Fonts")
                ?? Bundle.main.url(forResource: n, withExtension: "ttf")
            if let url { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        }
    }

    static func image(_ name: String) -> NSImage? {
        if let u = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Images") ?? Bundle.main.url(forResource: name, withExtension: "png") {
            return NSImage(contentsOf: u)
        }
        return nil
    }

    static let appIcon: NSImage = {
        let img = NSImage(size: NSSize(width: 16, height: 16))
        for n in ["appicon16", "appicon32", "appicon48"] {
            if let i = image(n), let rep = i.representations.first { rep.size = NSSize(width: 16, height: 16); img.addRepresentation(rep) }
        }
        return img
    }()
}

/// Notepad Fluent Icons 글리프 (Segoe Fluent Icons 코드 포인트)
enum Glyph: String {
    case chevronDown = "\u{E70D}"
    case chevronUp = "\u{E70E}"
    case cancel = "\u{E711}"
    case more = "\u{E712}"
    case settings = "\u{E713}"
    case up = "\u{E74A}"
    case down = "\u{E74B}"
    case chevronLeft = "\u{E76B}"
    case chevronRight = "\u{E76C}"
    case palette = "\u{E790}"
    case dot = "\u{E827}"
    case font = "\u{E8D2}"
    case info = "\u{E946}"
    case equalizer = "\u{E9E9}"
    case wordWrap = "\u{EC35}"
    case spell = "\u{F87B}"
    case autocorrect = "\u{EDDD}"
    case folder = "\u{E8B7}"
    case clock = "\u{E917}"
    case openWindow = "\u{F6AB}"
    case document = "\u{E496}"
}

extension NSView {
    func drawGlyph(_ g: Glyph, center: NSPoint, size: CGFloat, color: NSColor) {
        let font = Theme.icon(size)
        let s = NSAttributedString(string: g.rawValue, attributes: [.font: font, .foregroundColor: color])
        let b = s.size()
        s.draw(at: NSPoint(x: round(center.x - b.width / 2), y: center.y - b.height / 2))
    }

    func drawText(_ text: String, at p: NSPoint, font: NSFont, color: NSColor) {
        (text as NSString).draw(at: p, withAttributes: [.font: font, .foregroundColor: color])
    }

    /// 플립된 뷰에서 세로 중앙 정렬로 텍스트 그리기
    func drawText(_ text: String, x: CGFloat, centerY: CGFloat, font: NSFont, color: NSColor, maxWidth: CGFloat? = nil) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let h = font.ascender - font.descender
        let y = round(centerY - h / 2)
        if let maxWidth {
            let style = NSMutableParagraphStyle(); style.lineBreakMode = .byClipping
            var a = attrs; a[.paragraphStyle] = style
            (text as NSString).draw(with: NSRect(x: x, y: y, width: maxWidth, height: h + 4), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: a)
        } else {
            (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
        }
    }
}

func textWidth(_ s: String, _ font: NSFont) -> CGFloat {
    ceil((s as NSString).size(withAttributes: [.font: font]).width)
}

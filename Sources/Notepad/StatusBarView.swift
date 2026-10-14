import AppKit

/// 줄/열 | 문자 수 | 일반 텍스트 ... | 확대/축소 | 줄 끝 | 인코딩  (높이 31, 위쪽 구분선 포함)
final class StatusBarView: NSView {
    static let height: CGFloat = 31

    var lineColumn = "줄 1, 열 1" { didSet { needsDisplay = true } }
    var characters = "0자" { didSet { needsDisplay = true } }
    var formatting = "일반 텍스트" { didSet { needsDisplay = true } }
    var zoom = "100%" { didSet { needsDisplay = true } }
    var lineEnding = "Unix (LF)" { didSet { needsDisplay = true } }
    var encoding = "UTF-8" { didSet { needsDisplay = true } }

    private let font = Theme.ui(12)

    override var isFlipped: Bool { true }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        Theme.layer.setFill()
        bounds.fill()
        Theme.statusDivider.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()

        let cy: CGFloat = 16
        let W = bounds.width
        // 오른쪽부터 고정 폭 열 (스크린샷 측정값)
        let encW: CGFloat = 141, eolW: CGFloat = 168, zoomW: CGFloat = 68
        let encX = W - encW
        let eolX = encX - eolW
        let zoomX = eolX - zoomW
        let lineX: CGFloat = 26
        let lineW = max(72, textWidth(lineColumn, font) + 16)
        let charX = lineX + lineW
        let charW = max(208, textWidth(characters, font) + 24)
        let fmtX = charX + charW

        func sep(_ x: CGFloat) {
            Theme.separator.setFill()
            NSRect(x: x, y: 8, width: 1, height: 16).fill()
        }
        let color = Theme.textSecondary
        drawText(lineColumn, x: lineX, centerY: cy, font: font, color: color)
        sep(charX - 1)
        drawText(characters, x: charX + 9, centerY: cy, font: font, color: color, maxWidth: charW - 12)
        if fmtX + 40 < zoomX {
            sep(fmtX)
            drawText(formatting, x: fmtX + 11, centerY: cy, font: font, color: color, maxWidth: zoomX - fmtX - 16)
        }
        sep(zoomX)
        drawText(zoom, x: zoomX + 14, centerY: cy, font: font, color: color)
        sep(eolX)
        drawText(lineEnding, x: eolX + 13, centerY: cy, font: font, color: color)
        sep(encX)
        drawText(encoding, x: encX + 14, centerY: cy, font: font, color: color)
    }
}

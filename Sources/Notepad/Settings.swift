import AppKit

extension Notification.Name {
    static let settingsChanged = Notification.Name("NotepadSettingsChanged")
    static let recentFilesChanged = Notification.Name("NotepadRecentFilesChanged")
}

final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    enum ThemeMode: Int { case light = 0, dark = 1, system = 2 }

    private init() {
        d.register(defaults: [
            "theme": ThemeMode.system.rawValue,
            "fontFamily": "Malgun Gothic",
            "fontFace": "Regular",
            "fontSize": 11.0,
            "wordWrap": true,
            "statusBar": true,
            "spellCheck": true,
            "autoCorrect": false,
            "startupRestore": true,
            "openInNewWindow": false,
            "showRecentFiles": true,
            "recentFiles": [String](),
        ])
    }

    private func changed() { NotificationCenter.default.post(name: .settingsChanged, object: nil) }

    var theme: ThemeMode {
        get { ThemeMode(rawValue: d.integer(forKey: "theme")) ?? .system }
        set { d.set(newValue.rawValue, forKey: "theme"); applyTheme(); changed() }
    }
    var fontFamily: String {
        get { d.string(forKey: "fontFamily") ?? "Malgun Gothic" }
        set { d.set(newValue, forKey: "fontFamily"); changed() }
    }
    /// NSFontManager 멤버의 face 이름 (예: Regular, Bold)
    var fontFace: String {
        get { d.string(forKey: "fontFace") ?? "Regular" }
        set { d.set(newValue, forKey: "fontFace"); changed() }
    }
    /// Windows 포인트 단위 크기 (11pt = 14.67px)
    var fontSize: CGFloat {
        get { CGFloat(d.double(forKey: "fontSize")) }
        set { d.set(Double(newValue), forKey: "fontSize"); changed() }
    }
    var wordWrap: Bool {
        get { d.bool(forKey: "wordWrap") }
        set { d.set(newValue, forKey: "wordWrap"); changed() }
    }
    var statusBar: Bool {
        get { d.bool(forKey: "statusBar") }
        set { d.set(newValue, forKey: "statusBar"); changed() }
    }
    var spellCheck: Bool {
        get { d.bool(forKey: "spellCheck") }
        set { d.set(newValue, forKey: "spellCheck"); changed() }
    }
    var autoCorrect: Bool {
        get { d.bool(forKey: "autoCorrect") }
        set { d.set(newValue, forKey: "autoCorrect"); changed() }
    }
    var startupRestore: Bool {
        get { d.bool(forKey: "startupRestore") }
        set { d.set(newValue, forKey: "startupRestore"); changed() }
    }
    var openInNewWindow: Bool {
        get { d.bool(forKey: "openInNewWindow") }
        set { d.set(newValue, forKey: "openInNewWindow"); changed() }
    }
    var showRecentFiles: Bool {
        get { d.bool(forKey: "showRecentFiles") }
        set {
            d.set(newValue, forKey: "showRecentFiles")
            if !newValue { recentFiles = [] }
            changed()
        }
    }
    var recentFiles: [String] {
        get { d.stringArray(forKey: "recentFiles") ?? [] }
        set { d.set(Array(newValue.prefix(10)), forKey: "recentFiles"); NotificationCenter.default.post(name: .recentFilesChanged, object: nil) }
    }

    func noteRecent(_ url: URL) {
        guard showRecentFiles else { return }
        var r = recentFiles.filter { $0 != url.path }
        r.insert(url.path, at: 0)
        recentFiles = r
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    func applyTheme() {
        switch theme {
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .system: NSApp.appearance = nil
        }
    }

    // MARK: 글꼴

    /// Windows pt → macOS pt(=px). Windows는 96DPI 기준이므로 pt * 96/72
    static func pixelSize(_ pt: CGFloat) -> CGFloat { pt * 96.0 / 72.0 }

    func editorFont(zoom: CGFloat) -> NSFont {
        let size = max(1, Settings.pixelSize(fontSize) * zoom)
        return Settings.font(family: fontFamily, face: fontFace, size: size)
    }

    static func font(family: String, face: String, size: CGFloat) -> NSFont {
        if let members = NSFontManager.shared.availableMembers(ofFontFamily: family) {
            for m in members where (m[1] as? String) == face {
                if let ps = m[0] as? String, let f = NSFont(name: ps, size: size) { return f }
            }
            if let ps = members.first?[0] as? String, let f = NSFont(name: ps, size: size) { return f }
        }
        return NSFont(name: "MalgunGothic", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static func faces(of family: String) -> [String] {
        (NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []).compactMap { $0[1] as? String }
    }

    static func localizedFace(_ face: String) -> String {
        switch face.lowercased() {
        case "regular", "normal", "roman", "book": return "보통"
        case "bold": return "굵게"
        case "italic", "oblique": return "기울임꼴"
        case "bold italic", "bold oblique": return "굵은 기울임꼴"
        case "light": return "가늘게"
        case "semilight": return "Semilight"
        default: return face
        }
    }
}

import AppKit

/// 이전 세션 계속: 저장하지 않은 탭까지 그대로 복원
struct Session: Codable {
    struct Tab: Codable {
        var id: String
        var path: String?
        var text: String?      // 저장되지 않은 내용 (수정됐거나 제목 없는 탭)
        var encoding: String
        var lineEnding: String
        var modified: Bool
        var selLocation: Int
        var selLength: Int
    }
    struct Window: Codable {
        var x: Double, y: Double, width: Double, height: Double
        var maximized: Bool
        var selected: Int
        var zoom: Double?
        var tabs: [Tab]
    }
    var windows: [Window]

    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotepadWin", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("session.json")
    }

    static func save(_ controllers: [NotepadWindowController]) {
        let ws: [Window] = controllers.compactMap { c in
            guard let w = c.window else { return nil }
            var frame = w.frame
            let maximized = w.isZoomedWindows
            if maximized { frame = NotepadWindowController.defaultFrame() }
            let tabs = c.tabs.map { d -> Tab in
                let sel = d.textView.selectedRange()
                let keepText = d.isModified || d.url == nil
                return Tab(id: d.id.uuidString, path: d.url?.path, text: keepText ? d.text : nil,
                           encoding: d.encoding.rawValue, lineEnding: d.lineEnding.rawValue, modified: d.isModified,
                           selLocation: sel.location, selLength: sel.length)
            }
            return Window(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height, maximized: maximized,
                          selected: c.selectedTabIndex, zoom: Double(c.zoom), tabs: tabs)
        }
        guard let data = try? JSONEncoder().encode(Session(windows: ws)) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load() -> Session? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    static func clear() { try? FileManager.default.removeItem(at: url) }
}

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!

    private(set) var controllers: [NotepadWindowController] = []
    weak var lastActive: NotepadWindowController?
    var skipSessionSaveOnClose = false
    private var pendingOpen: [URL] = []
    private var launched = false
    private var saveTimer: Timer?
    private var terminating = false

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    var active: NotepadWindowController? {
        if let c = NSApp.keyWindow?.windowController as? NotepadWindowController { return c }
        if let c = NSApp.mainWindow?.windowController as? NotepadWindowController { return c }
        return lastActive ?? controllers.last
    }

    // MARK: 수명 주기

    func applicationWillFinishLaunching(_ notification: Notification) {
        Theme.registerFonts()
        Settings.shared.applyTheme()
        // Windows 메모장처럼 영어 사전으로만 맞춤법 검사 (한글 단어에 밑줄을 긋지 않음)
        NSSpellChecker.shared.automaticallyIdentifiesLanguages = false
        _ = NSSpellChecker.shared.setLanguage("en")
        NSApp.mainMenu = MainMenu.build()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Settings.shared.startupRestore { restoreSession() } else { Session.clear() }
        launched = true
        if !pendingOpen.isEmpty {
            openURLs(pendingOpen)
            pendingOpen = []
        }
        if controllers.isEmpty { makeWindow().showWindow(nil) }
        NSApp.activate(ignoringOtherApps: true)
        DebugSnapshot.runIfRequested()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if !launched { pendingOpen += urls; return }
        openURLs(urls)
    }

    private func openURLs(_ urls: [URL]) {
        let c = active ?? makeWindow(addEmptyTab: true)
        c.openFiles(urls)
        c.showWindow(nil)
        c.window?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { (controllers.first ?? makeWindow()).showWindow(nil) }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if Settings.shared.startupRestore || terminating {
            saveSession()
            return .terminateNow
        }
        // 세션 복원을 쓰지 않으면 창마다 저장 확인
        terminating = true
        confirmAll(controllers) { ok in
            self.terminating = ok
            NSApp.reply(toApplicationShouldTerminate: ok)
        }
        return .terminateLater
    }

    private func confirmAll(_ list: [NotepadWindowController], completion: @escaping (Bool) -> Void) {
        guard let c = list.first else { completion(true); return }
        c.window?.makeKeyAndOrderFront(nil)
        c.closeAllTabs { ok in
            if ok { self.confirmAll(Array(list.dropFirst()), completion: completion) } else { completion(false) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if Settings.shared.startupRestore { saveSession() } else { Session.clear() }
    }

    // MARK: 창

    @discardableResult
    func makeWindow(frame: NSRect? = nil, addEmptyTab: Bool = true) -> NotepadWindowController {
        let c = NotepadWindowController(frame: frame)
        controllers.append(c)
        if addEmptyTab { c.addTab() }
        c.layoutViews()
        return c
    }

    func controllerClosed(_ c: NotepadWindowController) {
        // 마지막 창이 세션 복원 경로로 닫히는 중이면 탭을 그대로 저장
        if !(skipSessionSaveOnClose) {
            controllers.removeAll { $0 === c }
            scheduleSessionSave()
        } else {
            controllers.removeAll { $0 === c }
        }
    }

    func findOpen(_ url: URL) -> (NotepadWindowController, Int)? {
        let target = url.standardizedFileURL.resolvingSymlinksInPath()
        for c in controllers {
            if let i = c.tabs.firstIndex(where: { $0.url?.standardizedFileURL.resolvingSymlinksInPath() == target }) { return (c, i) }
        }
        return nil
    }

    // MARK: 세션

    func scheduleSessionSave() {
        guard launched, Settings.shared.startupRestore, !skipSessionSaveOnClose else { return }
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in self?.saveSession() }
    }

    func saveSession() {
        saveTimer?.invalidate()
        guard Settings.shared.startupRestore else { return }
        Session.save(controllers)
    }

    private func restoreSession() {
        guard let s = Session.load() else { return }
        for w in s.windows where !w.tabs.isEmpty {
            let frame = NSRect(x: w.x, y: w.y, width: w.width, height: w.height)
            let visible = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
            let c = makeWindow(frame: visible ? frame : nil, addEmptyTab: false)
            c.zoom = w.zoom ?? 1
            for t in w.tabs {
                let d = TabDocument(id: UUID(uuidString: t.id) ?? UUID())
                let url = t.path.map { URL(fileURLWithPath: $0) }
                var text = t.text
                if text == nil, let url, let data = try? Data(contentsOf: url) {
                    let tf = TextFile.decode(data)
                    text = tf.text
                }
                if text == nil && url != nil && t.text == nil { continue } // 파일이 사라짐
                d.textView.string = text ?? ""
                d.url = url
                d.encoding = FileEncoding(rawValue: t.encoding) ?? .utf8
                d.lineEnding = LineEnding(rawValue: t.lineEnding) ?? .lf
                d.isModified = t.modified
                c.addTab(d, select: false)
                let len = (d.text as NSString).length
                d.textView.setSelectedRange(NSRange(location: min(t.selLocation, len), length: min(t.selLength, max(0, len - min(t.selLocation, len)))))
            }
            if c.tabs.isEmpty { c.addTab() }
            c.selectTab(min(max(0, w.selected), c.tabs.count - 1))
            if w.maximized, let sc = NSScreen.main { c.window?.setFrame(sc.visibleFrame, display: false) }
            c.showWindow(nil)
            if let d = c.currentDoc { d.textView.scrollRangeToVisible(d.textView.selectedRange()) }
        }
    }

    // MARK: 메인 메뉴 동작 (창이 없을 때)

    @objc func newTab(_ sender: Any?) { (active ?? makeWindow(addEmptyTab: false)).addTab(); active?.showWindow(nil) }
    @objc func newWindow(_ sender: Any?) { makeWindow().showWindow(nil) }
    @objc func openDocument(_ sender: Any?) {
        if let a = active { a.openDocument(sender); return }
        let c = makeWindow()
        c.showWindow(nil)
        c.openDocument(sender)
    }
    @objc func openSettingsFromMenu(_ sender: Any?) {
        let c = active ?? makeWindow()
        c.showWindow(nil)
        c.openSettings(sender)
    }
    @objc func showAbout(_ sender: Any?) {
        let c = active ?? makeWindow()
        c.showWindow(nil)
        c.openSettings(sender)
    }
}

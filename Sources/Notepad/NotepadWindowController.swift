import AppKit
import UniformTypeIdentifiers

final class NotepadWindowController: NSWindowController, NSWindowDelegate, TitleBarDelegate, MenuBarDelegate, EditorTextViewHost {
    private(set) var tabs: [TabDocument] = []
    private(set) var selectedTabIndex = 0
    private(set) var isSettingsMode = false
    var zoom: CGFloat = 1.0

    let rootView = RootView()
    let titleBar = TitleBarView()
    let menuBar = MenuBarView()
    let editorContainer = FlippedView()
    let statusBar = StatusBarView()
    let findBar = FindBar()
    private var settingsPage: SettingsPage?
    private let borderView = WindowBorderView()
    private var findVisible = false
    private var restoreFrame: NSRect?
    private var dialog: ContentDialog?

    var isDialogOpen: Bool { dialog?.superview != nil }
    var currentDoc: TabDocument? { tabs.indices.contains(selectedTabIndex) ? tabs[selectedTabIndex] : nil }
    var isMaximized: Bool { window?.isZoomedWindows ?? false }

    init(frame: NSRect? = nil) {
        let rect = frame ?? NotepadWindowController.defaultFrame()
        let w = NotepadWindow(contentRect: rect)
        super.init(window: w)
        w.delegate = self
        w.contentView = rootView
        rootView.controller = self
        titleBar.delegate = self
        menuBar.delegate = self
        rootView.addSubview(titleBar)
        rootView.addSubview(menuBar)
        rootView.addSubview(editorContainer)
        rootView.addSubview(statusBar)
        rootView.addSubview(borderView)
        editorContainer.wantsLayer = true
        findBar.onSearch = { [weak self] fwd, inc in self?.find(forward: fwd, incremental: inc) }
        findBar.onReplace = { [weak self] in self?.replaceOne() }
        findBar.onReplaceAll = { [weak self] in self?.replaceAll() }
        findBar.onClose = { [weak self] in self?.hideFind() }
        findBar.onLayoutChange = { [weak self] in self?.layoutViews() }
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: .settingsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSWindow.didChangeScreenNotification, object: w)
    }

    required init?(coder: NSCoder) { fatalError() }

    static func defaultFrame() -> NSRect {
        let vf = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: min(1077, vf.width - 80), height: min(640, vf.height - 80))
        var origin = NSPoint(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2)
        // 이미 열린 창과 겹치지 않게 계단식 배치
        let others = AppDelegate.shared.controllers.compactMap { $0.window?.frame.origin }
        while others.contains(where: { abs($0.x - origin.x) < 4 && abs($0.y - origin.y) < 4 }) {
            origin.x += 32; origin.y -= 32
        }
        return NSRect(origin: origin, size: size)
    }

    // MARK: 레이아웃

    func layoutViews() {
        let b = rootView.bounds
        titleBar.frame = NSRect(x: 0, y: 0, width: b.width, height: TitleBarView.height)
        borderView.frame = b
        if isSettingsMode, let sp = settingsPage {
            sp.frame = NSRect(x: 0, y: TitleBarView.height, width: b.width, height: b.height - TitleBarView.height)
            return
        }
        menuBar.frame = NSRect(x: 0, y: TitleBarView.height, width: b.width, height: MenuBarView.height)
        let statusH = Settings.shared.statusBar ? StatusBarView.height : 0
        statusBar.isHidden = statusH == 0
        statusBar.frame = NSRect(x: 0, y: b.height - statusH, width: b.width, height: statusH)
        let top = menuBar.frame.maxY
        editorContainer.frame = NSRect(x: 0, y: top, width: b.width, height: b.height - top - statusH)
        currentDoc?.scrollView.frame = editorContainer.bounds
        if findVisible {
            findBar.frame.origin = NSPoint(x: 8, y: 8)
        }
        borderView.frame = b
    }

    // MARK: 탭 관리

    @discardableResult
    func addTab(_ doc: TabDocument? = nil, select: Bool = true, at index: Int? = nil) -> TabDocument {
        let d = doc ?? TabDocument()
        d.textView.host = self
        d.onChange = { [weak self, weak d] in
            self?.titleBar.needsDisplay = true
            if let d, d === self?.currentDoc { self?.updateTitle(); self?.updateStatus() }
        }
        d.onTextChange = { [weak self, weak d] in
            if let d, d === self?.currentDoc { self?.updateStatus() }
            AppDelegate.shared.scheduleSessionSave()
        }
        d.onSelectionChange = { [weak self, weak d] in
            if let d, d === self?.currentDoc { self?.updateStatus() }
        }
        let i = index ?? tabs.count
        tabs.insert(d, at: i)
        applyStyle(to: d)
        if select { selectTab(i) } else { titleBar.needsDisplay = true }
        AppDelegate.shared.scheduleSessionSave()
        return d
    }

    func selectTab(_ i: Int) {
        guard tabs.indices.contains(i) else { return }
        currentDoc?.scrollView.removeFromSuperview()
        selectedTabIndex = i
        let d = tabs[i]
        d.scrollView.frame = editorContainer.bounds
        editorContainer.addSubview(d.scrollView, positioned: .below, relativeTo: nil)
        if findVisible { editorContainer.addSubview(findBar, positioned: .above, relativeTo: nil) }
        applyStyle(to: d)
        if !isSettingsMode && !isDialogOpen { window?.makeFirstResponder(d.textView) }
        titleBar.needsDisplay = true
        updateTitle()
        updateStatus()
    }

    func cycleTab(_ dir: Int) {
        guard !tabs.isEmpty else { return }
        selectTab((selectedTabIndex + dir + tabs.count) % tabs.count)
    }

    /// 확인 없이 탭 제거
    func removeTab(_ i: Int) {
        guard tabs.indices.contains(i) else { return }
        let d = tabs[i]
        d.scrollView.removeFromSuperview()
        d.onChange = nil; d.onTextChange = nil; d.onSelectionChange = nil
        tabs.remove(at: i)
        if tabs.isEmpty {
            window?.close()
            return
        }
        var newSel = selectedTabIndex
        if i < selectedTabIndex { newSel -= 1 } else if i == selectedTabIndex { newSel = min(i, tabs.count - 1) }
        selectedTabIndex = max(0, min(newSel, tabs.count - 1))
        selectTab(selectedTabIndex)
        AppDelegate.shared.scheduleSessionSave()
    }

    /// 저장 확인 후 탭 닫기
    func closeTab(_ i: Int, completion: ((Bool) -> Void)? = nil) {
        guard tabs.indices.contains(i) else { completion?(true); return }
        let d = tabs[i]
        if i != selectedTabIndex { selectTab(i) }
        confirmSave(d) { [weak self] ok in
            if ok { self?.removeTab(self?.tabs.firstIndex(of: d) ?? i) }
            completion?(ok)
        }
    }

    private func needsSavePrompt(_ d: TabDocument) -> Bool {
        d.isModified && !(d.url == nil && d.text.isEmpty)
    }

    /// 수정된 문서면 저장 여부 질문. completion(true)=계속 진행
    func confirmSave(_ d: TabDocument, completion: @escaping (Bool) -> Void) {
        guard needsSavePrompt(d) else { completion(true); return }
        if let i = tabs.firstIndex(of: d), i != selectedTabIndex { selectTab(i) }
        showDialog(title: "메모장", message: "변경 내용을 \(d.title)에 저장하시겠습니까?", primary: "저장", secondary: "저장 안 함", close: "취소") { [weak self] r in
            switch r {
            case .primary: self?.save(d) { completion($0) }
            case .secondary: completion(true)
            case .close: completion(false)
            }
        }
    }

    /// 모든 탭 확인 후 창 닫기
    func closeAllTabs(completion: @escaping (Bool) -> Void) {
        guard let d = tabs.first(where: { needsSavePrompt($0) }) else { completion(true); return }
        confirmSave(d) { [weak self] ok in
            guard ok, let self else { completion(false); return }
            d.isModified = false
            self.closeAllTabs(completion: completion)
        }
    }

    func requestCloseWindow() {
        let ad: AppDelegate = AppDelegate.shared
        if Settings.shared.startupRestore && ad.controllers.count == 1 {
            ad.saveSession()
            ad.skipSessionSaveOnClose = true
            NSApp.terminate(nil)
            return
        }
        closeAllTabs { [weak self] ok in
            guard ok, let self else { return }
            self.tabs.forEach { $0.isModified = false }
            self.window?.close()
        }
    }

    // MARK: TitleBarDelegate

    func titleBarSelectTab(_ index: Int) { if index != selectedTabIndex { selectTab(index) } }
    func titleBarCloseTab(_ index: Int) { closeTab(index) }
    func titleBarNewTab() { newTab(nil) }

    func titleBarMoveTab(from: Int, to: Int) {
        guard tabs.indices.contains(from), tabs.indices.contains(to) else { return }
        let d = tabs.remove(at: from)
        tabs.insert(d, at: to)
        selectedTabIndex = to
        titleBar.needsDisplay = true
    }

    func titleBarDropTab(_ index: Int, screenPoint: NSPoint) {
        guard tabs.indices.contains(index), tabs.count > 1 else { return }
        let d = tabs[index]
        // 다른 메모장 창의 탭 표시줄 위라면 그 창으로 이동
        for c in AppDelegate.shared.controllers where c !== self {
            guard let w = c.window else { continue }
            let barRect = w.convertToScreen(c.titleBar.convert(c.titleBar.bounds, to: nil))
            if barRect.contains(screenPoint) {
                detach(d)
                c.addTab(d)
                w.makeKeyAndOrderFront(nil)
                return
            }
        }
        detach(d)
        let size = window?.frame.size ?? NSSize(width: 1000, height: 640)
        let frame = NSRect(x: screenPoint.x - 120, y: screenPoint.y - size.height + 20, width: size.width, height: size.height)
        let c = AppDelegate.shared.makeWindow(frame: frame, addEmptyTab: false)
        c.addTab(d)
        c.showWindow(nil)
    }

    private func detach(_ d: TabDocument) {
        guard let i = tabs.firstIndex(of: d) else { return }
        d.scrollView.removeFromSuperview()
        tabs.remove(at: i)
        var newSel = selectedTabIndex
        if i < selectedTabIndex { newSel -= 1 } else if i == selectedTabIndex { newSel = min(i, tabs.count - 1) }
        selectedTabIndex = max(0, min(newSel, tabs.count - 1))
        selectTab(selectedTabIndex)
    }

    func titleBarTabContextMenu(_ index: Int, event: NSEvent) {
        guard let w = window else { return }
        let items = [
            FlyoutItem("새 탭", shortcut: "Ctrl+N") { [weak self] in self?.newTab(nil) },
            FlyoutItem("탭 닫기", shortcut: "Ctrl+W") { [weak self] in self?.closeTab(index) },
            FlyoutItem("다른 탭 닫기", enabled: { [weak self] in (self?.tabs.count ?? 0) > 1 }) { [weak self] in
                guard let self, self.tabs.indices.contains(index) else { return }
                let keep = self.tabs[index]
                self.closeSequentially(self.tabs.filter { $0 !== keep })
            },
            FlyoutItem("오른쪽 탭 닫기", enabled: { [weak self] in index < (self?.tabs.count ?? 0) - 1 }) { [weak self] in
                guard let self else { return }
                self.closeSequentially(Array(self.tabs[(index + 1)...]))
            },
        ]
        FlyoutMenu.show(items: items, topLeft: w.convertPoint(toScreen: event.locationInWindow), parentWindow: w)
    }

    private func closeSequentially(_ docs: [TabDocument]) {
        guard let d = docs.first, let i = tabs.firstIndex(of: d) else { return }
        closeTab(i) { [weak self] ok in
            if ok { self?.closeSequentially(Array(docs.dropFirst())) }
        }
    }

    func titleBarMinimize() { window?.miniaturize(nil) }

    func titleBarToggleMaximize() {
        guard let w = window, let s = w.screen else { return }
        if w.isZoomedWindows {
            w.setFrame(restoreFrame ?? NotepadWindowController.defaultFrame(), display: true, animate: true)
        } else {
            restoreFrame = w.frame
            w.setFrame(s.visibleFrame, display: true, animate: true)
        }
        titleBar.needsDisplay = true
        borderView.needsDisplay = true
    }

    func titleBarClose() { requestCloseWindow() }
    func titleBarBack() { closeSettings() }

    // MARK: MenuBarDelegate

    func menuBarOpenSettings() { openSettings(nil) }

    func menuBarItems(for index: Int) -> [FlyoutItem] {
        switch index {
        case 0: return fileMenuItems()
        case 1: return editMenuItems()
        default: return viewMenuItems()
        }
    }

    private var hasSelection: Bool { (currentDoc?.textView.selectedRange().length ?? 0) > 0 }
    private var canUndo: Bool { currentDoc?.undo.canUndo ?? false }

    private func fileMenuItems() -> [FlyoutItem] {
        var items = [
            FlyoutItem("새 탭", shortcut: "Ctrl+N") { [weak self] in self?.newTab(nil) },
            FlyoutItem("새 창", shortcut: "Ctrl+Shift+N") { [weak self] in self?.newWindow(nil) },
            FlyoutItem("열기", shortcut: "Ctrl+O") { [weak self] in self?.openDocument(nil) },
        ]
        if Settings.shared.showRecentFiles {
            items.append(FlyoutItem("최근 사용", enabled: { !Settings.shared.recentFiles.isEmpty }, submenu: { [weak self] in
                Settings.shared.recentFiles.map { path in
                    FlyoutItem((path as NSString).abbreviatingWithTildeInPath) { self?.openFiles([URL(fileURLWithPath: path)]) }
                } + [FlyoutItem.separator(), FlyoutItem("최근 사용 항목 지우기") { Settings.shared.recentFiles = [] }]
            }))
        }
        items += [
            FlyoutItem("저장", shortcut: "Ctrl+S") { [weak self] in self?.saveDocument(nil) },
            FlyoutItem("다른 이름으로 저장", shortcut: "Ctrl+Shift+S") { [weak self] in self?.saveDocumentAs(nil) },
            FlyoutItem("모두 저장", shortcut: "Ctrl+Alt+S") { [weak self] in self?.saveAll(nil) },
            .separator(),
            FlyoutItem("페이지 설정") { [weak self] in self?.pageSetup(nil) },
            FlyoutItem("인쇄", shortcut: "Ctrl+P") { [weak self] in self?.printDocument(nil) },
            .separator(),
            FlyoutItem("탭 닫기", shortcut: "Ctrl+W") { [weak self] in self?.closeCurrentTab(nil) },
            FlyoutItem("창 닫기", shortcut: "Ctrl+Shift+W") { [weak self] in self?.closeWindow(nil) },
            FlyoutItem("끝내기") { NSApp.terminate(nil) },
        ]
        return items
    }

    private func editMenuItems() -> [FlyoutItem] {
        [
            FlyoutItem("실행 취소", shortcut: "Ctrl+Z", enabled: { [weak self] in self?.canUndo ?? false }) { [weak self] in self?.undoEdit() },
            .separator(),
            FlyoutItem("잘라내기", shortcut: "Ctrl+X", enabled: { [weak self] in self?.hasSelection ?? false }) { [weak self] in self?.currentDoc?.textView.cut(nil) },
            FlyoutItem("복사", shortcut: "Ctrl+C", enabled: { [weak self] in self?.hasSelection ?? false }) { [weak self] in self?.currentDoc?.textView.copy(nil) },
            FlyoutItem("붙여넣기", shortcut: "Ctrl+V", enabled: { NSPasteboard.general.string(forType: .string) != nil }) { [weak self] in self?.currentDoc?.textView.paste(nil) },
            FlyoutItem("삭제", shortcut: "Del", enabled: { [weak self] in self?.hasSelection ?? false }) { [weak self] in self?.currentDoc?.textView.delete(nil) },
            .separator(),
            FlyoutItem("Bing으로 검색...", shortcut: "Ctrl+E", enabled: { [weak self] in self?.hasSelection ?? false }) { [weak self] in self?.searchWithBing(nil) },
            FlyoutItem("찾기", shortcut: "Ctrl+F") { [weak self] in self?.showFind(nil) },
            FlyoutItem("다음 찾기", shortcut: "F3") { [weak self] in self?.findNext(nil) },
            FlyoutItem("이전 찾기", shortcut: "Shift+F3") { [weak self] in self?.findPrevious(nil) },
            FlyoutItem("바꾸기", shortcut: "Ctrl+H") { [weak self] in self?.showReplace(nil) },
            FlyoutItem("이동", shortcut: "Ctrl+G") { [weak self] in self?.goToLine(nil) },
            .separator(),
            FlyoutItem("모두 선택", shortcut: "Ctrl+A") { [weak self] in self?.currentDoc?.textView.selectAll(nil) },
            FlyoutItem("시간/날짜", shortcut: "F5") { [weak self] in self?.insertTimeDate(nil) },
            .separator(),
            FlyoutItem("글꼴") { [weak self] in self?.showFontSettings(nil) },
        ]
    }

    private func viewMenuItems() -> [FlyoutItem] {
        [
            FlyoutItem("확대/축소", submenu: { [weak self] in [
                FlyoutItem("확대", shortcut: "Ctrl+더하기") { self?.zoomIn(nil) },
                FlyoutItem("축소", shortcut: "Ctrl+빼기") { self?.zoomOut(nil) },
                FlyoutItem("기본 확대/축소 복원", shortcut: "Ctrl+0") { self?.zoomReset(nil) },
            ] }),
            FlyoutItem("상태 표시줄", checked: { Settings.shared.statusBar }) { Settings.shared.statusBar.toggle() },
            FlyoutItem("자동 줄 바꿈", checked: { Settings.shared.wordWrap }) { Settings.shared.wordWrap.toggle() },
        ]
    }

    // MARK: EditorTextViewHost

    func editorRequestsZoom(delta: Int) { delta > 0 ? zoomIn(nil) : zoomOut(nil) }
    func editorOpenFiles(_ urls: [URL]) { openFiles(urls) }

    func editorContextMenu(_ editor: EditorTextView, event: NSEvent) {
        guard let w = window else { return }
        let items = [
            FlyoutItem("실행 취소", shortcut: "Ctrl+Z", enabled: { [weak self] in self?.canUndo ?? false }) { [weak self] in self?.undoEdit() },
            .separator(),
            FlyoutItem("잘라내기", shortcut: "Ctrl+X", enabled: { [weak self] in self?.hasSelection ?? false }) { editor.cut(nil) },
            FlyoutItem("복사", shortcut: "Ctrl+C", enabled: { [weak self] in self?.hasSelection ?? false }) { editor.copy(nil) },
            FlyoutItem("붙여넣기", shortcut: "Ctrl+V", enabled: { NSPasteboard.general.string(forType: .string) != nil }) { editor.paste(nil) },
            FlyoutItem("삭제", shortcut: "Del", enabled: { [weak self] in self?.hasSelection ?? false }) { editor.delete(nil) },
            .separator(),
            FlyoutItem("모두 선택", shortcut: "Ctrl+A") { editor.selectAll(nil) },
            .separator(),
            FlyoutItem("Bing으로 검색...", shortcut: "Ctrl+E", enabled: { [weak self] in self?.hasSelection ?? false }) { [weak self] in self?.searchWithBing(nil) },
        ]
        FlyoutMenu.show(items: items, topLeft: w.convertPoint(toScreen: event.locationInWindow), parentWindow: w, minWidth: 200)
    }

    // MARK: 상태 / 제목

    private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.locale = Locale(identifier: "ko_KR"); return f
    }()

    func updateStatus() {
        guard let d = currentDoc, Settings.shared.statusBar else { return }
        let (line, col) = d.caretPosition()
        let nf = NotepadWindowController.numberFormatter
        statusBar.lineColumn = "줄 \(nf.string(from: line as NSNumber) ?? "\(line)"), 열 \(nf.string(from: col as NSNumber) ?? "\(col)")"
        let total = nf.string(from: d.characterCount() as NSNumber) ?? ""
        let sel = d.selectedCharacterCount()
        statusBar.characters = sel > 0 ? "\(total)자 중 \(nf.string(from: sel as NSNumber) ?? "")자" : "\(total)자"
        statusBar.zoom = "\(Int(round(zoom * 100)))%"
        statusBar.lineEnding = d.lineEnding.label
        statusBar.encoding = d.encoding.label
    }

    func updateTitle() {
        guard let w = window else { return }
        let t = isSettingsMode ? "설정 - 메모장" : "\(currentDoc?.title ?? "제목 없음") - 메모장"
        w.title = t
        NSApp.changeWindowsItem(w, title: t, filename: false)
        w.representedURL = isSettingsMode ? nil : currentDoc?.url
    }

    // MARK: 스타일 / 설정

    func applyStyle(to d: TabDocument) {
        let s = Settings.shared
        d.scrollView.backgroundColor = Theme.editorBackground
        d.textView.backgroundColor = Theme.editorBackground
        d.applyStyle(font: s.editorFont(zoom: zoom), wordWrap: s.wordWrap, spellCheck: s.spellCheck, autoCorrect: s.autoCorrect)
    }

    @objc private func settingsChanged() {
        tabs.forEach(applyStyle)
        layoutViews()
        updateStatus()
        settingsPage?.needsDisplay = true
        rootView.needsDisplay = true
    }

    @objc private func screenChanged() { titleBar.needsDisplay = true }

    // MARK: 파일 메뉴 동작

    @objc func newTab(_ sender: Any?) {
        if isSettingsMode { closeSettings() }
        addTab()
    }

    @objc func newWindow(_ sender: Any?) {
        AppDelegate.shared.makeWindow().showWindow(nil)
    }

    @objc func openDocument(_ sender: Any?) {
        guard let w = window else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "열기"
        if let dir = currentDoc?.url?.deletingLastPathComponent() { panel.directoryURL = dir }
        panel.beginSheetModal(for: w) { [weak self] r in
            if r == .OK { self?.openFiles(panel.urls) }
        }
    }

    /// 파일 열기 (이미 열려 있으면 해당 탭으로 전환)
    func openFiles(_ urls: [URL]) {
        if isSettingsMode { closeSettings() }
        for url in urls {
            if let (c, i) = AppDelegate.shared.findOpen(url) {
                c.selectTab(i)
                c.window?.makeKeyAndOrderFront(nil)
                continue
            }
            if Settings.shared.openInNewWindow && !(tabs.count == 1 && isBlank(tabs[0])) {
                let c = AppDelegate.shared.makeWindow(addEmptyTab: false)
                c.loadFile(url, into: nil)
                c.showWindow(nil)
                continue
            }
            if let cur = currentDoc, tabs.count >= 1, isBlank(cur) {
                loadFile(url, into: cur)
            } else {
                loadFile(url, into: nil)
            }
        }
    }

    private func isBlank(_ d: TabDocument) -> Bool { d.url == nil && d.text.isEmpty && !d.isModified }

    func loadFile(_ url: URL, into existing: TabDocument?) {
        do {
            let data = try Data(contentsOf: url)
            let tf = TextFile.decode(data)
            let d = existing ?? addTab()
            d.textView.string = tf.text
            d.url = url
            d.encoding = tf.encoding
            d.lineEnding = tf.lineEnding
            d.undo.removeAllActions()
            d.isModified = false
            d.fileModDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            applyStyle(to: d)
            d.textView.setSelectedRange(NSRange(location: 0, length: 0))
            d.textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
            if let i = tabs.firstIndex(of: d) { selectTab(i) }
            Settings.shared.noteRecent(url)
        } catch {
            if existing == nil, let d = tabs.last, isBlank(d), tabs.count > 1 { removeTab(tabs.count - 1) }
            showDialog(title: "메모장", message: "\(url.lastPathComponent)\n파일을 열 수 없습니다.\n\(error.localizedDescription)", primary: "확인") { _ in }
        }
    }

    @objc func saveDocument(_ sender: Any?) {
        guard let d = currentDoc else { return }
        save(d) { _ in }
    }

    @objc func saveDocumentAs(_ sender: Any?) {
        guard let d = currentDoc else { return }
        saveAs(d) { _ in }
    }

    @objc func saveAll(_ sender: Any?) {
        func next(_ docs: [TabDocument]) {
            guard let d = docs.first else { return }
            if let i = tabs.firstIndex(of: d) { selectTab(i) }
            save(d) { ok in if ok { next(Array(docs.dropFirst())) } }
        }
        next(tabs.filter { $0.isModified || $0.url == nil && !$0.text.isEmpty })
    }

    func save(_ d: TabDocument, completion: @escaping (Bool) -> Void) {
        guard let url = d.url else { saveAs(d, completion: completion); return }
        write(d, to: url, completion: completion)
    }

    private func write(_ d: TabDocument, to url: URL, completion: @escaping (Bool) -> Void) {
        let tf = TextFile(text: d.text, encoding: d.encoding, lineEnding: d.lineEnding)
        let finish: (Data) -> Void = { [weak self] data in
            do {
                try data.write(to: url, options: .atomic)
                d.url = url
                d.isModified = false
                d.fileModDate = Date()
                Settings.shared.noteRecent(url)
                self?.updateTitle()
                self?.titleBar.needsDisplay = true
                AppDelegate.shared.scheduleSessionSave()
                completion(true)
            } catch {
                self?.showDialog(title: "메모장", message: "\(url.lastPathComponent)\n파일을 저장할 수 없습니다.\n\(error.localizedDescription)", primary: "확인") { _ in completion(false) }
            }
        }
        if let data = tf.encoded() {
            finish(data)
        } else {
            showDialog(title: "메모장",
                       message: "이 파일에는 ANSI 인코딩으로 저장하면 손실되는 유니코드 형식의 문자가 있습니다. 이 문자를 유지하려면 [취소]를 클릭한 다음 [인코딩] 드롭다운 목록에서 유니코드 옵션 중 하나를 선택하세요. 계속하시겠습니까?",
                       primary: "확인", close: "취소") { r in
                if r == .primary, let data = tf.encoded(allowLossy: true) { finish(data) } else { completion(false) }
            }
        }
    }

    func saveAs(_ d: TabDocument, completion: @escaping (Bool) -> Void) {
        guard let w = window else { completion(false); return }
        let panel = NSSavePanel()
        panel.title = "다른 이름으로 저장"
        panel.nameFieldLabel = "파일 이름:"
        panel.nameFieldStringValue = d.url?.lastPathComponent ?? (firstLineName(d) ?? "제목 없음") + ".txt"
        panel.allowedContentTypes = [.plainText]
        panel.allowsOtherFileTypes = true
        panel.isExtensionHidden = false
        panel.canCreateDirectories = true
        if let dir = d.url?.deletingLastPathComponent() { panel.directoryURL = dir }

        // 인코딩 선택
        let acc = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 44))
        let label = NSTextField(labelWithString: "인코딩:")
        label.frame = NSRect(x: 20, y: 13, width: 60, height: 18)
        let pop = NSPopUpButton(frame: NSRect(x: 84, y: 8, width: 200, height: 26), pullsDown: false)
        for e in FileEncoding.allCases { pop.addItem(withTitle: e.label) }
        pop.selectItem(at: FileEncoding.allCases.firstIndex(of: d.encoding) ?? 3)
        acc.addSubview(label)
        acc.addSubview(pop)
        panel.accessoryView = acc

        panel.beginSheetModal(for: w) { [weak self] r in
            guard r == .OK, let url = panel.url, let self else { completion(false); return }
            d.encoding = FileEncoding.allCases[pop.indexOfSelectedItem]
            self.write(d, to: url, completion: completion)
        }
    }

    /// Windows 11 메모장은 첫 줄을 기본 파일 이름으로 제안한다
    private func firstLineName(_ d: TabDocument) -> String? {
        let first = d.text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        let cleaned = first.replacingOccurrences(of: "[/:\\\\?*\"<>|]", with: "", options: .regularExpression)
        guard !cleaned.isEmpty else { return nil }
        return String(cleaned.prefix(50))
    }

    @objc func pageSetup(_ sender: Any?) {
        guard let w = window else { return }
        NSPageLayout().beginSheet(with: NSPrintInfo.shared, modalFor: w, delegate: nil, didEnd: nil, contextInfo: nil)
    }

    @objc func printDocument(_ sender: Any?) {
        guard let d = currentDoc, let w = window else { return }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.dictionary()[NSPrintInfo.AttributeKey.headerAndFooter] = true
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        tv.isRichText = false
        tv.string = d.text
        tv.font = Settings.shared.editorFont(zoom: 1)
        tv.textColor = .black
        tv.backgroundColor = .white
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = true
        tv.isVerticallyResizable = true
        tv.sizeToFit()
        let op = NSPrintOperation(view: tv, printInfo: info)
        op.jobTitle = d.title
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        op.runModal(for: w, delegate: nil, didRun: nil, contextInfo: nil)
    }

    @objc func closeCurrentTab(_ sender: Any?) {
        if isSettingsMode { closeSettings(); return }
        closeTab(selectedTabIndex)
    }

    @objc func closeWindow(_ sender: Any?) { requestCloseWindow() }

    // MARK: 편집 메뉴 동작

    private func undoEdit() {
        guard let d = currentDoc else { return }
        window?.makeFirstResponder(d.textView)
        d.undo.undo()
    }


    @objc func searchWithBing(_ sender: Any?) {
        guard let d = currentDoc else { return }
        let sel = (d.text as NSString).substring(with: d.textView.selectedRange()).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sel.isEmpty else { return }
        var comps = URLComponents(string: "https://www.bing.com/search")!
        comps.queryItems = [URLQueryItem(name: "q", value: String(sel.prefix(1000))), URLQueryItem(name: "form", value: "NPCTXT")]
        if let u = comps.url { NSWorkspace.shared.open(u) }
    }

    @objc func showFind(_ sender: Any?) { presentFind(replace: false) }
    @objc func showReplace(_ sender: Any?) { presentFind(replace: true) }

    private func presentFind(replace: Bool) {
        guard !isSettingsMode, let d = currentDoc else { return }
        let sel = (d.text as NSString).substring(with: d.textView.selectedRange())
        if !sel.isEmpty && !sel.contains("\n") { findBar.findBox.stringValue = sel }
        if !findVisible {
            findVisible = true
            editorContainer.addSubview(findBar, positioned: .above, relativeTo: nil)
        }
        if findBar.isReplaceVisible != replace || replace { findBar.setReplaceVisible(replace || findBar.isReplaceVisible) }
        if replace && !findBar.isReplaceVisible { findBar.setReplaceVisible(true) }
        layoutViews()
        findBar.findBox.focus()
    }

    func hideFind() {
        findVisible = false
        findBar.removeFromSuperview()
        if let d = currentDoc { window?.makeFirstResponder(d.textView) }
    }

    @objc func findNext(_ sender: Any?) {
        if findBar.findBox.stringValue.isEmpty { showFind(nil); return }
        find(forward: true, incremental: false)
    }

    @objc func findPrevious(_ sender: Any?) {
        if findBar.findBox.stringValue.isEmpty { showFind(nil); return }
        find(forward: false, incremental: false)
    }

    @discardableResult
    func find(forward: Bool, incremental: Bool) -> Bool {
        guard let d = currentDoc else { return false }
        let q = findBar.findBox.stringValue
        guard !q.isEmpty else { return false }
        let ns = d.text as NSString
        let sel = d.textView.selectedRange()
        var opts: NSString.CompareOptions = [.literal]
        if !findBar.matchCase { opts.insert(.caseInsensitive) }
        var r: NSRange
        if forward {
            let start = incremental ? sel.location : NSMaxRange(sel)
            r = ns.range(of: q, options: opts, range: NSRange(location: start, length: ns.length - start))
            if r.location == NSNotFound && findBar.wrapAround {
                r = ns.range(of: q, options: opts, range: NSRange(location: 0, length: min(ns.length, start + (q as NSString).length)))
            }
        } else {
            opts.insert(.backwards)
            r = ns.range(of: q, options: opts, range: NSRange(location: 0, length: sel.location))
            if r.location == NSNotFound && findBar.wrapAround {
                r = ns.range(of: q, options: opts, range: NSRange(location: sel.location, length: ns.length - sel.location))
            }
        }
        if r.location == NSNotFound {
            if !incremental {
                showDialog(title: "메모장", message: "\"\(q)\"을(를) 찾을 수 없습니다.", primary: "확인") { _ in }
            }
            return false
        }
        d.textView.setSelectedRange(r)
        d.textView.scrollRangeToVisible(r)
        return true
    }

    private func replaceOne() {
        guard let d = currentDoc else { return }
        let q = findBar.findBox.stringValue
        guard !q.isEmpty else { return }
        let sel = d.textView.selectedRange()
        let cur = (d.text as NSString).substring(with: sel)
        let matches = findBar.matchCase ? cur == q : cur.compare(q, options: .caseInsensitive) == .orderedSame
        if matches {
            let rep = findBar.replaceBox.stringValue
            if d.textView.shouldChangeText(in: sel, replacementString: rep) {
                d.textView.textStorage?.replaceCharacters(in: sel, with: rep)
                d.textView.didChangeText()
                d.textView.setSelectedRange(NSRange(location: sel.location + (rep as NSString).length, length: 0))
            }
        }
        find(forward: true, incremental: false)
    }

    private func replaceAll() {
        guard let d = currentDoc else { return }
        let q = findBar.findBox.stringValue
        guard !q.isEmpty else { return }
        var opts: NSString.CompareOptions = [.literal]
        if !findBar.matchCase { opts.insert(.caseInsensitive) }
        let full = d.text as NSString
        let result = NSMutableString(string: full)
        let count = result.replaceOccurrences(of: q, with: findBar.replaceBox.stringValue, options: opts, range: NSRange(location: 0, length: result.length))
        guard count > 0 else {
            showDialog(title: "메모장", message: "\"\(q)\"을(를) 찾을 수 없습니다.", primary: "확인") { _ in }
            return
        }
        let range = NSRange(location: 0, length: full.length)
        if d.textView.shouldChangeText(in: range, replacementString: result as String) {
            d.textView.textStorage?.replaceCharacters(in: range, with: result as String)
            applyStyle(to: d)
            d.textView.didChangeText()
            d.textView.setSelectedRange(NSRange(location: 0, length: 0))
        }
    }

    @objc func goToLine(_ sender: Any?) {
        guard let d = currentDoc, !isSettingsMode else { return }
        let box = WinTextBox()
        let container = FlippedView(frame: NSRect(x: 0, y: 0, width: 400, height: 56))
        let label = NSTextField(labelWithString: "줄 번호")
        label.font = Theme.ui(14)
        label.textColor = Theme.textPrimary
        label.frame = NSRect(x: 0, y: 0, width: 200, height: 20)
        box.frame = NSRect(x: 0, y: 24, width: 400, height: 32)
        box.autoresizingMask = [.width]
        container.addSubview(label)
        container.addSubview(box)
        box.stringValue = String(d.caretPosition().line)
        let lineCount = d.text.reduce(into: 1) { if $1 == "\n" { $0 += 1 } }
        let dlg = makeDialog(title: "줄로 이동", content: container, primary: "이동", close: "취소") { [weak self] r in
            guard r == .primary, let n = Int(box.stringValue.trimmingCharacters(in: .whitespaces)) else {
                if let d = self?.currentDoc { self?.window?.makeFirstResponder(d.textView) }
                return
            }
            self?.moveCaret(toLine: n)
        }
        dlg.shouldClose = { [weak self] r in
            guard r == .primary else { return true }
            guard let n = Int(box.stringValue.trimmingCharacters(in: .whitespaces)), n >= 1 else { NSSound.beep(); return false }
            if n > lineCount {
                self?.dialog = nil
                dlg.removeFromSuperview()
                self?.showDialog(title: "메모장 - 줄로 이동", message: "줄 번호가 전체 줄 수를 초과합니다.", primary: "확인") { _ in
                    self?.goToLine(nil)
                }
                return false
            }
            return true
        }
        box.onEnter = { _ in dlg.finish(.primary) }
        box.onEscape = { dlg.finish(.close) }
        dlg.initialFocus = box
        present(dlg)
    }

    private func moveCaret(toLine n: Int) {
        guard let d = currentDoc else { return }
        let ns = d.text as NSString
        var line = 1
        var loc = 0
        while line < n {
            let r = ns.range(of: "\n", options: .literal, range: NSRange(location: loc, length: ns.length - loc))
            if r.location == NSNotFound { break }
            loc = r.location + 1
            line += 1
        }
        window?.makeFirstResponder(d.textView)
        d.textView.setSelectedRange(NSRange(location: loc, length: 0))
        d.textView.scrollRangeToVisible(NSRange(location: loc, length: 0))
    }

    @objc func insertTimeDate(_ sender: Any?) {
        guard let d = currentDoc else { return }
        let tf = DateFormatter()
        tf.locale = Locale(identifier: "ko_KR")
        tf.dateFormat = "a h:mm"
        let df = DateFormatter()
        df.locale = Locale(identifier: "ko_KR")
        df.dateFormat = "yyyy-MM-dd"
        let now = Date()
        window?.makeFirstResponder(d.textView)
        d.textView.insertText("\(tf.string(from: now)) \(df.string(from: now))", replacementRange: d.textView.selectedRange())
    }

    @objc func showFontSettings(_ sender: Any?) { openSettings(nil) }

    @objc func deleteSelection(_ sender: Any?) { currentDoc?.textView.delete(nil) }

    // MARK: 보기 메뉴 동작

    @objc func zoomIn(_ sender: Any?) { setZoom(min(5.0, (zoom * 10).rounded() / 10 + 0.1)) }
    @objc func zoomOut(_ sender: Any?) { setZoom(max(0.1, (zoom * 10).rounded() / 10 - 0.1)) }
    @objc func zoomReset(_ sender: Any?) { setZoom(1.0) }

    private func setZoom(_ z: CGFloat) {
        guard !isSettingsMode else { return }
        zoom = (z * 10).rounded() / 10
        tabs.forEach(applyStyle)
        updateStatus()
    }

    @objc func toggleStatusBar(_ sender: Any?) { Settings.shared.statusBar.toggle() }
    @objc func toggleWordWrap(_ sender: Any?) { Settings.shared.wordWrap.toggle() }

    // MARK: 설정 페이지

    @objc func openSettings(_ sender: Any?) {
        guard !isSettingsMode else { return }
        FlyoutMenu.closeAll()
        if findVisible { hideFind() }
        isSettingsMode = true
        let sp = SettingsPage(frame: .zero)
        settingsPage = sp
        menuBar.isHidden = true
        editorContainer.isHidden = true
        statusBar.isHidden = true
        rootView.addSubview(sp, positioned: .below, relativeTo: borderView)
        layoutViews()
        titleBar.needsDisplay = true
        window?.makeFirstResponder(nil)
        updateTitle()
    }

    func closeSettings() {
        guard isSettingsMode else { return }
        isSettingsMode = false
        settingsPage?.removeFromSuperview()
        settingsPage = nil
        menuBar.isHidden = false
        editorContainer.isHidden = false
        layoutViews()
        titleBar.needsDisplay = true
        if let d = currentDoc { window?.makeFirstResponder(d.textView) }
        updateTitle()
        updateStatus()
    }

    // MARK: 대화 상자

    private func makeDialog(title: String, message: String? = nil, content: NSView? = nil, primary: String? = nil, secondary: String? = nil,
                            close: String? = nil, completion: @escaping (ContentDialog.Result) -> Void) -> ContentDialog {
        ContentDialog(title: title, message: message, content: content, primary: primary, secondary: secondary, close: close) { [weak self] r in
            self?.dialog = nil
            completion(r)
            if self?.dialog == nil, !(self?.isSettingsMode ?? true), let d = self?.currentDoc, self?.findVisible == false {
                self?.window?.makeFirstResponder(d.textView)
            }
        }
    }

    private func present(_ dlg: ContentDialog) {
        FlyoutMenu.closeAll()
        dialog = dlg
        window?.makeKeyAndOrderFront(nil)
        dlg.present(in: rootView)
    }

    func showDialog(title: String, message: String, primary: String? = nil, secondary: String? = nil, close: String? = nil,
                    completion: @escaping (ContentDialog.Result) -> Void) {
        present(makeDialog(title: title, message: message, primary: primary, secondary: secondary, close: close, completion: completion))
    }

    // MARK: NSWindowDelegate

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        if let d = currentDoc, window.firstResponder === d.textView { return d.undo }
        return nil
    }

    func windowDidBecomeKey(_ notification: Notification) {
        titleBar.needsDisplay = true
        AppDelegate.shared.lastActive = self
    }
    func windowDidResignKey(_ notification: Notification) {
        titleBar.needsDisplay = true
        FlyoutMenu.closeAll()
    }
    func windowDidResize(_ notification: Notification) {
        titleBar.needsDisplay = true
        borderView.needsDisplay = true
        AppDelegate.shared.scheduleSessionSave()
    }
    func windowDidMove(_ notification: Notification) { AppDelegate.shared.scheduleSessionSave() }

    func windowWillClose(_ notification: Notification) {
        FlyoutMenu.closeAll()
        AppDelegate.shared.controllerClosed(self)
    }

    // MARK: 메뉴 항목 검증

    override func responds(to aSelector: Selector!) -> Bool {
        if isDialogOpen, aSelector != nil, NotepadWindowController.blockedWhenDialog.contains(aSelector) { return false }
        return super.responds(to: aSelector)
    }

    private static let blockedWhenDialog: Set<Selector> = [
        #selector(newTab(_:)), #selector(openDocument(_:)), #selector(saveDocument(_:)), #selector(saveDocumentAs(_:)),
        #selector(saveAll(_:)), #selector(closeCurrentTab(_:)), #selector(showFind(_:)), #selector(showReplace(_:)),
        #selector(goToLine(_:)), #selector(insertTimeDate(_:)), #selector(printDocument(_:)),
    ]
}

extension NotepadWindowController: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleStatusBar(_:)): item.state = Settings.shared.statusBar ? .on : .off
        case #selector(toggleWordWrap(_:)): item.state = Settings.shared.wordWrap ? .on : .off
        case #selector(searchWithBing(_:)): return hasSelection
        default: break
        }
        return !isDialogOpen || item.action == #selector(closeWindow(_:))
    }
}

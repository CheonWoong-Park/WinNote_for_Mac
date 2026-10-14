import AppKit

/// macOS 상단 메뉴 막대 (Cmd 단축키 담당. Ctrl 조합은 NotepadWindow에서 같은 항목으로 전달)
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()

        func item(_ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            return i
        }
        func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
            let m = NSMenu(title: title)
            items.forEach(m.addItem)
            let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            i.submenu = m
            return i
        }
        let f3 = String(UnicodeScalar(NSF3FunctionKey)!)
        let f5 = String(UnicodeScalar(NSF5FunctionKey)!)

        let app = submenu("메모장", [
            item("메모장 정보", #selector(AppDelegate.showAbout(_:))),
            .separator(),
            item("설정...", #selector(AppDelegate.openSettingsFromMenu(_:)), ","),
            .separator(),
            submenu("서비스", []),
            .separator(),
            item("메모장 가리기", #selector(NSApplication.hide(_:)), ""),
            item("기타 가리기", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("모두 보기", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("메모장 종료", #selector(NSApplication.terminate(_:)), "q"),
        ])
        NSApp.servicesMenu = app.submenu?.item(withTitle: "서비스")?.submenu
        main.addItem(app)

        main.addItem(submenu("파일", [
            item("새 탭", #selector(NotepadWindowController.newTab(_:)), "n"),
            item("새 창", #selector(NotepadWindowController.newWindow(_:)), "n", [.command, .shift]),
            item("열기...", #selector(NotepadWindowController.openDocument(_:)), "o"),
            item("저장", #selector(NotepadWindowController.saveDocument(_:)), "s"),
            item("다른 이름으로 저장...", #selector(NotepadWindowController.saveDocumentAs(_:)), "s", [.command, .shift]),
            item("모두 저장", #selector(NotepadWindowController.saveAll(_:)), "s", [.command, .option]),
            .separator(),
            item("페이지 설정...", #selector(NotepadWindowController.pageSetup(_:))),
            item("인쇄...", #selector(NotepadWindowController.printDocument(_:)), "p"),
            .separator(),
            item("탭 닫기", #selector(NotepadWindowController.closeCurrentTab(_:)), "w"),
            item("창 닫기", #selector(NotepadWindowController.closeWindow(_:)), "w", [.command, .shift]),
        ]))

        main.addItem(submenu("편집", [
            item("실행 취소", Selector(("undo:")), "z"),
            item("다시 실행", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("잘라내기", #selector(NSText.cut(_:)), "x"),
            item("복사", #selector(NSText.copy(_:)), "c"),
            item("붙여넣기", #selector(NSText.paste(_:)), "v"),
            item("삭제", #selector(NSText.delete(_:))),
            .separator(),
            item("Bing으로 검색...", #selector(NotepadWindowController.searchWithBing(_:)), "e"),
            item("찾기", #selector(NotepadWindowController.showFind(_:)), "f"),
            item("다음 찾기", #selector(NotepadWindowController.findNext(_:)), f3, []),
            item("이전 찾기", #selector(NotepadWindowController.findPrevious(_:)), f3, [.shift]),
            item("바꾸기", #selector(NotepadWindowController.showReplace(_:)), "h"),
            item("이동", #selector(NotepadWindowController.goToLine(_:)), "g"),
            .separator(),
            item("모두 선택", #selector(NSText.selectAll(_:)), "a"),
            item("시간/날짜", #selector(NotepadWindowController.insertTimeDate(_:)), f5, []),
            .separator(),
            item("글꼴", #selector(NotepadWindowController.showFontSettings(_:))),
        ]))

        main.addItem(submenu("보기", [
            submenu("확대/축소", [
                item("확대", #selector(NotepadWindowController.zoomIn(_:)), "="),
                item("축소", #selector(NotepadWindowController.zoomOut(_:)), "-"),
                item("기본 확대/축소 복원", #selector(NotepadWindowController.zoomReset(_:)), "0"),
            ]),
            item("상태 표시줄", #selector(NotepadWindowController.toggleStatusBar(_:))),
            item("자동 줄 바꿈", #selector(NotepadWindowController.toggleWordWrap(_:))),
        ]))

        let windowMenu = submenu("윈도우", [
            item("최소화", #selector(NSWindow.miniaturize(_:)), "m"),
            .separator(),
            item("모두 앞으로 가져오기", #selector(NSApplication.arrangeInFront(_:))),
        ])
        NSApp.windowsMenu = windowMenu.submenu
        main.addItem(windowMenu)
        return main
    }
}

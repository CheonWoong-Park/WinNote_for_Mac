import AppKit

/// 개발용: NOTEPAD_SNAPSHOT=경로 환경 변수가 있으면 창을 PNG로 저장 (화면 녹화 권한 불필요)
enum DebugSnapshot {
    static func runIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["NOTEPAD_SNAPSHOT"] else { return }
        let action = env["NOTEPAD_ACTION"] ?? ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard let c = AppDelegate.shared.active, let w = c.window else { return }
            if let size = env["NOTEPAD_SIZE"]?.split(separator: "x").compactMap({ Double($0) }), size.count == 2 {
                w.setContentSize(NSSize(width: size[0], height: size[1]))
            }
            switch action {
            case "file": c.menuBar.open(0, keyboard: false)
            case "edit": c.menuBar.open(1, keyboard: false)
            case "view": c.menuBar.open(2, keyboard: false)
            case "find": c.showFind(nil)
            case "replace": c.showReplace(nil)
            case "settings": c.openSettings(nil)
            case "goto": c.goToLine(nil)
            case "save": c.currentDoc?.isModified = true; c.closeCurrentTab(nil)
            case "clip":
                // 서식 있는 클립보드 → 붙여넣기 → 복사 결과 검사
                let pb = NSPasteboard.general
                pb.clearContents()
                let rich = NSAttributedString(string: "굵은 빨강\r\n두번째 줄", attributes: [.font: NSFont.boldSystemFont(ofSize: 30), .foregroundColor: NSColor.red, .link: URL(string: "https://x.com")!])
                pb.writeObjects([rich])
                let typesBefore = pb.types?.map { $0.rawValue } ?? []
                guard let d = c.currentDoc else { break }
                d.textView.string = ""
                c.window?.makeFirstResponder(d.textView)
                d.textView.paste(nil)
                let ts = d.textView.textStorage!
                var runs = 0
                ts.enumerateAttributes(in: NSRange(location: 0, length: ts.length)) { a, _, _ in runs += 1; if a[.link] != nil { runs += 100 } }
                let font = (ts.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName ?? "?"
                d.textView.selectAll(nil)
                d.textView.copy(nil)
                let typesAfter = pb.types?.map { $0.rawValue } ?? []
                let report = "before=\(typesBefore)\ntext=\(d.textView.string.debugDescription)\nruns=\(runs) font=\(font)\nafter=\(typesAfter)\nclip=\(pb.string(forType: .string).debugDescription)\n"
                try? report.write(toFile: path + ".txt", atomically: true, encoding: .utf8)
            case "select": c.currentDoc?.textView.insertText("Thsi is a mispelled sentense. ", replacementRange: NSRange(location: 0, length: 0)); c.currentDoc?.textView.setSelectedRange(NSRange(location: 3, length: 20))
            default: break
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                let windows = [w] + (w.childWindows ?? [])
                var union = w.frame
                for cw in windows { union = union.union(cw.frame) }
                let scale = w.backingScaleFactor
                let img = NSImage(size: union.size)
                img.lockFocus()
                for cw in windows {
                    guard let v = cw.contentView?.superview ?? cw.contentView else { continue }
                    let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
                    v.cacheDisplay(in: v.bounds, to: rep)
                    rep.draw(in: NSRect(x: cw.frame.minX - union.minX, y: cw.frame.minY - union.minY, width: cw.frame.width, height: cw.frame.height))
                }
                img.unlockFocus()
                let tiff = img.tiffRepresentation!
                let bmp = NSBitmapImageRep(data: tiff)!
                _ = scale
                try? bmp.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                if env["NOTEPAD_QUIT"] != nil { exit(0) }
            }
        }
    }
}

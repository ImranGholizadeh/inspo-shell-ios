// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

#if DEBUG
import AppKit
import WebKit

// The rehearsal's door: in a development build alone, and open only when
// the environment's INSPO_DESKTOP_REHEARSAL names a folder (no config word
// opens it, so an app started from Xcode or the Finder has none). A proof
// on this Mac plays the app through it as a person would and takes the
// app's own pictures: it writes one step into <folder>/step.json, the app
// plays it and writes <folder>/answer.json. A press and a typed letter are
// AppKit's own events given to the web view, not a script's. What is typed
// is written nowhere, and may be read from a file's field so the step
// itself does not hold it.
@MainActor
final class Rehearsal {
    static let shared = Rehearsal()
    private var folder: URL?
    private var timer: Timer?
    private var busy = false
    private var events = 0

    func begin() {
        guard timer == nil, let path = ProcessInfo.processInfo.environment["INSPO_DESKTOP_REHEARSAL"], !path.isEmpty else { return }
        folder = URL(fileURLWithPath: path)
        WorkspaceHelper.shared.say("the rehearsal's door is open: \(path)")
        // a rehearsal stays behind the windows of whoever is at this Mac: it
        // is never brought forward unless a step says so
        NSApp.windows.forEach { $0.orderBack(nil) }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in Rehearsal.shared.look() }
        }
    }

    private func look() {
        guard !busy, let folder else { return }
        let asked = folder.appendingPathComponent("step.json")
        guard let data = try? Data(contentsOf: asked),
              let step = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        try? FileManager.default.removeItem(at: asked)
        busy = true
        Task {
            var answer = await play(step)
            answer["did"] = step["do"] as? String ?? ""
            let out = JSONSerialization.isValidJSONObject(answer) ? answer : ["error": "the answer is no JSON"]
            let to = folder.appendingPathComponent("answer.json")
            try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]).write(to: to, options: .atomic)
            busy = false
            if step["do"] as? String == "quit" { NSApp.terminate(nil) }
        }
    }

    private var covered = false
    private var web: WKWebView? {
        guard let web = DesktopBridge.shared.webView, web.window != nil else { return nil }
        if !covered {
            // behind other windows the page would count as hidden and stand
            // still: for a rehearsal it runs on as if it were seen
            covered = true
            let off = NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")
            if web.responds(to: off) {
                typealias Set = @convention(c) (AnyObject, Selector, Bool) -> Void
                unsafeBitCast(web.method(for: off), to: Set.self)(web, off, false)
            }
        }
        return web
    }

    private func play(_ step: [String: Any]) async -> [String: Any] {
        let x = (step["x"] as? NSNumber)?.doubleValue ?? 0, y = (step["y"] as? NSNumber)?.doubleValue ?? 0
        switch step["do"] as? String ?? "" {
        case "window":
            let window = NSApp.windows.first { $0.isVisible }
            let frame = window?.frame ?? .zero
            return ["window": [frame.origin.x, frame.origin.y, frame.width, frame.height], "key": window?.isKeyWindow ?? false,
                    "active": NSApp.isActive, "page": web?.url?.absoluteString ?? "",
                    "status": WorkspaceHelper.shared.status, "offers": WorkspaceHelper.shared.offersToStop,
                    "folder": WorkspaceHelper.shared.folder, "titleBar": Double(DesktopBridge.titleBarHeight)]
        case "back":
            NSApp.windows.forEach { $0.orderBack(nil) }
            return ["active": NSApp.isActive]
        case "again":
            guard web != nil else { return ["error": "no page is shown"] }
            DesktopBridge.shared.showAgain(hiddenFor: (step["for"] as? NSNumber)?.doubleValue ?? 0.3)
            return [:]
        case "front":
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.isVisible }?.makeKeyAndOrderFront(nil)
            return ["active": NSApp.isActive]
        case "size":
            guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return ["error": "no window"] }
            window.setContentSize(NSSize(width: x, height: y))
            return ["content": [window.contentLayoutRect.width, window.contentView?.bounds.height ?? 0]]
        case "picture":
            guard let to = step["to"] as? String else { return ["error": "no file named"] }
            return await picture(to)
        case "read":
            guard let web else { return ["error": "no page is shown"] }
            return await withCheckedContinuation { done in
                web.callAsyncJavaScript(step["js"] as? String ?? "", arguments: [:], in: nil, in: .page) { result in
                    switch result {
                    case .success(let value):
                        done.resume(returning: ["value": JSONSerialization.isValidJSONObject([value]) ? value : String(describing: value)])
                    case .failure(let error):
                        done.resume(returning: ["error": "\(error)"])
                    }
                }
            }
        case "move":
            return mouse(.mouseMoved, x, y)
        case "down":
            return mouse(.leftMouseDown, x, y)
        case "up":
            return mouse(.leftMouseUp, x, y)
        case "click":
            _ = mouse(.mouseMoved, x, y)
            try? await Task.sleep(nanoseconds: 60_000_000)
            _ = mouse(.leftMouseDown, x, y)
            try? await Task.sleep(nanoseconds: 60_000_000)
            return mouse(.leftMouseUp, x, y)
        case "press":
            // the one thing the window's own words offer (no page is shown then)
            guard WorkspaceHelper.shared.offersToStop else { return ["error": "the window offers nothing"] }
            WorkspaceHelper.shared.stopItAndOpen()
            return [:]
        case "type":
            var text = step["text"] as? String ?? ""
            if let file = step["file"] as? String, let field = step["field"] as? String {
                // a word kept in a file (an accounts file's field): read here, written nowhere
                guard let data = FileManager.default.contents(atPath: file),
                      let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
                      let word = rows.first?[field] as? String else { return ["error": "no such field in the file"] }
                text = word
            }
            guard let web else { return ["error": "no page is shown"] }
            if step["as"] as? String == "inserted" {
                // behind other windows the web view takes no key: the page's
                // own insertion into the field that holds the focus instead
                return await withCheckedContinuation { done in
                    web.callAsyncJavaScript("return document.execCommand('insertText', false, word)", arguments: ["word": text], in: nil, in: .page) { result in
                        if case .success(let value) = result { done.resume(returning: ["inserted": text.count, "taken": value as? Bool ?? false]) } else { done.resume(returning: ["error": "not inserted"]) }
                    }
                }
            }
            web.window?.makeFirstResponder(web)
            for c in text {
                key(String(c), 0, web)
                try? await Task.sleep(nanoseconds: 25_000_000)
            }
            return ["typed": text.count]
        case "key":
            guard let web else { return ["error": "no page is shown"] }
            let keys: [String: (String, UInt16)] = ["return": ("\r", 36), "tab": ("\t", 48), "escape": ("\u{1b}", 53), "delete": ("\u{7f}", 51)]
            guard let (characters, code) = keys[step["name"] as? String ?? ""] else { return ["error": "no such key"] }
            key(characters, code, web)
            return [:]
        case "menu":
            let title = step["title"] as? String ?? ""
            var found: NSMenuItem?
            func search(_ menu: NSMenu?) {
                for item in menu?.items ?? [] {
                    if item.title == title { found = item }
                    search(item.submenu)
                }
            }
            search(NSApp.mainMenu)
            guard let item = found else { return ["found": false] }
            if step["press"] as? Bool == true, let menu = item.menu { menu.performActionForItem(at: menu.index(of: item)) }
            return ["found": true, "enabled": item.isEnabled, "under": item.menu?.title ?? ""]
        case "quit":
            return [:] // the app quits after this answer is written, as its Quit does
        default:
            return ["error": "no such step"]
        }
    }

    /// A press or a move at a point of the page (its own points, from its top left).
    private func mouse(_ type: NSEvent.EventType, _ x: Double, _ y: Double) -> [String: Any] {
        guard let web, let window = web.window else { return ["error": "no page is shown"] }
        let inView = NSPoint(x: x, y: web.isFlipped ? y : Double(web.bounds.height) - y)
        events += 1
        guard let event = NSEvent.mouseEvent(with: type, location: web.convert(inView, to: nil), modifierFlags: [],
                                             timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                             context: nil, eventNumber: events, clickCount: type == .mouseMoved ? 0 : 1,
                                             pressure: type == .leftMouseDown ? 1 : 0) else { return ["error": "no event"] }
        switch type {
        case .leftMouseDown: web.mouseDown(with: event)
        case .leftMouseUp: web.mouseUp(with: event)
        default:
            // behind other windows a web view takes no move: its own way of
            // being told one, where it has it
            let told = NSSelectorFromString("_simulateMouseMove:")
            if web.responds(to: told) { web.perform(told, with: event) } else { web.mouseMoved(with: event) }
        }
        return [:]
    }

    private func key(_ characters: String, _ code: UInt16, _ web: WKWebView) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: web.window?.windowNumber ?? 0, context: nil, characters: characters,
                                               charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) else { continue }
            if type == .keyDown { web.keyDown(with: event) } else { web.keyUp(with: event) }
        }
    }

    /// The app's own picture of what its window shows: the page as the web
    /// view draws it, or the window's words where no page is shown.
    private func picture(_ to: String) async -> [String: Any] {
        var image: NSImage?
        var size = NSSize.zero
        if let web, !web.isHidden {
            size = web.bounds.size
            image = await withCheckedContinuation { done in
                web.takeSnapshot(with: nil) { got, _ in done.resume(returning: got) }
            }
        } else if let view = NSApp.windows.first(where: { $0.isVisible })?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            size = view.bounds.size
            view.cacheDisplay(in: view.bounds, to: rep)
            let made = NSImage(size: size)
            made.addRepresentation(rep)
            image = made
        }
        guard let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return ["error": "no picture could be taken"] }
        do { try png.write(to: URL(fileURLWithPath: to)) } catch { return ["error": "\(error.localizedDescription)"] }
        return ["points": [size.width, size.height], "pixels": [rep.pixelsWide, rep.pixelsHigh], "of": web == nil || web?.isHidden == true ? "the window's words" : "the page"]
    }
}
#endif

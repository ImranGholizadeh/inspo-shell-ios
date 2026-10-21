// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

import AppKit
import SwiftUI
import WebKit

// The desktop app's web view and bridge, as the iOS shell's (ShellBridge):
// the page asks through window.webkit.messageHandlers.inspo ({type:
// "haptic"} played on the trackpad, {type: "native"} for a native library,
// NativeLibrary.swift, shared with the iOS shell), and the shell answers
// through window.inspo, or window.inspoWaiting before the page is ready.
// It says what it does in window.inspoShell.acts (ShellActs.swift).
//
// It answers one page alone, the one the app opens, through the phone's
// door (Shell/OwnPage.swift): a link or a redirect out of that site puts
// another site's page in the app with the bridge in it, and that page is
// answered nothing and has nothing of its kept. A request is taken only
// from the main frame of a page of the opened address's origin; a console
// line from any frame of that origin; what the bridge tells a page is told
// only while the page held (its first bytes last came in) is of that
// origin, and an answer only to the page that asked.
final class DesktopBridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    static let shared = DesktopBridge()
    /// The height of the title bar the page runs under
    static let titleBarHeight = NSWindow.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled]).height - 100
    private(set) weak var webView: WKWebView?
    private var waiting = PageWaiting()
    private var door = PageDoor(own: nil)
    private var loaded = false

    func makeWebView(url: URL) -> WKWebView {
        door = PageDoor(own: PageOrigin(url))
        let config = WKWebViewConfiguration()
        config.applicationNameForUserAgent = "InspoDesktop/1"
        config.userContentController.add(self, name: "inspo")
        // what the page says to its console, and an error nobody caught, are
        // kept in the launch's folder (PageLog.swift): no field is listened
        // to, and only a page of the opened address's site is heard
        config.userContentController.add(self, name: PageLog.handler)
        config.userContentController.addUserScript(WKUserScript(
            source: PageLog.script, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        // the title bar the page runs under, as the safe area the host
        // covers: the renderer reads window.inspoSafeArea beside the
        // browser's own insets, and Go offers it as safe-area-top
        config.userContentController.addUserScript(WKUserScript(
            source: "window.inspoSafeArea = { top: \(Int(Self.titleBarHeight.rounded())) };",
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        // what this shell does, said before the page's own script runs: a
        // share and a clipboard are not among them, so the page does them
        // the web view's own way, or says at once that it cannot
        // (ShellActs.swift)
        config.userContentController.addUserScript(WKUserScript(
            source: ShellActs.script(ShellActs.desktop), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = self
        view.setValue(false, forKey: "drawsBackground")
        #if DEBUG
        view.isInspectable = true // Safari's Web Inspector, on a development build only
        #endif
        webView = view
        view.load(URLRequest(url: url))
        return view
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        let asker = Self.origin(of: message.frameInfo)
        if message.name == PageLog.handler {
            if let line = PageLog.line(message.body, from: asker, door: door) { WorkspaceHelper.shared.page?.line(line) }
            return
        }
        // a page that is not the one the app opens, or a frame inside it, is
        // answered nothing, and told nothing of its being refused
        guard let body = door.take(message.body, from: asker, mainFrame: message.frameInfo.isMainFrame),
              let type = body["type"] as? String else { return }
        // an answer is the page's that asked: told to no page that takes its place
        let page = waiting.page
        switch type {
        case "haptic":
            // a Mac feels only the trackpad's taps: every pattern is one
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        case "native":
            NativeLibraries.shared.handle(body,
                answered: { [weak self] id, value in self?.call("nativeAnswered", for: page, id, value) },
                failed: { [weak self] id, error in self?.call("nativeFailed", for: page, id, error) })
        default:
            break
        }
    }

    /// A frame's origin, as the web view says it.
    static func origin(of frame: WKFrameInfo) -> PageOrigin {
        let origin = frame.securityOrigin
        return PageOrigin(scheme: origin.protocol, host: origin.host, port: origin.port)
    }

    private func call(_ hook: String, for page: Int? = nil, _ values: Any...) {
        guard waiting.isFor(page) else { return }
        guard JSONSerialization.isValidJSONObject(values),
              let data = try? JSONSerialization.data(withJSONObject: values),
              let args = String(data: data, encoding: .utf8) else { return }
        let js = "(function(h,a){var i=window.inspo;if(i&&i[h]){i[h].apply(null,a)}else{(window.inspoWaiting=window.inspoWaiting||[]).push([h].concat(a))}})(\"\(hook)\",\(args))"
        guard loaded, let webView, door.isOwn(waiting.held) else {
            waiting.wait(js, for: page)
            return
        }
        webView.evaluateJavaScript(js)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        NativeLibraries.shared.stopAll()
    }

    /// Another page has taken the place of the one the web view held: it
    /// is the page held from here, and what the bridge had to tell the page
    /// before is nobody's now.
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        waiting.pageChanged(to: PageOrigin(webView.url))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        WorkspaceHelper.shared.page?.line("the page did not load: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        WorkspaceHelper.shared.page?.line("the page did not begin to load: \(error.localizedDescription)")
    }

    /// The page is hidden for a moment and shown again, which it tells its
    /// engine as the app hidden, then shown.
    func showAgain(hiddenFor seconds: Double) {
        guard let webView, !webView.isHidden else { return }
        webView.isHidden = true
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { webView.isHidden = false }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        WorkspaceHelper.shared.page?.line("the page loaded: \(webView.url?.absoluteString ?? "")")
        if DesktopApp.opensWorkspace { FirstFrame.watch(webView) }
        // A WAY ROUND, NOT A MEND (13 October 2026): the editor's opening
        // does not bring its sign-in in on an arrival that is visible from
        // its start, and does once the page has been out of sight for some
        // seconds and is shown again (it then opens its stream anew and is
        // drawn whole). Where the config says two numbers
        // (INSPO_DESKTOP_SHOWN_AGAIN: seconds after a load, seconds out of
        // sight), the app does that once after each load; empty: never.
        let again = DesktopWords.word("InspoShownAgain").split(separator: " ").compactMap { Double($0) }
        if again.count == 2, again[0] >= 0, again[1] > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + again[0]) { [weak self] in
                WorkspaceHelper.shared.say("the page is hidden for \(again[1]) s and shown again, \(again[0]) s after its load (INSPO_DESKTOP_SHOWN_AGAIN)")
                self?.showAgain(hiddenFor: again[1])
            }
        }
        loaded = true
        // a page that is not the one the app opens is told nothing: what waits, waits on
        if door.isOwn(waiting.held) {
            waiting.take().forEach { webView.evaluateJavaScript($0) }
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        WorkspaceHelper.shared.page?.line("the page's process ended; the page is loaded again")
        loaded = false
        waiting.pageChanged(to: nil) // no page is held, and what waited for the page that ended is nobody's
        NativeLibraries.shared.stopAll()
        webView.reload()
    }
}

struct DesktopView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> NSView {
        // the web view under a strip as tall as the title bar, which moves
        // the window as the bar did (the page runs under the bar, so the web
        // view would take the drag); genes keep their controls below it
        // (safe-area-top), and the traffic lights stay above both
        let container = NSView()
        let web = DesktopBridge.shared.makeWebView(url: url)
        let strip = TitleBarDragView()
        for view in [web, strip] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        // (the page under an opaque cover of the editor's ground until its first frame: FirstFrame)
        if DesktopApp.opensWorkspace { FirstFrame.covers(web, in: container) }
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: container.topAnchor),
            web.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            web.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            strip.topAnchor.constraint(equalTo: container.topAnchor),
            strip.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            strip.heightAnchor.constraint(equalToConstant: DesktopBridge.titleBarHeight),
        ])
        return container
    }
    func updateNSView(_ view: NSView, context: Context) {}
}

/// The title bar's strip: a drag moves the window, and a double-click does
/// what the system's setting says (zoom, minimise, or nothing).
final class TitleBarDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) {
        guard event.clickCount == 2 else {
            window?.performDrag(with: event)
            return
        }
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize": window?.performMiniaturize(nil)
        case "None": break
        default: window?.performZoom(nil)
        }
    }
}

/// The window's first frame (owner, 19 October 2026: "The workspace needs
/// to start fast..optimistically.. you should feel no step before the
/// animation start"). While the app opens the workspace no words are
/// shown: the window stands in the editor's own ground, and over the web
/// view lies an opaque cover of that ground, which takes no press and no
/// key, until the page has drawn its first frame (its root and something
/// in it); the cover then goes and the page, already moving, is there. The
/// window is visible all along, so WebKit draws the page under the cover
/// as it draws any page seen (no private switch). The cover goes too when
/// the window has words to say (a start that failed, a workspace already
/// open) and, whatever happens, 8 s after the launch. Each moment is said
/// in the launch's app.log, in milliseconds after the launch.
@MainActor
enum FirstFrame {
    /// when the system started this process (its own clock: a Swift
    /// static is made only when first asked for)
    static let launched: Date = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, 4, &info, &size, nil, 0) == 0 else { return Date() }
        let t = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000)
    }()
    private static var shown = false
    private static var watching = false
    private static weak var cover: NSView?
    private static weak var page: WKWebView?

    static func sinceLaunch() -> Int { Int(Date().timeIntervalSince(launched) * 1000) }

    /// the editor's ground, as the window's words stand on it
    static let ground = NSColor(calibratedHue: 214 / 360, saturation: 0.33, brightness: 0.12, alpha: 1)

    static func began() {
        WorkspaceHelper.shared.say("the window stands in its ground with no words until the page has drawn, \(sinceLaunch()) ms after the launch")
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { show(because: "nothing was drawn in 8 s") }
    }

    /// The cover laid over a web view while the page has not drawn: one a
    /// shown window no longer needs is not laid.
    static func covers(_ web: WKWebView, in container: NSView) {
        page = web
        guard !shown else { return }
        let view = FirstFrameCover()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view, positioned: .above, relativeTo: web)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        cover = view
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
    }

    static func show(because why: String) {
        guard !shown else { return }
        shown = true
        if let cover {
            let window = cover.window
            cover.removeFromSuperview()
            if let page { window?.makeFirstResponder(page) }
        }
        WorkspaceHelper.shared.say("the page is shown, \(sinceLaunch()) ms after the launch: \(why)")
    }

    /// how many elements the page drew of its root and in it: the root is
    /// the one its instance names (<script id="inspo-instance">), drawn by
    /// its locus; none drawn yet: 0
    static let rootDrawn = "(()=>{try{const i=JSON.parse(document.getElementById('inspo-instance').textContent);const r=document.getElementById(i.root);return r?1+r.querySelectorAll('*').length:0}catch(e){return 0}})()"

    /// The page's first frame: its root drawn with something in it
    /// (rootDrawn), asked every 30 ms once the page has loaded. The page is
    /// only looked at; nothing of it is changed.
    static func watch(_ webView: WKWebView) {
        guard !shown, !watching else { return }
        watching = true
        WorkspaceHelper.shared.say("the page loaded, \(sinceLaunch()) ms after the launch")
        var asked = 0
        func ask() {
            asked += 1
            webView.evaluateJavaScript(rootDrawn) { value, error in
                let drawn = (value as? NSNumber)?.intValue ?? 0
                if asked <= 3 || asked % 50 == 0 { WorkspaceHelper.shared.say("the page's first frame asked (\(asked)): \(drawn) drawn\(error.map { ", " + $0.localizedDescription } ?? "")") }
                if drawn > 1 {
                    show(because: "the page drew its first frame (its root and \(drawn - 1) things drawn in it)")
                } else if !shown {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: ask)
                }
            }
        }
        ask()
    }
}

/// The cover over the page until its first frame: the editor's ground,
/// opaque; it takes every press and every key, so nothing reaches a page a
/// person cannot see yet.
final class FirstFrameCover: NSView {
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        FirstFrame.ground.setFill()
        dirtyRect.fill()
    }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
    override func keyDown(with event: NSEvent) {}
    override func keyUp(with event: NSEvent) {}
    override func performKeyEquivalent(with event: NSEvent) -> Bool { false }
}

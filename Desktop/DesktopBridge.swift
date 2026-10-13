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
final class DesktopBridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    static let shared = DesktopBridge()
    /// The height of the title bar the page runs under
    static let titleBarHeight = NSWindow.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled]).height - 100
    private(set) weak var webView: WKWebView?
    private var pending: [String] = []
    private var loaded = false

    func makeWebView(url: URL) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.applicationNameForUserAgent = "InspoDesktop/1"
        config.userContentController.add(self, name: "inspo")
        // what the page says to its console, and an error nobody caught, are
        // kept in the launch's folder (PageLog.swift): no field is listened to
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
        if message.name == PageLog.handler {
            if let line = PageLog.line(message.body) { WorkspaceHelper.shared.page?.line(line) }
            return
        }
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "haptic":
            // a Mac feels only the trackpad's taps: every pattern is one
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        case "native":
            NativeLibraries.shared.handle(body,
                answered: { [weak self] id, value in self?.call("nativeAnswered", id, value) },
                failed: { [weak self] id, error in self?.call("nativeFailed", id, error) })
        default:
            break
        }
    }

    private func call(_ hook: String, _ values: Any...) {
        guard JSONSerialization.isValidJSONObject(values),
              let data = try? JSONSerialization.data(withJSONObject: values),
              let args = String(data: data, encoding: .utf8) else { return }
        let js = "(function(h,a){var i=window.inspo;if(i&&i[h]){i[h].apply(null,a)}else{(window.inspoWaiting=window.inspoWaiting||[]).push([h].concat(a))}})(\"\(hook)\",\(args))"
        guard loaded, let webView else {
            pending.append(js)
            return
        }
        webView.evaluateJavaScript(js)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        NativeLibraries.shared.stopAll()
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
        let waiting = pending
        pending = []
        waiting.forEach { webView.evaluateJavaScript($0) }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        WorkspaceHelper.shared.page?.line("the page's process ended; the page is loaded again")
        loaded = false
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

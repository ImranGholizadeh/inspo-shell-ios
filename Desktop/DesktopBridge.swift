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
final class DesktopBridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    static let shared = DesktopBridge()
    private(set) weak var webView: WKWebView?
    private var pending: [String] = []
    private var loaded = false

    func makeWebView(url: URL) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.applicationNameForUserAgent = "InspoDesktop/1"
        config.userContentController.add(self, name: "inspo")
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

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        let waiting = pending
        pending = []
        waiting.forEach { webView.evaluateJavaScript($0) }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loaded = false
        NativeLibraries.shared.stopAll()
        webView.reload()
    }
}

struct DesktopView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> WKWebView { DesktopBridge.shared.makeWebView(url: url) }
    func updateNSView(_ view: WKWebView, context: Context) {}
}

// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

import SwiftUI
import UIKit
import WebKit

// The web view and its bridge. The page (inspo-core-js) talks to the shell
// through window.webkit.messageHandlers.inspo ({type: "haptic", mode}); the
// shell talks to the page through window.inspo, which the page's app.js
// sets (linkOpened, nativeLibraryAnswered), and what arrives before the page
// is ready waits in window.inspoWaiting.
final class ShellBridge: NSObject, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate {
    static let shared = ShellBridge()
    private(set) weak var webView: WKWebView?
    private var pending: [String] = [] // calls made before the first page finished loading
    private var loaded = false

    /// The gene's page, from the build's INSPO_URL.
    var startURL: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "InspoURL") as? String).flatMap(URL.init(string:))
    }

    func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true // a camera's picture plays in its molecule
        config.mediaTypesRequiringUserActionForPlayback = []
        config.applicationNameForUserAgent = "InspoShell/1"
        config.userContentController.add(self, name: "inspo")
        let view = WKWebView(frame: .zero, configuration: config)
        view.uiDelegate = self
        view.navigationDelegate = self
        view.scrollView.contentInsetAdjustmentBehavior = .never // the page places itself by the safe-area tokens
        view.scrollView.bounces = false
        view.isOpaque = false
        view.isInspectable = true // Safari's Web Inspector, on a development build
        webView = view
        if let url = startURL {
            view.load(URLRequest(url: url))
        }
        return view
    }

    // MARK: the page asks

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "haptic":
            playHaptic(body["mode"] as? String ?? "")
        default:
            break
        }
    }

    /// A haptic's pattern (the device neuron's modes); an unknown one plays nothing.
    private func playHaptic(_ mode: String) {
        switch mode {
        case "light": UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case "medium": UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case "heavy": UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case "success": UINotificationFeedbackGenerator().notificationOccurred(.success)
        case "warning": UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case "error": UINotificationFeedbackGenerator().notificationOccurred(.error)
        default: break
        }
    }

    /// The camera, for the gene's own page only: its device neuron starts it.
    /// The app's camera permission (asked by iOS once) is the person's answer.
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let own = origin.host == startURL?.host
        decisionHandler(own && type == .camera ? .grant : .deny)
    }

    // MARK: the shell tells the page

    /// A link that opened the app, or reached it while open: the page's
    /// link-opened trigger.
    func linkOpened(_ url: URL) {
        call("linkOpened", url.absoluteString)
    }

    /// A native library's answer (a vendor's reader, added as a Swift
    /// package, calls this with its result): the page's
    /// native-library-answered trigger. The result must be JSON-shaped.
    func nativeLibraryAnswered(_ result: Any) {
        call("nativeLibraryAnswered", result)
    }

    private func call(_ hook: String, _ value: Any) {
        guard JSONSerialization.isValidJSONObject([value]),
              let data = try? JSONSerialization.data(withJSONObject: [value]),
              let list = String(data: data, encoding: .utf8) else { return }
        let arg = String(list.dropFirst().dropLast()) // the value as JSON
        let js = "(function(h,v){var i=window.inspo;if(i&&i[h]){i[h](v)}else{(window.inspoWaiting=window.inspoWaiting||[]).push([h,v])}})(\"\(hook)\",\(arg))"
        guard loaded, let webView else {
            pending.append(js)
            return
        }
        webView.evaluateJavaScript(js)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        let waiting = pending
        pending = []
        waiting.forEach { webView.evaluateJavaScript($0) }
    }
}

struct ShellView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { ShellBridge.shared.makeWebView() }
    func updateUIView(_ view: WKWebView, context: Context) {}
}

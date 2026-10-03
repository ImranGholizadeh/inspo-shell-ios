// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

import IDScannerBinding
import Network
import SwiftUI
import UIKit
import WebKit

/// What the app shows over its web view: the splash until a page has
/// loaded, and whether the system says there is no network meanwhile.
final class ShellState: ObservableObject {
    @Published var pageLoaded = false
    @Published var noNetwork = false
}

// The web view and its bridge. The page (inspo-core-js) talks to the shell
// through window.webkit.messageHandlers.inspo ({type: "haptic", mode},
// {type: "torch", mode}: the phone's light, Torch.swift,
// {type: "share", id, ...} and {type: "clipboard", id, text}: the share
// sheet and the clipboard, HandOver.swift, and
// {type: "native", ...}: a native library's call or stream, NativeLibrary.swift);
// the shell talks to the page through window.inspo, which the page sets
// (linkOpened, nativeAnswered, nativeFailed, deviceAnswered, deviceFailed),
// and what arrives before the page is ready waits in window.inspoWaiting.
// It says what it does in window.inspoShell.acts (ShellActs.swift), so a
// page newer or older than this shell knows what to ask of it.
final class ShellBridge: NSObject, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate {
    static let shared = ShellBridge()
    private(set) weak var webView: WKWebView?
    private var pending: [String] = [] // calls made before the first page finished loading
    private var loaded = false
    let state = ShellState()
    // a page that did not load is loaded again (LoadAgain.swift)
    private lazy var again = LoadAgain(load: { [weak self] in self?.loadPage() })
    private let network = NWPathMonitor()

    /// The gene's page, from the build's INSPO_URL.
    var startURL: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "InspoURL") as? String).flatMap(URL.init(string:))
    }

    func makeWebView() -> WKWebView {
        // the Bluetooth ID scanner a customer's workspace links (E47), under
        // the library name its xcconfig gives; a test build's stand-in (E42)
        // takes the same name in its place
        let scanner = Bundle.main.object(forInfoDictionaryKey: "InspoIDScanner") as? String ?? ""
        if !scanner.isEmpty, let linked = IDScannerAdapter.linked(name: scanner, scanner: IDScannerBinding.scanner()) {
            NativeLibraries.shared.register(linked)
        }
        if let standIn = StandInReader.fromBuild() {
            NativeLibraries.shared.register(standIn)
        }
        let config = WKWebViewConfiguration()
        // the app's own persistent store: cookies, localStorage and
        // IndexedDB (where Firebase Auth keeps who signed in) outlive the
        // app's close, a force-quit at once after a write included (E53)
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true // a camera's picture plays in its molecule
        config.mediaTypesRequiringUserActionForPlayback = []
        config.applicationNameForUserAgent = "InspoShell/1"
        config.userContentController.add(self, name: "inspo")
        // what this shell does, said before the page's own script runs: the
        // page never hands it a request it would not answer (ShellActs.swift)
        config.userContentController.addUserScript(WKUserScript(
            source: ShellActs.script(ShellActs.phone), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let view = WKWebView(frame: .zero, configuration: config)
        view.uiDelegate = self
        view.navigationDelegate = self
        view.scrollView.contentInsetAdjustmentBehavior = .never // the page places itself by the safe-area tokens
        view.scrollView.bounces = false
        view.isOpaque = false
        #if DEBUG
        view.isInspectable = true // Safari's Web Inspector, on a development build only
        #endif
        webView = view
        // the phone's own share sheet, shown over the page, and its clipboard
        HandOver.shared.sheet = { [weak view] in view.map(PhoneShareSheet.init(over:)) }
        HandOver.shared.clipboard = { PhoneClipboard() }
        // a light the page lit goes out when the app leaves the screen
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                               object: nil, queue: .main) { _ in Torch.shared.putOut() }
        // the system's word that the network is back, and the app coming to
        // the front: a load that waits is tried at once
        network.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.state.noNetwork = path.status != .satisfied
                if path.status == .satisfied { self?.again.wake() }
            }
        }
        network.start(queue: DispatchQueue.global(qos: .utility))
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.again.wake() }
        loadPage()
        return view
    }

    /// Loads the gene's page: afresh while none has loaded, else again where it is.
    private func loadPage() {
        guard let webView else { return }
        if state.pageLoaded, webView.url != nil {
            webView.reload()
        } else if let url = startURL {
            webView.load(URLRequest(url: url))
        }
    }

    // MARK: the page asks

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "haptic":
            playHaptic(body["mode"] as? String ?? "")
        case "torch":
            #if DEBUG
            print("shell: the page asked for the torch") // a development build says so; a simulator has no light to show it
            #endif
            Torch.shared.take(mode: body["mode"] as? String ?? "")
        case "share", "clipboard":
            // answered once, by the request's id; one with no id has no one to answer
            guard let id = body["id"] as? String, !id.isEmpty else { return }
            #if DEBUG
            print("shell: the page asked for the \(type == "share" ? "share sheet" : "clipboard")") // never what it handed over
            #endif
            let answered = { [weak self] in
                #if DEBUG
                print("shell: the \(type == "share" ? "share sheet closed" : "clipboard holds the text")")
                #endif
                self?.call("deviceAnswered", id)
            }
            let failed = { [weak self] (reason: String) in
                #if DEBUG
                print("shell: the \(type) failed: \(reason)")
                #endif
                self?.call("deviceFailed", id, reason)
            }
            if type == "share" {
                HandOver.shared.share(body, answered: answered, failed: failed)
            } else {
                HandOver.shared.copy(body, answered: answered, failed: failed)
            }
        case "native":
            NativeLibraries.shared.handle(body,
                answered: { [weak self] id, value in self?.call("nativeAnswered", id, value) },
                failed: { [weak self] id, error in self?.call("nativeFailed", id, error) })
        default:
            break
        }
    }

    /// A haptic's pattern (the device neuron's modes), or the system's long
    /// vibration; an unknown one plays nothing.
    private func playHaptic(_ mode: String) {
        switch mode {
        case "light": UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case "medium": UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case "heavy": UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case "success": UINotificationFeedbackGenerator().notificationOccurred(.success)
        case "warning": UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case "error": UINotificationFeedbackGenerator().notificationOccurred(.error)
        case "vibrate":
            #if DEBUG
            print("shell: the page asked for the long vibration") // a development build says so; a simulator has no motor to show it
            #endif
            playLongVibration()
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
        // a test build's stand-in plays its scenes by a link, which is its own
        if StandInReader.plays(url) { return }
        call("linkOpened", url.absoluteString)
    }

    /// Calls one of the page's hooks with JSON-shaped values; before the
    /// page is ready the call waits, in order.
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

    /// iOS ends a web view's content while the app is away when it needs
    /// the memory (a running camera makes it likely): the view is left
    /// empty, a black screen that answers nothing. The shell loads the page
    /// again (owner, 2026-09-29: "Recover where it broke").
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loaded = false
        state.pageLoaded = false // the splash, not an empty view, until it has loaded again
        NativeLibraries.shared.stopAll() // the page that asked is gone
        Torch.shared.putOut()
        loadPage()
    }

    /// A page that did not load (the app opened with no signal, or brought
    /// back by iOS with none): the splash stays, and the load is tried
    /// again after a wait, and at once when the network is back
    /// (LoadAgain.swift). A load another load took the place of is no failure.
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        pageDidNotLoad(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        pageDidNotLoad(error)
    }

    private func pageDidNotLoad(_ error: Error) {
        let e = error as NSError
        if e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled { return }
        #if DEBUG
        print("shell: the page did not load (\(e.domain) \(e.code)); it is tried again")
        #endif
        loaded = false
        state.pageLoaded = false
        again.failed()
    }

    /// A page loading afresh: the streams the page before asked for end,
    /// and a light it lit goes out.
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        NativeLibraries.shared.stopAll()
        Torch.shared.putOut()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        again.loaded()
        state.pageLoaded = true
        let waiting = pending
        pending = []
        waiting.forEach { webView.evaluateJavaScript($0) }
    }
}

struct ShellView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { ShellBridge.shared.makeWebView() }
    func updateUIView(_ view: WKWebView, context: Context) {}
}

/// The splash, as the launch screen draws it (the launch background and the
/// mark in its middle; a customer's own where its build lays them over),
/// kept over the web view until a page has loaded: an app opened with no
/// signal shows what it showed as it opened, not an empty view. While the
/// system says there is no network, a small sign near the bottom edge says
/// so, in no language.
struct SplashView: View {
    @ObservedObject var state: ShellState
    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            Image("LaunchMark")
            if state.noNetwork {
                // near the bottom edge, clear of a mark of any size
                VStack {
                    Spacer()
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 44)
                        .accessibilityLabel(Text("No connection"))
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.noNetwork)
    }
}

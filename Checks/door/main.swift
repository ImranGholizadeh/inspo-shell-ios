// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

// A check of whose page the shell answers (Shell/OwnPage.swift), on this
// Mac: a request is taken only from the main frame of the build's own
// page, a page of another origin that names a scan's every field in keep
// is handed nothing, an answer is told only to the page that asked, and
// the phone's bridge passes every request through that door:
// scripts/check-door.sh.

import Foundation
import IDScannerSurface

var passed = 0, failed = 0
func check(_ name: String, _ got: [String], _ want: [String]) {
    if got == want { passed += 1 } else { failed += 1; print("FAIL \(name):\n  got  \(got)\n  want \(want)") }
}

/// An answer with every field: key=value, in the keys' order.
func fields(_ value: [String: Any]) -> String {
    value.isEmpty ? "{}" : value.keys.sorted().map { "\($0)=\(value[$0]!)" }.joined(separator: " ")
}

let own = PageOrigin(URL(string: "https://gene.example/tally"))
let door = PageDoor(own: own)

/// A page's request as the bridge takes it: through the door, and a native
/// library's request on to the libraries. What the page was handed.
func asks(_ body: [String: Any], from page: String, mainFrame: Bool = true, door: PageDoor = door) -> [String] {
    var handed: [String] = []
    guard let taken = door.take(body, from: PageOrigin(URL(string: page)), mainFrame: mainFrame), taken["type"] as? String == "native" else { return handed }
    NativeLibraries.shared.handle(taken, answered: { _, value in handed.append(fields(value)) }, failed: { _, error in handed.append("error: " + error) })
    return handed
}

// MARK: a page's origin

do {
    func origin(_ text: String) -> String {
        PageOrigin(URL(string: text)).map { "\($0.scheme) \($0.host) \($0.port)" } ?? "none"
    }
    check("an origin is the scheme, the host and the port, the scheme's own when none is named, in small letters",
          ["https://gene.example/tally", "HTTPS://Gene.Example:443/x?y#z", "http://127.0.0.1:6901/", "http://localhost/", "about:blank", "file:///a/b"].map(origin),
          ["https gene.example 443", "https gene.example 443", "http 127.0.0.1 6901", "http localhost 80", "none", "none"])
    let asFrame = PageOrigin(scheme: "https", host: "gene.example", port: 0)
    check("a frame's origin as the web view says it, port 0, is the same origin as the address's",
          [String(asFrame == own), String(PageOrigin(scheme: "https", host: "gene.example", port: 8443) == own)], ["true", "false"])
}

// MARK: who is taken

do {
    let body: [String: Any] = ["type": "haptic", "mode": "light"]
    func taken(_ page: String?, mainFrame: Bool = true, door: PageDoor = door) -> String {
        door.take(body, from: page.flatMap { PageOrigin(URL(string: $0)) }, mainFrame: mainFrame) == nil ? "refused" : "taken"
    }
    check("the build's own page is taken, on any path of its site", [taken("https://gene.example/tally"), taken("https://gene.example/other/page?x=1")],
          ["taken", "taken"])
    check("a page of another host, of another scheme, of another port, of a host that only ends or begins as the build's, and a page with no origin are refused",
          [taken("https://other.example/tally"), taken("http://gene.example/tally"), taken("https://gene.example:8443/tally"),
           taken("https://evil-gene.example/"), taken("https://gene.example.evil.example/"), taken("https://sub.gene.example/"), taken("about:blank"), taken(nil)],
          ["refused", "refused", "refused", "refused", "refused", "refused", "refused", "refused"])
    check("a frame inside the build's own page is refused", [taken("https://gene.example/tally", mainFrame: false)], ["refused"])
    check("a build that names no page answers nobody", [taken("https://gene.example/tally", door: PageDoor(own: nil))], ["refused"])
    check("a request that is not a request's shape is nothing", [String(door.take("words", from: own, mainFrame: true) == nil)], ["true"])
    let local = PageDoor(own: PageOrigin(URL(string: "http://127.0.0.1:6901/")))
    check("a build whose page is this Mac's: the same address by another name, or another port of it, is another origin",
          [taken("http://127.0.0.1:6901/x", door: local), taken("http://localhost:6901/", door: local), taken("http://127.0.0.1:6902/", door: local)],
          ["taken", "refused", "refused"])
}

// MARK: a page of another origin that names a scan's every field

do {
    let reader = StandInReader()
    NativeLibraries.shared.register(IDScannerAdapter(name: "id-reader", scanner: reader))
    let every = ["kind", "fullName", "dateOfBirth", "expirationDate", "isOver21", "isExpired", "licenseNumber", "sex", "postalCode",
                 "issuingState", "issueCode", "state", "paired"]
    let stream: [String: Any] = ["type": "native", "id": "s", "url": "native://id-reader/events", "listen": true, "keep": every]
    let start: [String: Any] = ["type": "native", "id": "r", "url": "native://id-reader/start-reading", "keep": [String]()]
    var handed = asks(stream, from: "https://other.example/") + asks(start, from: "https://other.example/")
    reader.press()
    check("a page of another origin that asks for a scan's stream, naming every field in keep, and starts the reading, is handed nothing: no state, no answer, no scan",
          handed, [])
    // the build's own page, with the same words
    var own: [String] = []
    if let taken = door.take(stream, from: PageOrigin(URL(string: "https://gene.example/tally")), mainFrame: true) {
        NativeLibraries.shared.handle(taken, answered: { _, value in own.append(fields(value)) }, failed: { _, error in own.append("error: " + error) })
    }
    reader.press()
    check("and its start started no reading: the build's own page, listening, is told the next scan as one nobody reads",
          own, ["kind=state paired=1 state=connected", "kind=unread"])
    handed = asks(start, from: "https://gene.example/tally")
    reader.press() // the stand-in's third event: a read that failed, with no holder
    reader.press() // its fourth: the second made-up person
    NativeLibraries.shared.stopAll()
    check("the build's own page, with the same words, is handed its start's answer and the scans, the four fields with them",
          [handed.first ?? "nothing", String(own.last?.contains("licenseNumber=TEST0000002") == true && own.last?.contains("fullName=Test Person Two") == true)],
          ["{}", "true"])
    check("a frame inside the build's own page that asks for the stream is handed nothing",
          asks(stream, from: "https://gene.example/tally", mainFrame: false), [])
    NativeLibraries.shared.stopAll()
}

// MARK: an answer is told only to the page that asked

do {
    var waiting = PageWaiting()
    let first = waiting.page
    waiting.wait("a link that opened the app", for: nil)
    waiting.wait("an answer for the first page", for: first)
    check("while the page that asked is held, its answer may be told", [String(waiting.isFor(first)), String(waiting.isFor(nil))], ["true", "true"])
    waiting.pageChanged()
    check("another page takes its place: the answer is nobody's, to tell now or later; what no page asked for still waits",
          [String(waiting.isFor(first)), String(waiting.isFor(waiting.page)), String(waiting.isFor(nil))] + waiting.take(),
          ["false", "true", "true", "a link that opened the app"])
    check("what was taken is not told twice", waiting.take(), [])
    waiting.wait("an answer for the second page", for: waiting.page)
    waiting.wait("a second link", for: nil)
    check("what waits for the page that is held is told in its order", waiting.take(), ["an answer for the second page", "a second link"])
}

// MARK: the phone's bridge passes every request through the door

do {
    let bridge = (try? String(contentsOfFile: "Shell/ShellBridge.swift", encoding: .utf8)) ?? ""
    let lines = bridge.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    let at = lines.firstIndex { $0.hasPrefix("func userContentController(") } ?? -1
    let first = at < 0 ? "" : lines[(at + 1)...].first { !$0.isEmpty && !$0.hasPrefix("//") } ?? ""
    check("the bridge is read", [String(at >= 0)], ["true"])
    check("the first thing the bridge does with a page's message is pass it through the door, with the frame's own origin and whether it is the main frame",
          [first], ["guard let body = door.take(message.body, from: Self.origin(of: message.frameInfo), mainFrame: message.frameInfo.isMainFrame),"])
    check("and it reads a message's body nowhere else", [String(bridge.components(separatedBy: "message.body").count - 1)], ["1"])
    check("the door's own page is the build's page, and nothing else",
          [String(bridge.contains("private lazy var door = PageDoor(own: PageOrigin(startURL))"))], ["true"])
    check("what the shell tells a page is told only while the page held is the build's own, and an answer only to the page that asked",
          ["guard waiting.isFor(page) else { return }", "guard loaded, let webView, door.isOwn(PageOrigin(webView.url)) else {",
           "if door.isOwn(PageOrigin(webView.url)) {", "waiting.pageChanged()"].filter { !bridge.contains($0) }, [])
    check("the bridge runs its words for a page in one place alone, behind those guards; the one other thing it runs in a page is the web view's own covered edges, which a page of any origin reads from the web view too",
          bridge.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.contains("evaluateJavaScript(") }.sorted(),
          ["if firstLoadAsked { webView.evaluateJavaScript(Self.said(edges) + CoveredEdges.readAgain) }",
           "waiting.take().forEach { webView.evaluateJavaScript($0) }", "webView.evaluateJavaScript(js)"])
    check("the bridge counts each page that takes another's place: when a page's first bytes are in, and when iOS ended a page's content",
          [String(bridge.components(separatedBy: "waiting.pageChanged()").count - 1),
           String(bridge.contains("func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {\n        waiting.pageChanged()\n    }")),
           String(bridge.contains("loaded = false\n        waiting.pageChanged() // what waited for the page that ended is nobody's"))], ["2", "true", "true"])
}

print("door: \(passed) passed, \(failed) failed")
if failed > 0 { exit(1) }

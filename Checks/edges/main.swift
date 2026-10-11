// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

// A check of the script that tells a page a resize when the edges the
// hardware covers change (Shell/CoveredEdges.swift), on this Mac: the
// script is run in a JavaScript engine against a document that only
// records, and the check says what the web view would say of the mark's
// size: scripts/check-edges.sh.

import Foundation
import JavaScriptCore

var passed = 0, failed = 0
func check(_ name: String, _ got: [String], _ want: [String]) {
    if got == want { passed += 1 } else { failed += 1; print("FAIL \(name):\n  got  \(got)\n  want \(want)") }
}

/// A page's world that only records: the events the window was told, the
/// observers made, what was put in the document; and the web view's own
/// word of the four edges, which the check sets.
let world = """
var events = [], observers = [], appended = [], errors = [];
var window = this;
window.dispatchEvent = function (e) { events.push(e.type); };
function Event(type) { this.type = type; }
function ResizeObserver(heard) { this.heard = heard; observers.push(this); }
ResizeObserver.prototype.observe = function (el, options) { this.el = el; this.options = options; };
var document = {
  createElement: function (tag) { return { tag: tag, attrs: {}, style: {}, setAttribute: function (k, v) { this.attrs[k] = v; } }; },
  documentElement: { appendChild: function (el) { appended.push(el); } }
};
// the web view's own word of the covered edges: what the mark's padding is
var webView = [0, 0, 0, 0];
function getComputedStyle(el) { return { paddingTop: webView[0] + "px", paddingRight: webView[1] + "px", paddingBottom: webView[2] + "px", paddingLeft: webView[3] + "px" }; }
// the web view says the edges (top, right, bottom, left), and the mark's size is seen to change or not
function told(top, right, bottom, left) { webView = [top, right, bottom, left]; observers[0].heard([{}]); }
"""

/// A fresh world with the script run in it: said is what the shell says
/// the edges are to this page as it starts, if it knows them.
func page(_ before: String = "", said: [Double]? = nil) -> JSContext {
    let context = JSContext()!
    context.exceptionHandler = { context, error in context?.evaluateScript("errors.push(1)"); print("the script failed: \(error?.toString() ?? "")") }
    context.evaluateScript(world)
    context.evaluateScript(before)
    context.evaluateScript(CoveredEdges.script(saidAtStart: said))
    return context
}
func said(_ context: JSContext, _ words: String) -> String { context.evaluateScript(words)?.toString() ?? "nothing" }

do {
    let p = page()
    check("the script runs, makes one observer of one mark, and puts the mark in the document",
          [said(p, "errors.length"), said(p, "observers.length"), said(p, "appended.length"), said(p, "appended[0] === observers[0].el"), said(p, "appended[0].tag")],
          ["0", "1", "1", "true", "div"])
    let style = said(p, "appended[0].style.cssText")
    check("the mark is padded by the web view's own four edges and by no number of the shell's, is not seen, takes no touch and is hidden from a reader of the screen",
          ["padding:env(safe-area-inset-top,0px) env(safe-area-inset-right,0px) env(safe-area-inset-bottom,0px) env(safe-area-inset-left,0px)",
           "visibility:hidden", "pointer-events:none", "position:fixed", "width:0;height:0"].filter { !style.contains($0) }
              + [said(p, "appended[0].attrs['aria-hidden']")], ["true"])
    check("its size is watched with its padding (the mark itself is nothing by nothing)", [said(p, "observers[0].options.box")], ["border-box"])
    check("making the mark tells the page nothing", [said(p, "events.length")], ["0"])
    _ = said(p, "told(0, 0, 0, 0)")
    check("the web view's first word of the mark, as the page starts with every edge at 0, is no change: nothing is told",
          [said(p, "events.length")], ["0"])
    _ = said(p, "told(62, 0, 34, 0)")
    check("the shell said nothing to this page as it started, and the covered edges are told a moment later: the window is told one resize, the event a page already takes to read its screen again",
          [said(p, "events.join(' ')")], ["resize"])
    _ = said(p, "told(62, 0, 34, 0)")
    check("a word that changes nothing tells nothing more", [said(p, "events.length")], ["1"])
    _ = said(p, "told(62, 0, 96, 0); told(0, 59, 21, 59); told(0, 59, 21, 0); told(0, 0, 0, 0)")
    check("each later change of the edges (a home bar, a phone turned, one side alone, none) is one resize", [said(p, "events.join(' ')")],
          ["resize resize resize resize resize"])
}

do {
    // the shell said the edges to this page as it started, through the hook
    let p = page(said: [62, 0, 34, 0])
    _ = said(p, "told(0, 0, 0, 0)")
    _ = said(p, "told(62, 0, 34, 0)")
    check("the shell said the edges to this page as it started: the web view's own first word of those same edges tells the page nothing it has not read, and is told by no resize",
          [said(p, "events.length"), said(p, "errors.length")], ["0", "0"])
    _ = said(p, "told(0, 59, 21, 59)")
    check("the next change is told", [said(p, "events.join(' ')")], ["resize"])
    _ = said(p, "told(62, 0, 34, 0)")
    check("and a change back to the edges said at the start is told too: only the first is left out", [said(p, "events.join(' ')")], ["resize resize"])
    let other = page(said: [62, 0, 34, 0])
    _ = said(other, "told(47, 0, 34, 0)")
    check("a first word that is not what the shell said is told: the page must read again", [said(other, "events.join(' ')")], ["resize"])
    let near = page(said: [47.333333333333336, 0, 34, 0])
    _ = said(near, "told(47.3333, 0, 34, 0)")
    check("the same edge said to a hair's difference by the two is the same edge", [said(near, "events.length")], ["0"])
    let none = page(said: [0, 0, 0, 0])
    _ = said(none, "told(0, 0, 0, 0); told(20, 0, 0, 0)")
    check("a screen the shell said covers nothing, then covered: told", [said(none, "events.join(' ')")], ["resize"])
}

do {
    // a page that starts with its edges already known (it was loaded again in a web view that knows them)
    let p = page("webView = [62, 0, 34, 0];")
    _ = said(p, "told(62, 0, 34, 0); told(62, 0, 34, 0)")
    check("a page that starts with its edges already told hears no resize for them", [said(p, "events.length")], ["0"])
    _ = said(p, "told(0, 0, 0, 0)")
    check("and is told when they change", [said(p, "events.join(' ')")], ["resize"])
    let none = page("ResizeObserver = undefined;")
    check("a web view with no such observer: the script does nothing, and fails nothing",
          [said(none, "errors.length"), said(none, "appended.length"), said(none, "events.length")], ["0", "0", "0"])
}

do {
    check("the event's script says no covered edge to the page: it sets none of its own and hands the page nothing but the event",
          ["inspoSafeArea", "postMessage", "webkit", "innerHeight", "screen."].filter(CoveredEdges.script(saidAtStart: [62, 0, 34, 0]).contains), [])
    check("what it is given of the shell's word is the four edges, never less than 0, or nothing",
          [CoveredEdges.script(saidAtStart: [62, -1, .nan, 0.5]).contains("var said = [62.0, 0.0, 0.0, 0.5];"),
           CoveredEdges.script(saidAtStart: nil).contains("var said = null;")].map(String.init), ["true", "true"])
}

// MARK: the web view's own covered edges, said to a page as it starts

do {
    // a page reads the hook as the real page does: the larger of the hook's word and its browser's, for each edge
    let reads = "function read(browser) { var host = window.inspoSafeArea || {}; return ['top', 'right', 'bottom', 'left'].map(function (e) { return Math.max(browser[e] || 0, parseFloat(host[e]) || 0); }).join(' '); }"
    let p = page(reads)
    check("before the shell has said anything a page reads what its browser says: 0 for every edge as it starts",
          [said(p, "read({})")], ["0 0 0 0"])
    _ = said(p, CoveredEdges.said(top: 62, right: 0, bottom: 34, left: 0))
    check("the shell's words say the four edges through the hook a page reads, and a page that starts reads them though its browser still says 0",
          [said(p, "JSON.stringify(window.inspoSafeArea)"), said(p, "read({})")], [#"{"top":62,"right":0,"bottom":34,"left":0}"#, "62 0 34 0"])
    check("when the browser has said them too the page reads the same: the two are one number", [said(p, "read({top: 62, bottom: 34})")], ["62 0 34 0"])
    _ = said(p, CoveredEdges.said(top: 0, right: 59, bottom: 21, left: 59) + CoveredEdges.readAgain)
    check("the edges change (a phone turned): the hook is said again whole, so it holds no edge the web view no longer has, and the page is told a resize",
          [said(p, "read({right: 59, bottom: 21, left: 59})"), said(p, "events.join(' ')")], ["0 59 21 59", "resize"])
    check("an edge is never said as less than 0 or as no number",
          [CoveredEdges.said(top: -4, right: .nan, bottom: .infinity, left: 0.5)],
          ["window.inspoSafeArea = { top: 0.0, right: 0.0, bottom: 0.0, left: 0.5 };"])
}

do {
    let bridge = (try? String(contentsOfFile: "Shell/ShellBridge.swift", encoding: .utf8)) ?? ""
    check("the phone's bridge adds the event's script to every page, as the page starts, in the page's main frame, in a world of the shell's own, and gives it the same edges it says through the hook",
          [String(bridge.contains("WKUserScript(source: CoveredEdges.script(saidAtStart: edges.map { [$0.top, $0.right, $0.bottom, $0.left] }),\n                         injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .defaultClient),"))], ["true"])
    check("and says the web view's own covered edges to a page as it starts, once they are known, in the page's own world, where the page reads them",
          [String(bridge.contains("scripts.append(WKUserScript(source: Self.said(edges), injectionTime: .atDocumentStart, forMainFrameOnly: true))")),
           String(bridge.contains("CoveredEdges.said(top: edges.top, right: edges.right, bottom: edges.bottom, left: edges.left)"))], ["true", "true"])
    check("the edges are the web view's own safe area and no other number: nothing in the bridge writes one",
          [String(bridge.contains("edgesTold?(safeAreaInsets)")), String(bridge.components(separatedBy: "CoveredEdges.said(").count - 1),
           String(bridge.components(separatedBy: "inspoSafeArea").count - 1)], ["true", "1", "0"])
    check("when they change, every page that starts is told the new ones, the page shown is told them with a resize, and the first page is loaded once they are known",
          ["scripts.removeAllUserScripts()\n        Self.pageScripts(edges: edges).forEach(scripts.addUserScript)",
           "if firstLoadAsked { webView.evaluateJavaScript(Self.said(edges) + CoveredEdges.readAgain) }\n        firstLoad()",
           "view.edgesTold = { [weak self] edges in self?.coveredEdges(edges) }",
           "guard window != nil, bounds.width > 0, safeAreaInsets != told else { return }"].filter { !bridge.contains($0) }, [])
    check("the page is loaded in three places and no other: the first page once the edges are known, a page that did not load again, and a page whose content iOS ended",
          bridge.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.contains("loadPage()") && !$0.hasPrefix("private func") },
          ["private lazy var again = LoadAgain(load: { [weak self] in self?.loadPage() })", "loadPage()", "loadPage()"])
    check("a web view laid out in no window loads its page all the same, a second on, and the first page is loaded once",
          ["DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.firstLoad() }",
           "guard !firstLoadAsked else { return }\n        firstLoadAsked = true\n        loadPage()"].filter { !bridge.contains($0) }, [])
}

print("edges: \(passed) passed, \(failed) failed")
if failed > 0 { exit(1) }

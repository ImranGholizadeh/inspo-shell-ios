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
/// observers made, what was put in the document.
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
// the web view's word of the mark's size: its two sides' edges together, and its top and bottom's
function told(across, down) { observers[0].heard([{ borderBoxSize: [{ inlineSize: across, blockSize: down }] }]); }
"""

/// A fresh world with the script run in it.
func page(_ before: String = "") -> JSContext {
    let context = JSContext()!
    context.exceptionHandler = { context, error in context?.evaluateScript("errors.push(1)"); print("the script failed: \(error?.toString() ?? "")") }
    context.evaluateScript(world)
    context.evaluateScript(before)
    context.evaluateScript(CoveredEdges.script)
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
    _ = said(p, "told(0, 0)")
    check("the web view's first word of the mark, as the page starts with every edge at 0, is no change: nothing is told",
          [said(p, "events.length")], ["0"])
    _ = said(p, "told(0, 62)")
    check("the covered top is told a moment later: the window is told one resize, the event a page already takes to read its screen again",
          [said(p, "events.join(' ')")], ["resize"])
    _ = said(p, "told(0, 62)")
    check("a word that changes nothing tells nothing more", [said(p, "events.length")], ["1"])
    _ = said(p, "told(0, 96); told(47, 21); told(0, 0)")
    check("each later change of the edges (a home bar, a phone turned, none) is one resize", [said(p, "events.join(' ')")],
          ["resize resize resize resize"])
}

do {
    // a page that starts with its edges already known (it was loaded again in a web view that knows them)
    let p = page()
    _ = said(p, "told(0, 62); told(0, 62)")
    check("a page that starts with its edges already told hears no resize for them", [said(p, "events.length")], ["0"])
    let none = page("ResizeObserver = undefined;")
    check("a web view with no such observer: the script does nothing, and fails nothing",
          [said(none, "errors.length"), said(none, "appended.length"), said(none, "events.length")], ["0", "0", "0"])
}

do {
    check("the script says no number of the shell's: it sets no covered edge of its own and hands the page nothing but the event",
          ["inspoSafeArea", "postMessage", "webkit", "innerHeight", "screen."].filter(CoveredEdges.script.contains), [])
    let bridge = (try? String(contentsOfFile: "Shell/ShellBridge.swift", encoding: .utf8)) ?? ""
    check("the phone's bridge adds it to every page, as the page starts, in the page's main frame, in a world of the shell's own",
          [String(bridge.contains("source: CoveredEdges.script, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .defaultClient))"))], ["true"])
    check("and still loads the page as it did, and tells the page no covered edge itself",
          ["loadPage()\n        return view", "contentInsetAdjustmentBehavior = .never"].filter { !bridge.contains($0) } + ["inspoSafeArea"].filter(bridge.contains), [])
}

print("edges: \(passed) passed, \(failed) failed")
if failed > 0 { exit(1) }

// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

import Foundation

// The edges of the screen the hardware covers (the status bar and its
// island, the home bar), and when a page is told of them. A page reads
// them from the web view itself (env(safe-area-inset-top) and the three
// others) and places itself by them; the shell lays the web view over the
// whole screen and tells the page no number of its own.
//
// A page that has just started reads 0 for every edge. The web view tells
// a new page's content its covered edges only with the first word of what
// it shows, which follows the page's first drawing: about a twentieth of a
// second after the page's script began, on a simulator. It makes no event
// of it: the window's size has not changed, so no resize is told, and a
// page that read the edges as it started keeps 0 and draws under the
// status bar. Starting the load later does not help: with the load held
// until the web view was in its window and knew its covered top, the page
// still read 0 as it started, three starts of three.
//
// So the shell does two things.
//
// It makes the event the web view leaves out (script, below): a script it
// adds to every page keeps one hidden mark padded by the web view's own
// four edges, and when the mark's size changes (the edges have been told,
// or have changed) it tells the window a resize, the event a page already
// takes to read its screen again. By this the shell says no number: the
// page reads the edges itself.
//
// And, because a page told so a moment after it has drawn is not drawn
// again by today's engine (a screen whose size is the same and whose
// covered edges differ draws nothing again), it says the web view's own
// covered edges to a page as the page starts (said, below), through the
// hook a page already reads for an edge its browser does not know of:
// window.inspoSafeArea, of which the page takes the larger of the hook's
// word and the browser's for each edge. The numbers are the web view's own
// (its safe area, in points, which are a page's px): the same the page's
// browser tells it a twentieth of a second later. The shell says them
// again, with a resize, whenever they change, so the hook never holds an
// edge the web view no longer has; and the first page is loaded when the
// web view is first laid out in its window, when its edges are known.

enum CoveredEdges {
    /// The script, run at the start of every page, in a world of the
    /// shell's own: the page's own script sees the mark in its document
    /// and the event, and nothing else of it.
    static let script = """
    (function () {
      if (typeof ResizeObserver !== "function") return;
      var mark = document.createElement("div");
      mark.setAttribute("aria-hidden", "true");
      mark.style.cssText = "position:fixed;top:0;left:0;width:0;height:0;visibility:hidden;pointer-events:none;" +
        "padding:env(safe-area-inset-top,0px) env(safe-area-inset-right,0px) env(safe-area-inset-bottom,0px) env(safe-area-inset-left,0px)";
      var seen = null;
      new ResizeObserver(function (entries) {
        var box = entries[entries.length - 1].borderBoxSize, size = box && box[0] ? box[0].inlineSize + "x" + box[0].blockSize : "";
        var first = seen === null, changed = size !== seen;
        seen = size;
        if (!first && changed) window.dispatchEvent(new Event("resize"));
      }).observe(mark, { box: "border-box" });
      document.documentElement.appendChild(mark);
    })();
    """

    /// The words that say the web view's covered edges to a page, through
    /// the hook a page reads: each edge in points, none less than 0.
    static func said(top: Double, right: Double, bottom: Double, left: Double) -> String {
        func edge(_ points: Double) -> String { String(points.isFinite && points > 0 ? points : 0) }
        return "window.inspoSafeArea = { top: \(edge(top)), right: \(edge(right)), bottom: \(edge(bottom)), left: \(edge(left)) };"
    }

    /// The words that have a page read its screen again.
    static let readAgain = "window.dispatchEvent(new Event(\"resize\"));"
}

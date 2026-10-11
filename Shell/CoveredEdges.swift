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
// So the shell makes the event the web view leaves out, and nothing else:
// a script it adds to every page keeps one hidden mark padded by the web
// view's own four edges, and when the mark's size changes (the edges have
// been told, or have changed) it tells the window a resize, the event a
// page already takes to read its screen again. The page reads the edges
// itself, from the web view, as before: the shell says no number, so what
// the page is told cannot differ from what is so.

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
}

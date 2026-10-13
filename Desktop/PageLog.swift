// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

import Foundation

// What a launch keeps for a later read (owner, 2026-10-13: "have you review
// the logs"): the app's own lines (app.log) and the page's own console and
// errors (page.log), in the launch's folder. The page's part is a script set
// before the page's own: it hands on what the page says to its console, an
// error nobody caught and a promise nobody answered, and nothing else. It
// listens to no field and no key, so no word a person types is kept.
enum PageLog {
    static let handler = "inspoLog"

    static let script = """
    (function () {
      var door = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(handler);
      if (!door || window.inspoLogSet) return;
      window.inspoLogSet = true;
      function text(v) {
        if (typeof v === "string") return v;
        if (v instanceof Error) return v.name + ": " + v.message + (v.stack ? "\\n" + v.stack : "");
        try { var s = JSON.stringify(v); return s === undefined ? String(v) : s; } catch (e) { return String(v); }
      }
      function say(level, parts) {
        try { door.postMessage({ level: level, text: parts.map(text).join(" ").slice(0, 4000) }); } catch (e) {}
      }
      ["log", "info", "warn", "error", "debug"].forEach(function (level) {
        var own = console[level];
        console[level] = function () {
          say(level, Array.prototype.slice.call(arguments));
          return own.apply(console, arguments);
        };
      });
      window.addEventListener("error", function (e) {
        say("uncaught", [e.message || "error", (e.filename || "") + ":" + (e.lineno || 0) + ":" + (e.colno || 0), e.error && e.error.stack || ""]);
      });
      window.addEventListener("unhandledrejection", function (e) {
        say("unanswered", [e.reason]);
      });
    })();
    """

    /// One line of the page's, as the file keeps it; nil for what is no such message.
    static func line(_ body: Any) -> String? {
        guard let body = body as? [String: Any], let level = body["level"] as? String, let text = body["text"] as? String else { return nil }
        return "\(level): \(text)"
    }
}

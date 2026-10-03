// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

// A check of Shell/HandOver.swift on this Mac, with a share sheet and a
// clipboard that only record what they were given (no phone, no
// simulator): scripts/check-share.sh.

import Foundation

/// A sheet that records what it was opened with, reads a file it is given
/// while it is open, and closes when the check says.
final class RecordedSheet: ShareSheet {
    var opened: [String] = []
    var opens = true
    var close: (() -> Void)?
    func open(_ items: [SharedItem], closed: @escaping () -> Void) -> Bool {
        opened.append(items.map { item in
            switch item {
            case .text(let text): return "text \(text)"
            case .link(let url): return "link \(url.absoluteString)"
            case .file(let url): return "file \(url.lastPathComponent) = \((try? String(contentsOf: url, encoding: .utf8)) ?? "unreadable")"
            }
        }.joined(separator: " | "))
        guard opens else { return false }
        close = closed
        return true
    }
}

final class RecordedClipboard: Clipboard {
    var held: [String] = []
    func hold(_ text: String) { held.append(text) }
}

var passed = 0, failed = 0
func check(_ name: String, _ got: [String], _ want: [String]) {
    if got == want { passed += 1 } else { failed += 1; print("FAIL \(name):\n  got  \(got)\n  want \(want)") }
}

/// A bench: the hand-over with a recorded sheet and clipboard, a folder of
/// its own, and every answer it gave, in order.
final class Bench {
    let over = HandOver()
    let sheet = RecordedSheet()
    let clipboard = RecordedClipboard()
    var said: [String] = []
    init(sheet has: Bool = true, clipboard holds: Bool = true) {
        over.folder = FileManager.default.temporaryDirectory.appendingPathComponent("check-share-\(UUID().uuidString)", isDirectory: true)
        if has { over.sheet = { [sheet] in sheet } }
        if holds { over.clipboard = { [clipboard] in clipboard } }
    }
    func share(_ body: [String: Any], as name: String = "share") {
        over.share(body, answered: { self.said.append("\(name) answered") }, failed: { self.said.append("\(name) failed: \($0)") })
    }
    func copy(_ body: [String: Any]) {
        over.copy(body, answered: { self.said.append("answered") }, failed: { self.said.append("failed: \($0)") })
    }
    /// The files under the shared folder, as folder-less names.
    var files: [String] {
        let all = FileManager.default.enumerator(at: over.folder, includingPropertiesForKeys: [.isRegularFileKey])?.compactMap { $0 as? URL } ?? []
        return all.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }.map(\.lastPathComponent).sorted()
    }
    deinit { try? FileManager.default.removeItem(at: over.folder) }
}

let csv: [String: Any] = ["name": "Test venue 2026-09-29.csv", "mime": "text/csv", "text": "venue,in\nTest venue,12\n"]

do {
    let bench = Bench()
    bench.share(["type": "share", "id": "f1", "file": csv])
    check("a file is written under its name and the sheet opens with it", bench.sheet.opened, ["file Test venue 2026-09-29.csv = venue,in\nTest venue,12\n"])
    check("nothing is answered while the sheet is open", bench.said + bench.files, ["Test venue 2026-09-29.csv"])
    bench.sheet.close?()
    check("the sheet closed: answered", bench.said, ["share answered"])
    check("and the file is removed", bench.files, [])
    bench.sheet.close?()
    check("a sheet closes once", bench.said, ["share answered"])
}

do {
    let bench = Bench()
    bench.share(["type": "share", "id": "w1", "text": "Last night: 12 in", "url": "https://example.test/night?date=2026-09-29"])
    bench.sheet.close?()
    bench.share(["type": "share", "id": "w2", "text": "Only words"])
    bench.sheet.close?()
    bench.share(["type": "share", "id": "w3", "url": "http://example.test/"])
    bench.sheet.close?()
    check("a text and a link, a text alone, a link alone", bench.sheet.opened,
          ["text Last night: 12 in | link https://example.test/night?date=2026-09-29", "text Only words", "link http://example.test/"])
    check("each answered when its sheet closed", bench.said, ["share answered", "share answered", "share answered"])
    check("no file is written for words", bench.files, [])
}

do {
    let bench = Bench()
    bench.share(["type": "share", "id": "a", "file": csv], as: "first")
    bench.share(["type": "share", "id": "b", "text": "second"], as: "second")
    check("a sheet already open is not opened over", bench.said + bench.sheet.opened, ["second failed: a share sheet is already open", "file Test venue 2026-09-29.csv = venue,in\nTest venue,12\n"])
    check("and the first share's file stays for its sheet", bench.files, ["Test venue 2026-09-29.csv"])
    bench.sheet.close?()
    bench.share(["type": "share", "id": "c", "text": "third"], as: "third")
    bench.sheet.close?()
    check("once it closed the next opens", bench.said, ["second failed: a share sheet is already open", "first answered", "third answered"])
}

do {
    // what an earlier share left (the app ended with its sheet open) goes when the next begins
    let bench = Bench()
    let left = bench.over.folder.appendingPathComponent("earlier", isDirectory: true)
    try? FileManager.default.createDirectory(at: left, withIntermediateDirectories: true)
    try? Data("old".utf8).write(to: left.appendingPathComponent("old.csv"))
    check("a file an earlier share left", bench.files, ["old.csv"])
    bench.share(["type": "share", "id": "n", "file": csv])
    check("is removed when the next share begins", bench.files, ["Test venue 2026-09-29.csv"])
    bench.sheet.close?()
}

for (name, body, why) in [
    ("nothing", ["type": "share", "id": "x"] as [String: Any], "a share is given a text, a link or a file"),
    ("a file and a text", ["type": "share", "id": "x", "text": "hello", "file": csv], "a share is a file, or a text and a link, not both"),
    ("a file and a link", ["type": "share", "id": "x", "url": "https://example.test", "file": csv], "a share is a file, or a text and a link, not both"),
    ("a link to the phone's own file", ["type": "share", "id": "x", "url": "file:///etc/passwd"], "a share's link is an http or https address"),
    ("a link that is a script", ["type": "share", "id": "x", "url": "javascript:alert(1)"], "a share's link is an http or https address"),
    ("a link to a file by a host's name", ["type": "share", "id": "x", "url": "file://localhost/etc/passwd"], "a share's link is an http or https address"),
    ("a link of another kind", ["type": "share", "id": "x", "url": "ftp://example.test/a"], "a share's link is an http or https address"),
    ("a link with no host", ["type": "share", "id": "x", "url": "https://"], "a share's link is an http or https address"),
    ("a link with a space", ["type": "share", "id": "x", "url": "https://example.test/a b"], "a share's link is an http or https address"),
    ("a file above its folder", ["type": "share", "id": "x", "file": ["name": "../out.csv", "mime": "text/csv", "text": "1"]], "a file's name is a plain file name"),
    ("a file in a folder", ["type": "share", "id": "x", "file": ["name": "a/b.csv", "mime": "text/csv", "text": "1"]], "a file's name is a plain file name"),
    ("a file named ..", ["type": "share", "id": "x", "file": ["name": "..", "mime": "text/csv", "text": "1"]], "a file's name is a plain file name"),
    ("a file with no name", ["type": "share", "id": "x", "file": ["mime": "text/csv", "text": "1"]], "a file's name is a plain file name"),
    ("a file that is not an object", ["type": "share", "id": "x", "file": "a.csv"], "a file's name is a plain file name"),
    ("a file with nothing in it", ["type": "share", "id": "x", "file": ["name": "a.csv", "mime": "text/csv", "text": ""]], "a file with nothing in it is not shared"),
    ("a file too large", ["type": "share", "id": "x", "file": ["name": "a.csv", "mime": "text/csv", "text": String(repeating: "a", count: HandOver.limit + 1)]], "a file is at most 1000000 bytes"),
    ("a text too large", ["type": "share", "id": "x", "text": String(repeating: "a", count: HandOver.limit + 1)], "a text is at most 1000000 bytes"),
] {
    let bench = Bench()
    bench.share(body)
    check("\(name) is not shared", bench.said + bench.sheet.opened + bench.files, ["share failed: \(why)"])
}

do {
    let bench = Bench()
    bench.share(["type": "share", "id": "x", "file": ["name": "a.csv", "mime": "text/csv", "text": String(repeating: "a", count: HandOver.limit)]])
    check("a file of exactly the limit is shared", [String(bench.sheet.opened.count)] + bench.said, ["1"])
    bench.sheet.close?()
}

do {
    let bench = Bench(sheet: false)
    bench.share(["type": "share", "id": "x", "file": csv])
    check("nothing to show a sheet on: failed, and no file is left", bench.said + bench.files, ["share failed: nothing here can show a share sheet"])
}

do {
    let bench = Bench()
    bench.sheet.opens = false
    bench.share(["type": "share", "id": "x", "file": csv])
    check("a sheet that would not open: failed, and no file is left", bench.said + bench.files, ["share failed: the share sheet could not be opened"])
    bench.sheet.opens = true
    bench.share(["type": "share", "id": "y", "text": "again"])
    bench.sheet.close?()
    check("and the next share opens", bench.said, ["share failed: the share sheet could not be opened", "share answered"])
}

do {
    let bench = Bench()
    bench.copy(["type": "clipboard", "id": "c1", "text": "4821"])
    check("the clipboard holds the text, and is answered", bench.clipboard.held + bench.said, ["4821", "answered"])
    bench.copy(["type": "clipboard", "id": "c2"])
    bench.copy(["type": "clipboard", "id": "c3", "text": ""])
    bench.copy(["type": "clipboard", "id": "c4", "text": String(repeating: "a", count: HandOver.limit + 1)])
    check("no text, an empty text and one too large are not held", bench.clipboard.held + Array(bench.said.dropFirst()),
          ["4821", "failed: a clipboard is given a text", "failed: a clipboard is given a text", "failed: a text is at most 1000000 bytes"])
    let none = Bench(clipboard: false)
    none.copy(["type": "clipboard", "id": "c5", "text": "4821"])
    check("no clipboard: failed", none.said, ["failed: no clipboard here"])
}

print("share: \(passed) passed, \(failed) failed")
if failed > 0 { exit(1) }

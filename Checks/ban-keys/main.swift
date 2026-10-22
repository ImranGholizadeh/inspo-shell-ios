// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

// A check of the phone's saved ban list (Shell/BanKeys.swift), native://ban-keys,
// on this Mac with no phone and no simulator: replace (in pages), put, lift
// and match; the newest row of a key and a state wins; a row of one eid is
// held once; match always answers, with no file, a corrupt file or bad
// words; the list outlives a restart; only the five fields are kept; the
// file is kept as the phone needs it. scripts/check-ban-keys.sh.

import Foundation

var passed = 0, failed = 0
func check(_ name: String, _ got: String, _ want: String) {
    if got == want { passed += 1 } else { failed += 1; print("FAIL \(name):\n  got  \(got)\n  want \(want)") }
}

func fields(_ value: [String: Any]) -> String {
    value.isEmpty ? "{}" : value.keys.sorted().map { "\($0)=\(value[$0]!)" }.joined(separator: " ")
}

/// What one call answered, and how long it took (every call here answers
/// before it returns, so the engine's native timeout is never reached).
func ask(_ library: BanKeysLibrary, _ call: String, _ data: Any?) -> (text: String, seconds: Double) {
    var said = "NO ANSWER"
    let start = Date()
    library.call(call, data: data) { result in
        switch result {
        case .success(let value): said = fields(value)
        case .failure(let err): said = "ERROR \(err.message)"
        }
    }
    return (said, Date().timeIntervalSince(start))
}
func say(_ library: BanKeysLibrary, _ call: String, _ data: Any?) -> String { ask(library, call, data).text }

func row(_ eid: String, _ idKey: String, _ state: String = "NY", _ reason: String = "fight", _ at: Int = 1000) -> [String: Any] {
    ["eid": eid, "idKey": idKey, "issuingState": state, "reason": reason, "createdAtMs": at]
}
func match(_ library: BanKeysLibrary, _ idKey: String, _ state: String = "NY") -> String {
    say(library, "match", ["idKey": idKey, "issuingState": state])
}

let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ban-keys-check-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: folder) }
var count = 0
func fresh() -> URL { count += 1; return folder.appendingPathComponent("list\(count)/bans.json") }

// MARK: with nothing held

do {
    let file = fresh()
    let lib = BanKeysLibrary(file: file)
    check("a library has its name", lib.name, "ban-keys")
    check("match with no file is a miss", match(lib, "k1"), "createdAtMs=0 hit=0 reason=")
    check("lift with nothing held is fine", say(lib, "lift", ["eid": "nobody"]), "{}")
}

// MARK: put, match, lift

do {
    let lib = BanKeysLibrary(file: fresh())
    check("put answers {}", say(lib, "put", row("e1", "k1", "NY", "fight", 5)), "{}")
    check("match finds it", match(lib, "k1"), "createdAtMs=5 hit=1 reason=fight")
    check("the state must match too", match(lib, "k1", "NJ"), "createdAtMs=0 hit=0 reason=")
    check("the key must match too", match(lib, "k2"), "createdAtMs=0 hit=0 reason=")
    check("same eid replaces (one row)", say(lib, "put", row("e1", "k1", "NY", "theft", 9)), "{}")
    check("and the match is the replacement", match(lib, "k1"), "createdAtMs=9 hit=1 reason=theft")
    _ = say(lib, "put", row("e2", "k1", "NY", "older", 3))
    check("the newest by createdAtMs wins, not the last put", match(lib, "k1"), "createdAtMs=9 hit=1 reason=theft")
    _ = say(lib, "put", row("e3", "k1", "NY", "newest", 12))
    check("a newer row wins", match(lib, "k1"), "createdAtMs=12 hit=1 reason=newest")
    _ = say(lib, "put", row("e4", "k1", "NJ", "other state", 99))
    check("another state's newer row does not win", match(lib, "k1"), "createdAtMs=12 hit=1 reason=newest")
    check("lift answers {}", say(lib, "lift", ["eid": "e3"]), "{}")
    check("after a lift the next newest answers", match(lib, "k1"), "createdAtMs=9 hit=1 reason=theft")
    _ = say(lib, "lift", ["eid": "e1"])
    _ = say(lib, "lift", ["eid": "e2"])
    check("all lifted is a miss", match(lib, "k1"), "createdAtMs=0 hit=0 reason=")
    check("the other state's row is still held", match(lib, "k1", "NJ"), "createdAtMs=99 hit=1 reason=other state")
    check("a lift of an unknown eid is {}", say(lib, "lift", ["eid": "zzz"]), "{}")
}

// MARK: replace, in pages

do {
    let lib = BanKeysLibrary(file: fresh())
    _ = say(lib, "put", row("old", "kold"))
    check("replace with no page drops the list and keeps these", say(lib, "replace", ["keys": [row("a", "ka"), row("b", "kb")]]), "n=2")
    check("the old row is gone", match(lib, "kold"), "createdAtMs=0 hit=0 reason=")
    check("page 0 is the same as none", say(lib, "replace", ["keys": [row("c", "kc")], "page": 0]), "n=1")
    check("page 0 dropped the earlier rows", match(lib, "ka"), "createdAtMs=0 hit=0 reason=")
    check("page 1 adds", say(lib, "replace", ["keys": [row("d", "kd"), row("e", "ke")], "page": 1]), "n=3")
    check("page 2 adds", say(lib, "replace", ["keys": [row("f", "kf")], "page": 2]), "n=4")
    check("and the first page's row is still held", match(lib, "kc"), "createdAtMs=1000 hit=1 reason=fight")
    check("a page's row of a held eid replaces it", say(lib, "replace", ["keys": [row("c", "kc", "NY", "changed", 2000)], "page": 3]), "n=4")
    check("and it is the replacement", match(lib, "kc"), "createdAtMs=2000 hit=1 reason=changed")
    check("an empty list at page 0 empties the list", say(lib, "replace", ["keys": [] as [Any]]), "n=0")
    check("and match misses", match(lib, "kc"), "createdAtMs=0 hit=0 reason=")
    check("a page 1 of an empty list adds nothing", say(lib, "replace", ["keys": [] as [Any], "page": 1]), "n=0")
}

// MARK: bad words

do {
    let lib = BanKeysLibrary(file: fresh())
    _ = say(lib, "put", row("e1", "k1"))
    check("put with no eid is an error", say(lib, "put", ["idKey": "k", "issuingState": "NY", "reason": "r", "createdAtMs": 1]), "ERROR put: needs eid, idKey, issuingState, reason and createdAtMs")
    check("put with a number for a key is an error", say(lib, "put", ["eid": "x", "idKey": 5, "issuingState": "NY", "reason": "r", "createdAtMs": 1]), "ERROR put: needs eid, idKey, issuingState, reason and createdAtMs")
    check("put with no time is an error", say(lib, "put", ["eid": "x", "idKey": "k", "issuingState": "NY", "reason": "r"]), "ERROR put: needs eid, idKey, issuingState, reason and createdAtMs")
    check("put with an empty key is an error", say(lib, "put", row("x", "")), "ERROR put: needs eid, idKey, issuingState, reason and createdAtMs")
    check("put with nothing is an error", say(lib, "put", nil), "ERROR put: needs eid, idKey, issuingState, reason and createdAtMs")
    check("lift with no eid is an error", say(lib, "lift", [:]), "ERROR lift: needs eid")
    check("replace with no keys is an error", say(lib, "replace", [:]), "ERROR replace: needs keys")
    check("replace with a bad row is an error and changes nothing", say(lib, "replace", ["keys": [row("a", "ka"), ["eid": "b"]]]), "ERROR replace: needs keys")
    check("the list is as it was", match(lib, "k1"), "createdAtMs=1000 hit=1 reason=fight")
    check("a page that is not a whole number is an error", say(lib, "replace", ["keys": [row("a", "ka")], "page": "x"]), "ERROR replace: page is a whole number")
    check("the list is still as it was", match(lib, "k1"), "createdAtMs=1000 hit=1 reason=fight")
    check("an unknown call is an error", say(lib, "frobnicate", nil), "ERROR no call frobnicate")
    for (name, data) in [("no words", nil), ("a text", "k1"), ("no state", ["idKey": "k1"]), ("a number key", ["idKey": 1, "issuingState": "NY"]),
                         ("an empty key", ["idKey": "", "issuingState": "NY"])] as [(String, Any?)] {
        let answered = ask(lib, "match", data)
        check("match with \(name) answers a miss", answered.text, "createdAtMs=0 hit=0 reason=")
        check("and answers fast (\(name))", String(answered.seconds < 0.5), "true")
    }
}

// MARK: a restart, a corrupt file, an unreadable one

do {
    let file = fresh()
    var lib = BanKeysLibrary(file: file)
    _ = say(lib, "replace", ["keys": [row("a", "ka", "NY", "fight", 7), row("b", "kb", "NJ", "theft", 8)]])
    _ = say(lib, "put", row("c", "kc", "CA", "noise", 9))
    _ = say(lib, "lift", ["eid": "b"])
    lib = BanKeysLibrary(file: file) // the phone restarted
    check("after a restart a held row still matches", match(lib, "ka"), "createdAtMs=7 hit=1 reason=fight")
    check("a row put still matches", match(lib, "kc", "CA"), "createdAtMs=9 hit=1 reason=noise")
    check("a row lifted is still lifted", match(lib, "kb", "NJ"), "createdAtMs=0 hit=0 reason=")
    check("a page added after a restart adds", say(lib, "replace", ["keys": [row("d", "kd")], "page": 1]), "n=3")

    try? Data("{ not json".utf8).write(to: file)
    lib = BanKeysLibrary(file: file)
    let corrupt = ask(lib, "match", ["idKey": "ka", "issuingState": "NY"])
    check("a corrupt file is a miss", corrupt.text, "createdAtMs=0 hit=0 reason=")
    check("and a fast one", String(corrupt.seconds < 0.5), "true")
    check("a put on a corrupt file starts the list again", say(lib, "put", row("z", "kz", "NY", "fresh", 3)), "{}")
    lib = BanKeysLibrary(file: file)
    check("and it is kept", match(lib, "kz"), "createdAtMs=3 hit=1 reason=fresh")

    try? Data("[1,2,3]".utf8).write(to: file) // json, but not the list
    lib = BanKeysLibrary(file: file)
    check("a file of another shape is a miss", match(lib, "ka"), "createdAtMs=0 hit=0 reason=")

    // a place that cannot be read or written: a folder where the file should be
    let blocked = fresh()
    try? FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
    lib = BanKeysLibrary(file: blocked)
    check("an unreadable file is a miss", match(lib, "ka"), "createdAtMs=0 hit=0 reason=")
    check("a put that cannot be kept is an error, not a silence", String(say(lib, "put", row("q", "kq")).hasPrefix("ERROR could not keep")), "true")
}

// MARK: only the five fields, and the file as the phone needs it

do {
    let file = fresh()
    let lib = BanKeysLibrary(file: file)
    var extra = row("x", "kx", "NY", "fight", 4)
    extra["name"] = "Pat Doe"; extra["photo"] = "data:image/png;base64,AAAA"; extra["note"] = "rude"
    _ = say(lib, "put", extra)
    _ = say(lib, "replace", ["keys": [extra], "page": 1, "name": "Pat Doe"])
    let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    check("nothing but the five fields is in the file", String(!text.contains("Pat") && !text.contains("photo") && !text.contains("rude") && !text.contains("AAAA")), "true")
    check("the five fields are", String(["eid", "idKey", "issuingState", "reason", "createdAtMs"].allSatisfy { text.contains($0) }), "true")
    check("match answers only hit, reason and createdAtMs", match(lib, "kx"), "createdAtMs=4 hit=1 reason=fight")
    let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
    #if os(iOS)
    check("the file is protected until the first unlock", String(describing: attributes?[.protectionKey] as? FileProtectionType), "Optional(NSFileProtectionCompleteUntilFirstUserAuthentication)")
    #endif
    let values = try? file.resourceValues(forKeys: [.isExcludedFromBackupKey])
    check("the file is kept out of backups", String(values?.isExcludedFromBackup ?? false), "true")
    let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)) ?? []
    check("an atomic write leaves no other file", leftovers.sorted().joined(separator: ","), "bans.json")
}

// MARK: a long list, and speed

do {
    let lib = BanKeysLibrary(file: fresh())
    for page in 0..<50 {
        let rows = (0..<100).map { row("e\(page * 100 + $0)", "key\(page * 100 + $0)") }
        _ = say(lib, "replace", ["keys": rows, "page": page])
    }
    check("5000 rows are held", say(lib, "replace", ["keys": [] as [Any], "page": 99]), "n=5000")
    let answered = ask(lib, "match", ["idKey": "key4999", "issuingState": "NY"])
    check("the last of 5000 matches", answered.text, "createdAtMs=1000 hit=1 reason=fight")
    check("fast", String(answered.seconds < 0.05), "true")
}

print("ban-keys: \(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)

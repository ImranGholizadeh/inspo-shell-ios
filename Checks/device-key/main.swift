// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

// A check of Shell/DeviceKey.swift on this Mac, with no phone and no
// simulator: the shell keeps the first key the page tells it and never
// another, says it only to a page of the build's own origin, keeps it over
// a reopen and over the web view's storage lost, and forgets it at the first
// start of a new install: scripts/check-device-key.sh. The Keychain itself
// is the phone's; a box stands in for it here.

import Foundation

var passed = 0, failed = 0
func check(_ name: String, _ got: String?, _ want: String?) {
    if got == want { passed += 1 } else { failed += 1; print("FAIL \(name):\n  got  \(got ?? "nil")\n  want \(want ?? "nil")") }
}

/// The Keychain's stand-in: what it holds outlives every DeviceKeyKept, as
/// the Keychain outlives an app's close.
final class Box: DeviceKeyPlace {
    var held: String?
    var refuses = false
    func read() -> String? { held }
    func write(_ key: String) -> Bool { if refuses { return false }; held = key; return true }
    func remove() { held = nil }
}
/// The app's defaults: gone with the app.
final class Marks: InstallMarks {
    var marked = false
    func mark() { marked = true }
}

let key = "AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_abcd" // 42 characters, as the page's 256 bits are
let other = "ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ"
let own = PageOrigin(URL(string: "https://example.web.app/door"))

// a phone that gains this shell: the page's own key is the one kept
let box = Box(), marks = Marks()
var shell = DeviceKeyKept(place: box, marks: marks)
check("a shell that keeps nothing says nothing", shell.script(own: own), nil)
check("the page's key is kept when the shell keeps none", String(shell.told(key)), "true")
check("the key kept is the page's", box.held, key)
check("the script says it to the build's own origin only",
      shell.script(own: own), #"(function(p){if(location.origin===p[0]){window.inspoShell=window.inspoShell||{};window.inspoShell.deviceKey=p[1]}})(["https:\/\/example.web.app","\#(key)"]);"#)
check("a key told again changes nothing", String(shell.told(other)), "false")
check("a key kept is never replaced", box.held, key)

// the app closed and opened again: the same key, whatever the web view kept
shell = DeviceKeyKept(place: box, marks: marks)
check("after a reopen the key is the one kept", shell.key, key)
check("after a reopen the page's other key is not taken", String(shell.told(other)), "false")
check("and the kept key is said", shell.key, key)

// the app deleted and installed again: its defaults are new, the Keychain is not
shell = DeviceKeyKept(place: box, marks: Marks())
check("a new install keeps nothing of the one before", shell.key, nil)
check("and the Keychain is wiped", box.held, nil)
check("its page's key is kept", String(shell.told(other)), "true")
check("as the new install's", box.held, other)

// what is not a key is never kept
for (name, value) in [("a short text", "abc"), ("a text with a quote", String(repeating: "a", count: 30) + "\""),
                      ("a text with a space", String(repeating: "a", count: 30) + " b"), ("too long", String(repeating: "a", count: 129))] {
    let b = Box()
    let s = DeviceKeyKept(place: b, marks: Marks())
    check("\(name) is not kept", String(s.told(value)), "false")
    check("\(name) leaves nothing", b.held, nil)
}
let notText = DeviceKeyKept(place: Box(), marks: Marks())
check("a number is not kept", String(notText.told(42)), "false")
check("nothing is not kept", String(notText.told(nil)), "false")

// a Keychain that refuses the write: nothing is said, the page keeps its own
let refusing = Box(); refusing.refuses = true
let r = DeviceKeyKept(place: refusing, marks: Marks())
check("a refused write is not kept", String(r.told(key)), "false")
check("and nothing is said", r.script(own: own), nil)

// a value the Keychain holds that is not a key is not said
let odd = Box(); odd.held = "not a key"
let o = DeviceKeyKept(place: odd, marks: { let m = Marks(); m.mark(); return m }())
check("a kept value that is not a key is not said", o.script(own: own), nil)

// an origin with a port of its own says the port, one with the scheme's own does not
check("a port of its own", PageOrigin(URL(string: "http://localhost:4810/x"))?.text, "http://localhost:4810")
check("the scheme's own port", PageOrigin(URL(string: "https://example.web.app:443/x"))?.text, "https://example.web.app")
check("a build that names no page says nothing", shell.script(own: nil), nil)

print("device-key: \(passed) passed, \(failed) failed")
if failed > 0 { exit(1) }

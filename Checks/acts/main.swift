// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

// A check of Shell/ShellActs.swift on this Mac: what each shell says it
// does is said as the page reads it, each bridge says its own, and a shell
// says no word its bridge has no case for: scripts/check-acts.sh.

import Foundation

var passed = 0, failed = 0
func check(_ name: String, _ got: [String], _ want: [String]) {
    if got == want { passed += 1 } else { failed += 1; print("FAIL \(name):\n  got  \(got)\n  want \(want)") }
}

check("the phone's shell says what it does", [ShellActs.script(ShellActs.phone)],
      [#"window.inspoShell = { acts: ["haptic","vibrate","torch","share","clipboard","native"] };"#])
check("the desktop app says what it does", [ShellActs.script(ShellActs.desktop)],
      [#"window.inspoShell = { acts: ["haptic","native"] };"#])
check("a word with a quote in it stays inside its text", [ShellActs.script([#"a"b"#])], [#"window.inspoShell = { acts: ["a\"b"] };"#])

/// The words a bridge's source has a case for, and whether it says the list.
func bridge(_ path: String, says list: String) -> (cases: Set<String>, says: Bool) {
    let source = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    var cases = Set<String>()
    for line in source.split(separator: "\n") where line.trimmingCharacters(in: .whitespaces).hasPrefix("case \"") {
        for (n, part) in line.split(separator: "\"", omittingEmptySubsequences: false).enumerated() where n % 2 == 1 {
            cases.insert(String(part))
        }
    }
    return (cases, source.contains("ShellActs.script(ShellActs.\(list))"))
}

for (name, path, list, acts) in [
    ("the phone's shell", "Shell/ShellBridge.swift", "phone", ShellActs.phone),
    ("the desktop app", "Desktop/DesktopBridge.swift", "desktop", ShellActs.desktop),
] {
    let found = bridge(path, says: list)
    check("\(name) sets its acts on every page", [String(found.says)], ["true"])
    check("\(name) says no act its bridge has no case for", acts.filter { !found.cases.contains($0) }, [])
}

print("acts: \(passed) passed, \(failed) failed")
if failed > 0 { exit(1) }

// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

import Foundation

// What a shell does, said to the page as it loads. A page and the shell it
// runs in are not built together: a page is live at once, a shell is an app
// a person installs later. So the shell sets window.inspoShell.acts, a list
// of words, before the page's own script runs, and the page (inspo-core-js,
// utils/share.js) never hands the shell a request whose word is not there:
// it does it the web view's own way, or says at once that it cannot. A shell
// that says nothing is one built before this, and the page takes it to do
// what the oldest shell did: haptic, torch, native.
//
// A word is added here when the bridge takes the request it names, and
// never before: scripts/check-acts.sh holds each word to a case of its
// bridge.
enum ShellActs {
    /// The iOS shell's: a haptic's patterns, the long vibration (a haptic of
    /// mode vibrate), the phone's light, the share sheet, the clipboard, and
    /// a native library's call or stream.
    static let phone = ["haptic", "vibrate", "torch", "share", "clipboard", "native"]

    /// The desktop app's: the trackpad's tap for every haptic, and a native
    /// library. A share and a clipboard are the web view's own there.
    static let desktop = ["haptic", "native"]

    /// The script that says them, run at the start of every page.
    static func script(_ acts: [String]) -> String {
        let list = (try? JSONSerialization.data(withJSONObject: acts)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
        return "window.inspoShell = { acts: \(list) };"
    }
}

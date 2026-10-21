// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

import Foundation
import Security
#if os(iOS)
import UIKit
#endif

// The device's own key, kept by the shell too. The page (inspo-core-js,
// utils/device-key.js) makes a key once and keeps it in the web view's
// storage, and the engine derives the device's id from it; a gene keys
// what is the device's own on that id (a pause after wrong codes, a door
// the phone joined). The web view's storage is the page's, and iOS may
// lose it while the app lives on: under storage pressure, or with the web
// view's data reset. The page then makes another key, and the device is
// another device: what the gene kept for it is no longer its own.
//
// So the shell keeps a copy of the key in the Keychain, which outlives a
// close, a force-quit and the web view's data, and says it to the page as
// each page starts, before the page's own script runs; the page takes it
// over its own (device-key.js). The shell never makes a key: the first
// key it keeps is the one the page tells it ({type: "device-key", key}),
// so a phone that already had a key keeps the same device id when it
// gains this shell. A key the shell already keeps is never replaced.
//
//   - The key is said only to a page of the build's own origin: the script
//     that says it checks the page's origin first, so a page of another
//     site in the web view is told nothing (OwnPage.swift).
//   - It is kept for this phone only, readable once the phone was first
//     unlocked after a start (a locked phone at the door still has it),
//     and never in a backup that could be restored on another phone.
//   - An app deleted and installed again is a new device, as the page has
//     always said: the Keychain outlives an app's deletion, so the first
//     start of an install wipes what an earlier install kept, by a mark in
//     the app's own defaults, which go with the app.
//   - Before the phone's first unlock after a start the Keychain cannot be
//     read and the app's defaults read empty: then nothing is read, wiped
//     or kept, and it is done at the first word after the unlock.
//   - Nothing of the key is printed or logged.

/// Where the shell keeps the key: the Keychain in the app, a box in a check.
protocol DeviceKeyPlace: AnyObject {
    func read() -> String?
    /// Keeps the key where none is kept; false when one is kept already
    /// (it is never written over) or it could not be kept.
    func add(_ key: String) -> Bool
    func remove()
}

/// Whether this install has started before: a mark in the app's own
/// defaults, which are deleted with the app.
protocol InstallMarks: AnyObject {
    var marked: Bool { get }
    func mark()
}

final class DeviceKeyKept {
    /// The key as the page makes one: URL-safe base64, 22 to 128
    /// characters (device-key.js, KEY_FORM).
    static func isKey(_ value: Any?) -> Bool {
        guard let text = value as? String, (22...128).contains(text.utf8.count) else { return false }
        return text.utf8.allSatisfy { c in
            (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || (c >= 0x30 && c <= 0x39) || c == 0x2D || c == 0x5F
        }
    }

    private let place: DeviceKeyPlace
    private let marks: InstallMarks
    /// Whether the phone's protected data can be read now: not before its
    /// first unlock after a start, when the Keychain answers nothing and
    /// the app's defaults read empty.
    private let available: () -> Bool
    /// Whether what is kept has been read (and, at an install's first
    /// start, wiped): done once, when the phone's data can be read.
    private var settled = false
    /// The key the shell keeps, when it keeps one.
    private(set) var key: String?

    /// Reads what is kept; the first start of an install first wipes what
    /// an earlier install left. Before the phone's first unlock neither is
    /// done: a Keychain that cannot be read would read as none, and
    /// defaults that read empty as a new install, whose wipe would take
    /// the phone's key. They are done at the first word after.
    init(place: DeviceKeyPlace, marks: InstallMarks, available: @escaping () -> Bool) {
        self.place = place
        self.marks = marks
        self.available = available
        _ = settle()
    }

    /// Reads (and at an install's first start wipes) what is kept, once,
    /// when the phone's data can be read. True when it has been.
    func settle() -> Bool {
        guard !settled else { return true }
        guard available() else { return false }
        settled = true
        if !marks.marked {
            place.remove()
            marks.mark()
        }
        take(place.read())
        return true
    }

    private func take(_ kept: String?) {
        if key == nil, Self.isKey(kept) { key = kept }
    }

    /// The page told its key. Kept when the shell keeps none and it is a
    /// key; one the Keychain holds already is never written over, and is
    /// taken as the shell's (a read that failed before kept none in
    /// memory). True when the shell has a key now that it did not have
    /// (the scripts a page starts with then say it). Before the phone's
    /// first unlock nothing is kept.
    func told(_ value: Any?) -> Bool {
        guard key == nil, settle() else { return false }
        if key != nil { return true } // read at last: the kept one
        guard Self.isKey(value), let text = value as? String else { return false }
        if place.add(text) {
            key = text
        } else {
            take(place.read()) // one is kept already: that one, never the page's
        }
        return key != nil
    }

    /// The script that says the key to a page as it starts: only to a page
    /// of the build's own origin. None when no key is kept or the build
    /// names no page.
    func script(own: PageOrigin?) -> String? {
        guard let key, let own else { return nil }
        let origin = own.text
        // both are plain text (a key is URL-safe base64, an origin a
        // scheme, a host and a port), written as JSON texts all the same
        guard let said = try? JSONSerialization.data(withJSONObject: [origin, key]),
              let pair = String(data: said, encoding: .utf8) else { return nil }
        return "(function(p){if(location.origin===p[0]){window.inspoShell=window.inspoShell||{};window.inspoShell.deviceKey=p[1]}})(\(pair));"
    }

    /// The app's own: the Keychain and the app's defaults, read once the
    /// phone's protected data can be read.
    static let app = DeviceKeyKept(place: KeychainDeviceKey(), marks: DefaultsInstallMarks(), available: {
        #if os(iOS)
        let read = { UIApplication.shared.isProtectedDataAvailable }
        return Thread.isMainThread ? read() : DispatchQueue.main.sync(execute: read)
        #else
        return true
        #endif
    })
}

extension PageOrigin {
    /// The origin as a page reads location.origin: the scheme, the host,
    /// and the port when it is not the scheme's own.
    var text: String {
        port == Self.ownPort(of: scheme) || port == 0 ? "\(scheme)://\(host)" : "\(scheme)://\(host):\(port)"
    }
}

/// The key in the Keychain: a generic password of the app's own, for this
/// phone only, readable after the phone's first unlock.
final class KeychainDeviceKey: DeviceKeyPlace {
    private let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "shell") + ".device-key",
        kSecAttrAccount as String: "device-key",
    ]

    func read() -> String? {
        var asked = query
        asked[kSecReturnData as String] = true
        asked[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        guard SecItemCopyMatching(asked as CFDictionary, &found) == errSecSuccess, let data = found as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func add(_ key: String) -> Bool {
        var item = query
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        // one kept already (errSecDuplicateItem) is never written over
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    func remove() {
        SecItemDelete(query as CFDictionary)
    }
}

/// The mark in the app's own defaults.
final class DefaultsInstallMarks: InstallMarks {
    private static let name = "inspo-install-started"
    var marked: Bool { UserDefaults.standard.bool(forKey: Self.name) }
    func mark() { UserDefaults.standard.set(true, forKey: Self.name) }
}

// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

import Foundation

// What the page hands over to the phone, for the device neuron's share and
// clipboard (owner, 2026-09-29: "Go fires, renderer acts"). A web view
// opens no share sheet, and takes the clipboard only inside a tap, so the
// page hands the shell one request and the shell does it:
//
//   { type: "share", id, text, url }                    the share sheet with a text, a link or both
//   { type: "share", id, file: { name, mime, text } }   the share sheet with a file: the shell writes
//                                                       text under name and shares the file
//   { type: "clipboard", id, text }                     the text put on the clipboard
//
// Each is answered once, by its id: answered when the sheet has closed
// (whether the person shared or put it away: iOS's word on which is not
// passed on) or the clipboard holds the text, failed with a reason when it
// could not be done. The engine resolved every value and holds the rules of
// what may be handed over; the shell holds them again for what reaches the
// phone's own files and sheet: a file's name is a plain file name, a link
// is an http or https address, and nothing is larger than the limit.
//
// A shared file is written under the app's temporary folder, in a folder
// of its own, and removed when its sheet closes; what an earlier share
// left (an app ended with its sheet open) is removed when the next begins.
// Nothing handed over is printed or kept.

/// One thing a share sheet is given.
enum SharedItem: Equatable {
    case text(String)
    case link(URL)
    case file(URL)
}

/// A share sheet the shell can open: the phone's own, or a test's.
protocol ShareSheet {
    /// Opens the sheet with the items; closed is called once when it has
    /// closed. False when it could not be opened.
    func open(_ items: [SharedItem], closed: @escaping () -> Void) -> Bool
}

/// A clipboard the shell can write: the phone's own, or a test's.
protocol Clipboard {
    func hold(_ text: String)
}

/// The page's share and clipboard requests, each answered once.
final class HandOver {
    static let shared = HandOver()
    /// The most a text or a file may hold, in bytes (the engine's limit).
    static let limit = 1_000_000

    /// The phone's share sheet, looked for at each request; none where no
    /// sheet can be shown.
    var sheet: () -> ShareSheet? = { nil }
    /// The phone's clipboard; none where there is none.
    var clipboard: () -> Clipboard? = { nil }
    /// Where shared files are written, each in a folder of its own.
    var folder = FileManager.default.temporaryDirectory.appendingPathComponent("shared", isDirectory: true)
    private(set) var open = false

    /// Takes a share request. A sheet already open is not opened over.
    func share(_ body: [String: Any], answered: @escaping () -> Void, failed: @escaping (String) -> Void) {
        guard !open else { return failed("a share sheet is already open") }
        clear()
        let text = body["text"] as? String ?? ""
        let link = body["url"] as? String ?? ""
        var items: [SharedItem] = []
        var written: URL?
        if let file = body["file"] {
            guard text.isEmpty, link.isEmpty else { return failed("a share is a file, or a text and a link, not both") }
            guard let file = file as? [String: Any], let name = file["name"] as? String, HandOver.plainFileName(name) else {
                return failed("a file's name is a plain file name")
            }
            guard let content = (file["text"] as? String)?.data(using: .utf8), !content.isEmpty else {
                return failed("a file with nothing in it is not shared")
            }
            guard content.count <= HandOver.limit else { return failed("a file is at most \(HandOver.limit) bytes") }
            let place = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let url = place.appendingPathComponent(name, isDirectory: false)
            do {
                try FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)
                try content.write(to: url, options: .atomic)
            } catch {
                try? FileManager.default.removeItem(at: place)
                return failed("the file could not be written")
            }
            written = place
            items = [.file(url)]
        } else {
            guard text.utf8.count <= HandOver.limit else { return failed("a text is at most \(HandOver.limit) bytes") }
            if !text.isEmpty { items.append(.text(text)) }
            if !link.isEmpty {
                guard let url = HandOver.webLink(link) else { return failed("a share's link is an http or https address") }
                items.append(.link(url))
            }
            guard !items.isEmpty else { return failed("a share is given a text, a link or a file") }
        }
        let remove = { if let written { try? FileManager.default.removeItem(at: written) } }
        guard let sheet = sheet() else {
            remove()
            return failed("nothing here can show a share sheet")
        }
        open = true
        var closedOnce = false
        let shown = sheet.open(items) { [weak self] in
            guard !closedOnce else { return }
            closedOnce = true
            self?.open = false
            remove()
            answered()
        }
        if !shown && !closedOnce {
            closedOnce = true
            open = false
            remove()
            failed("the share sheet could not be opened")
        }
    }

    /// Takes a clipboard request: the text is put on the clipboard.
    func copy(_ body: [String: Any], answered: @escaping () -> Void, failed: @escaping (String) -> Void) {
        guard let text = body["text"] as? String, !text.isEmpty else { return failed("a clipboard is given a text") }
        guard text.utf8.count <= HandOver.limit else { return failed("a text is at most \(HandOver.limit) bytes") }
        guard let clipboard = clipboard() else { return failed("no clipboard here") }
        clipboard.hold(text)
        answered()
    }

    /// Removes every shared file an earlier share left.
    func clear() {
        guard !open else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    /// Whether name is a file's name and nothing else: no folder, no
    /// control character, not too long.
    static func plainFileName(_ name: String) -> Bool {
        guard !name.isEmpty, name != ".", name != "..", name.utf8.count <= 255 else { return false }
        return !name.unicodeScalars.contains { $0 == "/" || $0 == "\\" || $0.properties.generalCategory == .control }
    }

    /// An http or https address with a host, or none: a share never names
    /// a file of the phone's own.
    static func webLink(_ link: String) -> URL? {
        guard !link.unicodeScalars.contains(where: { $0.properties.isWhitespace }),
              let parts = URLComponents(string: link), let scheme = parts.scheme?.lowercased(),
              scheme == "https" || scheme == "http", !(parts.host ?? "").isEmpty else { return nil }
        return parts.url
    }
}

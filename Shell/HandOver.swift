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
// phone's own files and sheet: a file's name is a plain file name, its
// type one of the few a share's file may have and its name ends as that
// type does, a link is an https address with no user or password in it and
// no longer than a link may be, and nothing is larger than the limit.
//
// A shared file is written under the app's temporary folder, in a folder
// of its own, and removed when its sheet closes; what an earlier share
// left (an app ended with its sheet open) is removed when the app opens
// and when the next share begins. Nothing handed over is printed or kept.
//
// One sheet is open at a time, and nothing holds that for ever: a sheet
// that could not be opened says so, at once or a moment later, and one iOS
// took down without a word is found gone when the next share asks. A
// request that arrives twice opens one sheet. A page that loads afresh
// under an open sheet leaves the sheet to the person and is told nothing.

/// One thing a share sheet is given.
enum SharedItem: Equatable {
    case text(String)
    case link(URL)
    case file(URL)
}

/// A share sheet the shell can open: the phone's own, or a test's.
protocol ShareSheet {
    /// Opens the sheet with the items; ended is called once: with true
    /// when the sheet has closed, with false when it could not be opened,
    /// at once or a moment later.
    func open(_ items: [SharedItem], ended: @escaping (_ shown: Bool) -> Void)
    /// Whether the sheet this opened is on the screen, or on its way there.
    var showing: Bool { get }
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

    /// The share whose sheet is open: who asked, by the request's id, its
    /// sheet, the file written for it, and how the page is answered.
    private final class OpenShare {
        let id: String
        let sheet: ShareSheet
        let written: URL?
        var answered: (() -> Void)?
        var failed: ((String) -> Void)?
        var ended = false
        init(id: String, sheet: ShareSheet, written: URL?, answered: @escaping () -> Void, failed: @escaping (String) -> Void) {
            self.id = id
            self.sheet = sheet
            self.written = written
            self.answered = answered
            self.failed = failed
        }
    }
    private var current: OpenShare?
    /// Whether a share's sheet is open.
    var open: Bool { current != nil }

    /// Takes a share request. A sheet already open is not opened over; the
    /// open share sent again (the engine sends a request again when it
    /// could not tell that it arrived) is the one being done, and is not
    /// answered twice.
    func share(_ body: [String: Any], answered: @escaping () -> Void, failed: @escaping (String) -> Void) {
        let id = body["id"] as? String ?? ""
        if let now = current {
            if !id.isEmpty, now.id == id { return }
            // a sheet iOS took down without saying so has closed: the share
            // before ends here, so one lost answer never holds every share after it
            guard !now.sheet.showing else { return failed("a share sheet is already open") }
            end(now, shown: true)
        }
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
            // iOS chooses what opens a file by how its name ends, so the
            // name ends as the type says, and the type is one of the few
            let mime = file["mime"] as? String ?? ""
            guard HandOver.fileTypes[mime] != nil else { return failed("a file's mime is a type a share's file may have") }
            guard HandOver.nameFitsType(name, mime) else { return failed("a file's name ends as its type does") }
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
                guard link.utf8.count <= HandOver.linkLimit else { return failed("a link is at most \(HandOver.linkLimit) bytes") }
                guard let url = HandOver.webLink(link) else { return failed("a share's link is an https address, with no user or password in it") }
                items.append(.link(url))
            }
            guard !items.isEmpty else { return failed("a share is given a text, a link or a file") }
        }
        guard let sheet = sheet() else {
            if let written { try? FileManager.default.removeItem(at: written) }
            return failed("nothing here can show a share sheet")
        }
        let share = OpenShare(id: id, sheet: sheet, written: written, answered: answered, failed: failed)
        current = share
        sheet.open(items) { [weak self] shown in self?.end(share, shown: shown) }
    }

    /// Ends a share, once: its file goes, the next may open, and the page
    /// that asked is answered (its sheet closed) or told it could not open.
    private func end(_ share: OpenShare, shown: Bool) {
        guard !share.ended else { return }
        share.ended = true
        if current === share { current = nil }
        if let written = share.written { try? FileManager.default.removeItem(at: written) }
        if shown { share.answered?() } else { share.failed?("the share sheet could not be opened") }
    }

    /// The page that asked is gone (it loads afresh, or its content ended):
    /// a sheet that is open stays for the person who is in it, its file goes
    /// when it closes, and no page is answered: the one that loads now never
    /// asked.
    func pageGone() {
        current?.answered = nil
        current?.failed = nil
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
    /// character that is not shown (a control character, or one that only
    /// turns the writing round or joins it, which can make a name read as
    /// another), not too long.
    static func plainFileName(_ name: String) -> Bool {
        guard !name.isEmpty, name != ".", name != "..", name.utf8.count <= 255 else { return false }
        return !name.unicodeScalars.contains {
            let kind = $0.properties.generalCategory
            return $0 == "/" || $0 == "\\" || kind == .control || kind == .format || kind == .lineSeparator || kind == .paragraphSeparator
        }
    }

    /// The types a share's file may have, each with how a file of it ends
    /// (the engine's list): a text a person reads or a table opens, never a
    /// file a system runs, installs or shows as a page.
    static let fileTypes: [String: [String]] = [
        "text/csv": [".csv"],
        "text/tab-separated-values": [".tsv"],
        "text/plain": [".txt"],
        "text/markdown": [".md"],
        "application/json": [".json"],
    ]

    /// Whether a file's name ends as a file of type mime does, in either
    /// case, with something before the ending.
    static func nameFitsType(_ name: String, _ mime: String) -> Bool {
        let lower = name.lowercased()
        return (fileTypes[mime] ?? []).contains { lower.hasSuffix($0) && lower.utf8.count > $0.utf8.count }
    }

    /// The most a share's link may hold, in bytes (the engine's limit).
    static let linkLimit = 2048

    /// An https address with a host and no user or password in it, no
    /// longer than a link may be, or none: a share never names a file of
    /// the phone's own, never sends a person to a page read in the clear,
    /// and never carries a sign-in.
    static func webLink(_ link: String) -> URL? {
        guard link.utf8.count <= linkLimit, !link.unicodeScalars.contains(where: { $0.properties.isWhitespace }),
              let parts = URLComponents(string: link), parts.scheme?.lowercased() == "https",
              !(parts.host ?? "").isEmpty, parts.user == nil, parts.password == nil else { return nil }
        return parts.url
    }
}

// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

import Foundation

// Whose page the shell answers. The shell's bridge is in every page the
// web view holds, and a web view goes where a link takes it: a gene that
// draws a link out of its own site puts another site's page in the app,
// with the same bridge in it. What a page is handed is what its own
// request's keep names (NativeLibrary.swift), which protects a read only
// while the page is the gene's: another site's page could name a scan's
// every field. So the shell answers one page alone, the build's own:
//
//   - A request is taken only from the main frame of a page whose origin
//     is the origin of the build's page (INSPO_URL): its scheme, its host
//     and its port, as a browser tells one site from another. A page of
//     any other origin, and a frame inside any page, is answered nothing:
//     no call, no stream, no haptic, no light, no share, no clipboard, and
//     no word that it was refused (a page told "no" has learned that a
//     shell is there and can ask again in other words).
//   - What the shell tells a page (an answer, a stream's event, a link
//     that opened the app) is told only while the page the web view holds
//     is the build's own; and an answer is told only to the page that
//     asked: when another page takes its place, what waited for the page
//     before is nobody's.
//
// The camera's grant holds to the build's host in the same way
// (ShellBridge.swift). The shell does not keep a page of another origin
// out of the web view: a sign-in that passes through another site and
// comes back is such a page. It only answers it nothing.

/// A page's origin, as a browser tells one site from another.
struct PageOrigin: Equatable {
    let scheme: String
    let host: String
    let port: Int

    /// A frame's origin as the web view says it: a port of 0 is the
    /// scheme's own.
    init(scheme: String, host: String, port: Int) {
        self.scheme = scheme.lowercased()
        self.host = host.lowercased()
        self.port = port > 0 ? port : Self.ownPort(of: self.scheme)
    }

    /// An address's origin; nil for one that has no host (about:blank, a
    /// file).
    init?(_ url: URL?) {
        guard let url, let scheme = url.scheme, let host = url.host, !host.isEmpty else { return nil }
        self.init(scheme: scheme, host: host, port: url.port ?? 0)
    }

    static func ownPort(of scheme: String) -> Int {
        switch scheme {
        case "https": return 443
        case "http": return 80
        default: return 0
        }
    }
}

/// The door a page's requests come through.
struct PageDoor {
    /// The build's own page's origin; nil in a build that names no page,
    /// which answers nobody.
    let own: PageOrigin?

    /// Whether a page of this origin is the build's own.
    func isOwn(_ page: PageOrigin?) -> Bool {
        guard let own, let page else { return false }
        return page == own
    }

    /// A page's request, when it is taken: from the main frame of the
    /// build's own page, and of the shape a request has. Else nil, and
    /// nothing is done or said.
    func take(_ body: Any, from asker: PageOrigin?, mainFrame: Bool) -> [String: Any]? {
        guard mainFrame, isOwn(asker) else { return nil }
        return body as? [String: Any]
    }
}

/// What the shell has to tell a page that cannot be told yet, and which
/// page each is for.
struct PageWaiting {
    /// The page the web view holds, counted: one more each time another
    /// page takes its place.
    private(set) var page = 0
    private var waiting: [(words: String, page: Int?)] = []

    /// Whether something asked by that page may still be told: only while
    /// that page is the one held. What no page asked for (a link that
    /// opened the app) is for whichever page of the build's own is held.
    func isFor(_ asked: Int?) -> Bool {
        asked == nil || asked == page
    }

    /// Keeps words until a page can be told them.
    mutating func wait(_ words: String, for asked: Int?) {
        waiting.append((words, asked))
    }

    /// Another page has taken the place of the one held: what waited for
    /// the page before is nobody's.
    mutating func pageChanged() {
        page += 1
        waiting.removeAll { $0.page != nil }
    }

    /// Everything that waits, in order, for the page now held to be told.
    mutating func take() -> [String] {
        let all = waiting.map(\.words)
        waiting = []
        return all
    }
}

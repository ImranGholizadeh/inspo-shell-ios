// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

import Foundation

// A native library the shell carries (a vendor's Bluetooth ID scanner,
// through its adapter, IDScanner.swift) is an API the gene reaches through the
// exotic bridge (owner, 2026-09-30, E40: "Like an exotic agent"): each call
// and each event stream is an endpoint document, native://<library>/<name>,
// and the page hands the shell one request per call or stream:
//
//   { type: "native", id, url, data, keep, listen }   a call, or a stream to start
//   { type: "native", id, stop: true }                a stream whose page has left
//
// The shell keeps only the fields keep names before anything leaves the
// phone (E41: "Phone drops them"), and answers through
// window.inspo.nativeAnswered(id, value) or nativeFailed(id, error).

/// A native library as the shell carries it: an adapter over a vendor's
/// package. Its answers are JSON-shaped; the shell filters them.
protocol NativeLibrary: AnyObject {
    /// The library's name in its endpoints' urls: native://<name>/...
    var name: String { get }
    /// Runs one call; answers once.
    func call(_ call: String, data: Any?, answer: @escaping (Result<[String: Any], NativeError>) -> Void)
    /// Starts an event stream; each event until the returned stop is called.
    /// Every event of one endpoint is handed to every stream of it that is
    /// open, and only the words said to a stream as it opens (where it
    /// begins) go to that stream alone: the engine counts on it, to tell a
    /// second copy of an event from a new one when a page holds two streams
    /// of one endpoint for a moment.
    func listen(_ events: String, data: Any?, each: @escaping ([String: Any]) -> Void,
                failed: @escaping (NativeError) -> Void) -> () -> Void
}

struct NativeError: Error {
    let message: String
}

/// The libraries the shell carries, and the streams running for the page.
final class NativeLibraries {
    static let shared = NativeLibraries()
    private var libraries: [String: NativeLibrary] = [:]
    private var streams: [String: () -> Void] = [:]

    /// Adds a library (an adapter, or the stand-in).
    func register(_ library: NativeLibrary) {
        libraries[library.name] = library
    }

    /// Only the fields keep names: nothing else leaves the phone.
    static func keepOnly(_ value: [String: Any], _ keep: Set<String>) -> [String: Any] {
        value.filter { keep.contains($0.key) }
    }

    /// Takes one request from the page; answered and failed carry the
    /// request's id back.
    func handle(_ body: [String: Any], answered: @escaping (String, [String: Any]) -> Void,
                failed: @escaping (String, String) -> Void) {
        guard let id = body["id"] as? String else { return }
        if body["stop"] as? Bool == true {
            streams.removeValue(forKey: id)?()
            return
        }
        guard let url = body["url"] as? String, url.hasPrefix("native://") else {
            failed(id, "not a native endpoint")
            return
        }
        let path = url.dropFirst("native://".count).split(separator: "/", maxSplits: 1).map(String.init)
        guard path.count == 2, let library = libraries[path[0]] else {
            failed(id, "no library \(path.first ?? "")")
            return
        }
        let keep = Set(body["keep"] as? [String] ?? [])
        let data = body["data"]
        if body["listen"] as? Bool == true {
            streams.removeValue(forKey: id)?()
            streams[id] = library.listen(path[1], data: data,
                each: { answered(id, Self.keepOnly($0, keep)) },
                failed: { failed(id, $0.message) })
            return
        }
        library.call(path[1], data: data) { result in
            switch result {
            case .success(let value): answered(id, Self.keepOnly(value, keep))
            case .failure(let err): failed(id, err.message)
            }
        }
    }

    /// Stops every stream: the page has gone (reloaded or ended).
    func stopAll() {
        let running = streams
        streams = [:]
        running.values.forEach { $0() }
    }
}

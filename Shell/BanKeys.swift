// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

import Foundation

// The phone's saved ban list, native://ban-keys (CLICR's records, release 2).
// On a night with no signal the door phone cannot ask the database whether a
// scanned ID is banned. The records hand the shell a list of hashed ban
// keys while signal is there, and ask it to match a scan against the list
// when the database gives no answer. The shell keeps the list and nothing
// else of a person: the hashed key, the issuing state, the reason code and
// when the ban was made. Anything else in a body is dropped, never stored.
//
//   replace {keys: [row, ...], page}   -> {n}   n rows held after the call.
//       The records send the list in pages of 100: page absent or 0 drops
//       the list and keeps these; page 1 and up add these (a row whose eid
//       is held already is replaced). `page` is Inspo's addition to the
//       records' call.
//   put {row}                          -> {}    a ban landed (same eid replaces)
//   lift {eid}                         -> {}    a lift landed (unknown eid is fine)
//   match {idKey, issuingState}        -> {hit, reason, createdAtMs}
//       hit 1 with the newest held row (by createdAtMs) of that key AND
//       state; else {hit: 0, reason: "", createdAtMs: 0}.
//
// A row is {eid, idKey, issuingState, reason, createdAtMs}.
//
//   - match ALWAYS answers, at once: with no list, a file that cannot be
//     read, or words that make no sense, it is a miss. The engine's native
//     timeout (30 s) is never what tells the door "not checked".
//   - The list is kept in one file in Application Support: written whole
//     and atomically at every change (so a restart mid-write reads the
//     list as it was, not half), readable once the phone was first
//     unlocked after a start (a door phone is locked between scans), and
//     out of any backup that could be restored on another phone.
//   - A file that cannot be read is not taken as an empty list: the list
//     is read again at the next word, so a read before the first unlock
//     never lets a later write take the list's place. A file that reads but
//     is no list is an empty one.
//   - Nothing of the list goes to any server, log line or the engine; a key
//     is never printed.

struct BanKeyRow: Equatable {
    let eid: String
    let idKey: String
    let issuingState: String
    let reason: String
    let createdAtMs: Int64

    static let fields = ["eid", "idKey", "issuingState", "reason", "createdAtMs"]

    /// A row as the page says it: the five fields, a text for each of the
    /// four texts (the eid and the key not empty) and a whole number for the
    /// time. Whatever else a body holds is not read.
    init?(_ value: Any?) {
        guard let body = value as? [String: Any],
              let eid = body["eid"] as? String, !eid.isEmpty,
              let idKey = body["idKey"] as? String, !idKey.isEmpty,
              let state = body["issuingState"] as? String,
              let reason = body["reason"] as? String,
              let at = Self.whole(body["createdAtMs"]) else { return nil }
        self.eid = eid
        self.idKey = idKey
        self.issuingState = state
        self.reason = reason
        self.createdAtMs = at
    }

    /// A whole number (not a truth value, not a fraction).
    static func whole(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double == double.rounded(), abs(double) < 9.0e15 else { return nil }
        return number.int64Value
    }

    var json: [String: Any] {
        ["eid": eid, "idKey": idKey, "issuingState": issuingState, "reason": reason, "createdAtMs": createdAtMs]
    }
}

final class BanKeysLibrary: NativeLibrary {
    let name = "ban-keys"
    private let file: URL
    private let lock = NSLock()
    /// The rows held, by eid; nil until the file has been read.
    private var rows: [String: BanKeyRow]?

    init(file: URL) {
        self.file = file
    }

    /// The app's own: one file in Application Support.
    static let app = BanKeysLibrary(file: {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ban-keys", isDirectory: true).appendingPathComponent("bans.json")
    }())

    private static let rowWords = "needs eid, idKey, issuingState, reason and createdAtMs"

    func call(_ call: String, data: Any?, answer: @escaping (Result<[String: Any], NativeError>) -> Void) {
        let body = data as? [String: Any] ?? [:]
        lock.lock()
        defer { lock.unlock() }
        switch call {
        case "match":
            answer(.success(match(body)))
        case "put":
            guard let row = BanKeyRow(data) else {
                answer(.failure(NativeError(message: "put: \(Self.rowWords)")))
                return
            }
            answer(change { $0[row.eid] = row }.map { .failure($0) } ?? .success([:]))
        case "lift":
            guard let eid = body["eid"] as? String, !eid.isEmpty else {
                answer(.failure(NativeError(message: "lift: needs eid")))
                return
            }
            answer(change { $0.removeValue(forKey: eid) }.map { .failure($0) } ?? .success([:]))
        case "replace":
            guard let list = body["keys"] as? [Any] else {
                answer(.failure(NativeError(message: "replace: needs keys")))
                return
            }
            let parsed = list.compactMap { BanKeyRow($0) }
            guard parsed.count == list.count else {
                answer(.failure(NativeError(message: "replace: needs keys")))
                return
            }
            var page: Int64 = 0
            if let said = body["page"], !(said is NSNull) {
                guard let whole = BanKeyRow.whole(said), whole >= 0 else {
                    answer(.failure(NativeError(message: "replace: page is a whole number")))
                    return
                }
                page = whole
            }
            if let err = change({ held in
                if page == 0 { held = [:] }
                for row in parsed { held[row.eid] = row }
            }) {
                answer(.failure(err))
            } else {
                answer(.success(["n": rows?.count ?? 0]))
            }
        default:
            answer(.failure(NativeError(message: "no call \(call)")))
        }
    }

    func listen(_ events: String, data: Any?, each: @escaping ([String: Any]) -> Void,
                failed: @escaping (NativeError) -> Void) -> () -> Void {
        failed(NativeError(message: "no stream \(events)"))
        return {}
    }

    // MARK: the list

    private static let miss: [String: Any] = ["hit": 0, "reason": "", "createdAtMs": 0]

    /// The newest held row of this key and state, else a miss: always an answer.
    private func match(_ body: [String: Any]) -> [String: Any] {
        guard let key = body["idKey"] as? String, !key.isEmpty, let state = body["issuingState"] as? String,
              loaded() else { return Self.miss }
        var best: BanKeyRow?
        for row in (rows ?? [:]).values where row.idKey == key && row.issuingState == state {
            if best == nil || row.createdAtMs > best!.createdAtMs { best = row }
        }
        guard let found = best else { return Self.miss }
        return ["hit": 1, "reason": found.reason, "createdAtMs": found.createdAtMs]
    }

    /// Reads the file once it can be read. A file that is not there, or
    /// reads but is no list, is an empty list; one that cannot be read is
    /// not (false: asked again at the next word).
    private func loaded() -> Bool {
        if rows != nil { return true }
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch let error as NSError {
            let absent = error.domain == NSCocoaErrorDomain && (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError)
            if absent { rows = [:] }
            return absent
        }
        var held: [String: BanKeyRow] = [:]
        if let list = (try? JSONSerialization.jsonObject(with: data)) as? [Any] {
            for case let row? in list.map({ BanKeyRow($0) }) { held[row.eid] = row }
        }
        rows = held
        return true
    }

    /// Changes the list and keeps it. The list in memory is the changed one
    /// either way (the door still matches against it); an error says it was
    /// not kept, or could not be read to change.
    private func change(_ edit: (inout [String: BanKeyRow]) -> Void) -> NativeError? {
        guard loaded(), var held = rows else { return NativeError(message: "could not keep the list: it cannot be read yet") }
        edit(&held)
        rows = held
        return keep(held)
    }

    /// Written whole, atomically; protected until the first unlock; out of backups.
    private func keep(_ held: [String: BanKeyRow]) -> NativeError? {
        let list = held.values.sorted { ($0.createdAtMs, $0.eid) < ($1.createdAtMs, $1.eid) }.map(\.json)
        do {
            let data = try JSONSerialization.data(withJSONObject: list)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            var options: Data.WritingOptions = [.atomic]
            #if os(iOS)
            options.insert(.completeFileProtectionUntilFirstUserAuthentication)
            #endif
            try data.write(to: file, options: options)
            var mark = URLResourceValues()
            mark.isExcludedFromBackup = true
            var place = file
            try place.setResourceValues(mark)
            return nil
        } catch {
            return NativeError(message: "could not keep the list")
        }
    }
}

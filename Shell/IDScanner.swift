// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

import Foundation
import IDScannerSurface
#if os(iOS)
import UIKit
#endif

// A Bluetooth ID scanner as a native library (E47): the adapter that maps a
// vendor's scanner package onto the endpoint documents a gene declares
// (E40: one document per call, one per event stream). The package is not in
// this repository: the adapter is written against BluetoothIDScanner, the
// surface it needs in plain terms (Packages/IDScannerSurface), and a
// customer's Xcode workspace builds a binding that conforms the package to
// it in place of the stand-in package Packages/IDScannerBinding (README).
// A test build's stand-in (StandInReader, E42) conforms to the same
// surface, so its answers take the same mapping and the same shape.
//
// The adapter's names, the gene's endpoint urls native://<library>/<name>:
//
//   calls   state          the connection state and the battery, in one answer
//           feedback       data "accept" | "deny" | "error" (or {pattern: ...})
//           start-reading  results and duplicates start reaching the stream
//           stop-reading   they stop
//           reconnect      connects the paired scanner again
//           forget         forgets the paired scanner
//   stream  events         every event, flat, with a kind:
//
//   { kind: "read" | "failedRead" | "failedValidation",
//     fullName, dateOfBirth, expirationDate, isOver21, isExpired,  (the holder's, when read)
//     issueCode }                                                  (the first issue, if any)
//   { kind: "duplicate", result }      a result the scanner suppressed as a
//                                      repeat, with only its kind (read, ...)
//   { kind: "state", state }           a real connection change: idle,
//                                      scanning, connecting, connected,
//                                      reconnecting, disconnected; the
//                                      package's reading during each scan is
//                                      held back (owner, 2026-10-01: "Hold
//                                      'reading' back")
//   { kind: "battery", battery }       the percent
//
// Nothing else leaves the adapter: the raw scan, the document's number and
// every other field of the vendor's result have no place in the surface's
// types. The shell then keeps only the fields the endpoint's keep names (E41).

/// The adapter: a NativeLibrary over a BluetoothIDScanner.
final class IDScannerAdapter: NativeLibrary {
    let name: String
    private let scanner: BluetoothIDScanner
    private var configured: Result<Void, NativeError>?
    /// The page's streams, by key; every event reaches each.
    private var sinks: [UUID: ([String: Any]) -> Void] = [:]
    /// The package's listeners: state and battery while a stream is open,
    /// results while reading.
    private var stateListener: (() -> Void)?
    private var scanListener: (() -> Void)?
    private var foreground: NSObjectProtocol?
    /// The last state the streams heard, so a held-back reading never
    /// shows as a change.
    private var heardState: String?

    init(name: String, scanner: BluetoothIDScanner) {
        self.name = name
        self.scanner = scanner
    }

    deinit {
        stateListener?()
        scanListener?()
        if let foreground { NotificationCenter.default.removeObserver(foreground) }
    }

    /// The scanner a customer build links (IDScannerBinding's), under the
    /// library name the build gives. Nil in a build without one.
    static func linked(name: String, scanner: BluetoothIDScanner?) -> IDScannerAdapter? {
        guard !name.isEmpty, let scanner else { return nil }
        return IDScannerAdapter(name: name, scanner: scanner)
    }

    // MARK: configuration, once

    /// Configures the package on first use, so its Bluetooth prompt comes
    /// when a page first asks for the scanner, not at launch.
    private func ready() -> NativeError? {
        if configured == nil {
            do {
                try scanner.configure(ScannerPolicy(checksAge: true, checksExpiry: true))
                configured = .success(())
                #if os(iOS)
                foreground = NotificationCenter.default.addObserver(
                    forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
                ) { [weak self] _ in self?.scanner.becameActive() }
                #endif
            } catch {
                configured = .failure(NativeError(message: "configure: \(error)"))
            }
        }
        if case .failure(let err) = configured { return err }
        return nil
    }

    // MARK: calls

    func call(_ call: String, data: Any?, answer: @escaping (Result<[String: Any], NativeError>) -> Void) {
        if let err = ready() {
            answer(.failure(err))
            return
        }
        let done: (Error?) -> Void = { error in
            answer(error.map { .failure(NativeError(message: "\($0)")) } ?? .success([:]))
        }
        switch call {
        case "state":
            var value: [String: Any] = ["kind": "state", "state": Self.shown(scanner.connection.state)]
            if let battery = scanner.batteryPercent { value["battery"] = battery }
            answer(.success(value))
        case "feedback":
            guard let kind = Self.feedback(data) else {
                answer(.failure(NativeError(message: "feedback: no pattern \(Self.pattern(data) ?? "")")))
                return
            }
            scanner.feedback(kind, done: done)
        case "start-reading":
            if scanListener == nil {
                scanListener = scanner.listen { [weak self] event in
                    switch event {
                    case .result, .duplicate: self?.send(event)
                    default: break
                    }
                }
            }
            answer(.success([:]))
        case "stop-reading":
            stopReading()
            answer(.success([:]))
        case "reconnect", "forget":
            guard let id = scanner.connection.deviceID ?? scanner.pairedDeviceIDs.first else {
                answer(.failure(NativeError(message: "\(call): no paired scanner")))
                return
            }
            if call == "reconnect" {
                scanner.connect(id, done: done)
            } else {
                scanner.forget(id, done: done)
            }
        default:
            answer(.failure(NativeError(message: "no call \(call)")))
        }
    }

    /// A feedback's pattern onto the package's two kinds.
    static func feedback(_ data: Any?) -> ScannerFeedback? {
        switch pattern(data) {
        case "accept": return .success
        case "deny", "error": return .error
        default: return nil
        }
    }

    static func pattern(_ data: Any?) -> String? {
        (data as? String) ?? ((data as? [String: Any])?["pattern"] as? String)
    }

    // MARK: the stream

    func listen(_ events: String, data: Any?, each: @escaping ([String: Any]) -> Void,
                failed: @escaping (NativeError) -> Void) -> () -> Void {
        guard events == "events" else {
            failed(NativeError(message: "no stream \(events)"))
            return {}
        }
        if let err = ready() {
            failed(err)
            return {}
        }
        let key = UUID()
        sinks[key] = each
        if stateListener == nil {
            stateListener = scanner.listen { [weak self] event in
                switch event {
                case .connection, .battery: self?.send(event)
                default: break
                }
            }
        }
        let now = Self.shown(scanner.connection.state)
        heardState = now
        each(["kind": "state", "state": now]) // where the stream begins
        return { [weak self] in
            guard let self else { return }
            self.sinks.removeValue(forKey: key)
            if self.sinks.isEmpty {
                // the page has gone: nothing is listening, nothing is read
                self.stateListener?()
                self.stateListener = nil
                self.heardState = nil
                self.stopReading()
            }
        }
    }

    private func stopReading() {
        scanListener?()
        scanListener = nil
    }

    private func send(_ event: ScannerLibraryEvent) {
        if case .connection(let state) = event {
            // only a real change: reading is connected, and a scan's
            // connected after it is no change
            let now = Self.shown(state)
            guard now != heardState else { return }
            heardState = now
        }
        guard let value = Self.flat(event) else { return }
        sinks.values.forEach { $0(value) }
    }

    // MARK: the flat shape

    /// A state as the gene hears it: the package's reading, during each
    /// scan, is a connected scanner.
    static func shown(_ state: String) -> String {
        state == "reading" ? "connected" : state
    }

    /// An event as the gene receives it: top-level fields only, a kind first.
    static func flat(_ event: ScannerLibraryEvent) -> [String: Any]? {
        switch event {
        case .result(let result):
            return flat(result)
        case .duplicate(let result):
            return ["kind": "duplicate", "result": result.kind.rawValue]
        case .connection(let state):
            return ["kind": "state", "state": shown(state)]
        case .battery(let percent):
            return ["kind": "battery", "battery": percent]
        case .unpassed:
            return nil
        }
    }

    static func flat(_ result: ScannerResult) -> [String: Any] {
        var value: [String: Any] = ["kind": result.kind.rawValue]
        if let holder = result.holder {
            value["fullName"] = holder.fullName
            value["dateOfBirth"] = holder.dateOfBirth
            value["isOver21"] = holder.isOver21
            if let expiry = holder.expirationDate { value["expirationDate"] = expiry }
            if let expired = holder.isExpired { value["isExpired"] = expired }
        }
        if let code = result.issueCodes.first { value["issueCode"] = code }
        return value
    }
}

// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

import Foundation
#if os(iOS)
import UIKit
#endif

// A Bluetooth ID scanner as a native library (E47): the adapter that maps a
// vendor's scanner package onto the endpoint documents a gene declares
// (E40: one document per call, one per event stream). The package is not in
// this repository: the adapter is written against BluetoothIDScanner, the
// surface it needs in plain terms, and a customer build links the package
// with one binding file that conforms it (Bindings/, compiled only there).
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
//   { kind: "duplicate" }                   a result the scanner suppressed as a repeat
//   { kind: "state", state }                connecting, connected, reading, reconnecting, ...
//   { kind: "battery", battery }            the percent
//
// Nothing else leaves the adapter: the raw scan, the document's number and
// every other field of the vendor's result have no place in these types.
// The shell then keeps only the fields the endpoint's keep names (E41).

/// The scanner's surface the adapter needs. A binding conforms the vendor's
/// package to it; the stand-in conforms a made-up scanner. Callbacks come
/// on the main thread.
protocol BluetoothIDScanner: AnyObject {
    init()
    /// Configures the package; the adapter calls it once, before anything else.
    func configure(_ policy: ScannerPolicy) throws
    /// The connection's state now, and the paired scanner's id if one is paired.
    var connection: ScannerConnection { get }
    /// The battery's percent, if the scanner has said.
    var batteryPercent: Int? { get }
    /// The ids of the scanners paired with this phone.
    var pairedDeviceIDs: [String] { get }
    func feedback(_ kind: ScannerFeedback, done: @escaping (Error?) -> Void)
    func connect(_ deviceID: String, done: @escaping (Error?) -> Void)
    func forget(_ deviceID: String, done: @escaping (Error?) -> Void)
    /// The app came back to the foreground: the package reconnects fast.
    func becameActive()
    /// Subscribes to the package's events until the returned cancel is called.
    func listen(_ each: @escaping (ScannerLibraryEvent) -> Void) -> () -> Void
}

/// The package's checks: holders under its minimum age, and expired
/// documents, fail validation with an issue code. The duplicate window is
/// left as the package delivers it.
struct ScannerPolicy {
    var checksAge: Bool
    var checksExpiry: Bool
}

struct ScannerConnection {
    var state: String
    var deviceID: String?
}

/// The package's two feedback kinds on the scanner (a beep and a vibration).
enum ScannerFeedback {
    case success, error
}

/// One event of the package, reduced to what the gene may receive.
enum ScannerLibraryEvent {
    case result(ScannerResult)
    case duplicate(ScannerResult)
    case connection(String)
    case battery(Int)
    /// discovery, pairing steps, reporting and warnings: not passed on
    case unpassed
}

/// A scan's result: its kind, the holder's kept fields when the document
/// was read, and the codes of its issues (errors first, then warnings).
struct ScannerResult {
    enum Kind: String {
        case read, failedRead, failedValidation
    }
    var kind: Kind
    var holder: ScannerHolder?
    var issueCodes: [String]
}

struct ScannerHolder {
    var fullName: String
    var dateOfBirth: String // ISO, YYYY-MM-DD
    var expirationDate: String?
    var isOver21: Bool
    var isExpired: Bool?
}

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

    init(name: String, scanner: BluetoothIDScanner) {
        self.name = name
        self.scanner = scanner
    }

    deinit {
        stateListener?()
        scanListener?()
        if let foreground { NotificationCenter.default.removeObserver(foreground) }
    }

    /// The scanner a customer build links: the binding's class, registered
    /// with the Objective-C runtime under this name. Nil in a build without it.
    static func linked(name: String) -> IDScannerAdapter? {
        guard !name.isEmpty,
              let type = NSClassFromString("InspoBluetoothIDScanner") as? BluetoothIDScanner.Type else { return nil }
        return IDScannerAdapter(name: name, scanner: type.init())
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
            var value: [String: Any] = ["kind": "state", "state": scanner.connection.state]
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
        each(["kind": "state", "state": scanner.connection.state]) // where the stream begins
        return { [weak self] in
            guard let self else { return }
            self.sinks.removeValue(forKey: key)
            if self.sinks.isEmpty {
                // the page has gone: nothing is listening, nothing is read
                self.stateListener?()
                self.stateListener = nil
                self.stopReading()
            }
        }
    }

    private func stopReading() {
        scanListener?()
        scanListener = nil
    }

    private func send(_ event: ScannerLibraryEvent) {
        guard let value = Self.flat(event) else { return }
        sinks.values.forEach { $0(value) }
    }

    // MARK: the flat shape

    /// An event as the gene receives it: top-level fields only, a kind first.
    static func flat(_ event: ScannerLibraryEvent) -> [String: Any]? {
        switch event {
        case .result(let result):
            return flat(result)
        case .duplicate:
            return ["kind": "duplicate"]
        case .connection(let state):
            return ["kind": "state", "state": state]
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

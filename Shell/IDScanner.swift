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
//           start-pairing  starts pairing a scanner this phone has never
//                          used; data {venue, door, doorName}: where, kept
//                          with the pairing on the phone; answers at once
//                          with the pairing's step, as the stream tells it
//           stop-pairing   stops the pairing that runs
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
//   { kind: "pairing", step, reason }  a pairing's step: looking, connecting,
//                                      confirm (the person scans any barcode
//                                      with the scanner in their hand),
//                                      paired, or failed, with the reason:
//                                      none-found, not-connected,
//                                      not-confirmed, stopped, bluetooth-off,
//                                      bluetooth-not-allowed
//
// A first pairing (owner, 2026-10-02: "Nearest scanner, confirm by scan")
// shows the person no list: the adapter listens for a short window from the
// first scanner it hears, connects the one with the strongest signal, and
// the person's scan with the scanner in their hand is what proves the pick.
// A wrong pick is never confirmed: it fails in its time and is forgotten.
// A call must answer in 30 seconds and a pairing takes up to a minute, so
// start-pairing answers at once and the steps come on the stream.
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
    /// The pairing that runs, if one does.
    private var pairing: Pairing?
    private var pairings = 0

    /// A pairing's times, in seconds: how long it looks before none is
    /// found; how long it listens, from the first scanner heard, before it
    /// picks the strongest; how long the pick may take to connect; how long
    /// the person has to scan. Together under the package's own minute.
    static let lookingLimit: TimeInterval = 15
    static let listeningWindow: TimeInterval = 3
    static let connectingLimit: TimeInterval = 10
    static let confirmLimit: TimeInterval = 30

    /// Runs work after some seconds, unless the returned cancel is called
    /// first. A check passes the time itself.
    static let onMain: (TimeInterval, @escaping () -> Void) -> () -> Void = { seconds, work in
        let item = DispatchWorkItem(block: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
        return { item.cancel() }
    }
    var wait = IDScannerAdapter.onMain

    init(name: String, scanner: BluetoothIDScanner) {
        self.name = name
        self.scanner = scanner
    }

    deinit {
        stateListener?()
        scanListener?()
        pairing?.listener?()
        pairing?.limit?()
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
        case "start-pairing":
            if let pairing {
                // one pairing at a time: the one that runs goes on
                answer(.success(Self.flat(pairing: pairing.step)))
                return
            }
            answer(.success(Self.flat(pairing: "looking")))
            startPairing(Self.place(data))
        case "stop-pairing":
            failPairing("stopped")
            answer(.success([:]))
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
        if let pairing { each(Self.flat(pairing: pairing.step)) } // and a pairing that runs
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

    // MARK: a first pairing

    /// A pairing that runs: its step, the scanners heard while it looks and
    /// the one picked.
    private struct Pairing {
        let run: Int
        var step = "looking"
        /// each scanner's latest signal, and the scanners in the order heard
        var signals: [String: Int] = [:]
        var heard: [String] = []
        var picked: String?
        /// the scanners paired before it began: none of them is forgotten
        /// when it fails
        let known: Set<String>
        var listener: (() -> Void)?
        /// the step's time limit; while it looks and has heard a scanner,
        /// the listening window
        var limit: (() -> Void)?
    }

    private func startPairing(_ place: ScannerPlace) {
        pairings += 1
        let run = pairings
        var begun = Pairing(run: run, known: Set(scanner.pairedDeviceIDs))
        begun.listener = scanner.listen { [weak self] event in
            switch event {
            case .found(let deviceID, let signal): self?.heard(deviceID, signal, run)
            case .confirming: self?.confirming(run)
            default: break
            }
        }
        begun.limit = wait(Self.lookingLimit) { [weak self] in self?.failPairing("none-found", run) }
        pairing = begun
        sendPairing("looking")
        scanner.pair(place) { [weak self] failure in self?.pairingEnded(failure, run) }
    }

    /// A scanner heard while the pairing looks: its latest signal is kept,
    /// and the first scanner heard starts the listening window.
    private func heard(_ deviceID: String, _ signal: Int, _ run: Int) {
        guard var now = pairing, now.run == run, now.step == "looking" else { return }
        if now.signals[deviceID] == nil {
            now.heard.append(deviceID)
            if now.heard.count == 1 {
                now.limit?()
                now.limit = wait(Self.listeningWindow) { [weak self] in self?.pick(run) }
            }
        }
        now.signals[deviceID] = signal
        pairing = now
    }

    /// The window is over: the scanner with the strongest signal is
    /// connected, the first heard of two equally strong.
    private func pick(_ run: Int) {
        guard var now = pairing, now.run == run, now.step == "looking",
              var nearest = now.heard.first else { return }
        for id in now.heard where now.signals[id, default: .min] > now.signals[nearest, default: .min] {
            nearest = id
        }
        now.picked = nearest
        now.step = "connecting"
        now.limit = wait(Self.connectingLimit) { [weak self] in self?.failPairing("not-connected", run) }
        pairing = now
        sendPairing("connecting")
        scanner.connect(nearest) { [weak self] error in
            if error != nil { self?.failPairing("not-connected", run) }
        }
    }

    /// The pick is connected, and the package waits for the person's scan.
    /// The limit runs until the package says the scanner is paired.
    private func confirming(_ run: Int) {
        guard var now = pairing, now.run == run, now.step == "connecting" else { return }
        now.limit?()
        now.step = "confirm"
        now.limit = wait(Self.confirmLimit) { [weak self] in self?.failPairing("not-confirmed", run) }
        pairing = now
        sendPairing("confirm")
    }

    /// The package's own end of the pairing: paired, or why it stopped.
    private func pairingEnded(_ failure: ScannerPairingFailure?, _ run: Int) {
        guard let now = pairing, now.run == run else { return }
        switch failure {
        case nil:
            endPairing()
            sendPairing("paired")
        case .bluetoothOff:
            failPairing("bluetooth-off", run)
        case .bluetoothNotAllowed:
            failPairing("bluetooth-not-allowed", run)
        case .stopped:
            failPairing(Self.reason(stoppedAt: now.step), run)
        }
    }

    /// Why a pairing the package gave up failed, by the step it had reached.
    static func reason(stoppedAt step: String) -> String {
        switch step {
        case "looking": return "none-found"
        case "connecting": return "not-connected"
        default: return "not-confirmed"
        }
    }

    /// Ends the pairing that runs as failed, with a reason the gene can act
    /// on. The package's pairing and its looking are stopped, and a scanner
    /// picked for it is forgotten unless it was paired before: the phone is
    /// not left connected to a scanner nobody confirmed.
    private func failPairing(_ reason: String, _ run: Int? = nil) {
        guard let now = pairing, run == nil || now.run == run else { return }
        endPairing()
        scanner.stopPairing()
        if let picked = now.picked, !now.known.contains(picked) {
            scanner.forget(picked) { _ in }
        }
        sendPairing("failed", reason: reason)
    }

    private func endPairing() {
        pairing?.listener?()
        pairing?.limit?()
        pairing = nil
    }

    private func sendPairing(_ step: String, reason: String? = nil) {
        let value = Self.flat(pairing: step, reason: reason)
        sinks.values.forEach { $0(value) }
    }

    /// Where the gene says the scanner is paired; what it does not say is
    /// empty. The phone is the shell's to say: iOS's id of this phone for
    /// the app's maker.
    static func place(_ data: Any?) -> ScannerPlace {
        let given = data as? [String: Any] ?? [:]
        var phone = ""
        #if os(iOS)
        phone = UIDevice.current.identifierForVendor?.uuidString ?? ""
        #endif
        return ScannerPlace(venue: given["venue"] as? String ?? "", door: given["door"] as? String ?? "",
                            doorName: given["doorName"] as? String ?? "", phone: phone)
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
        case .found, .confirming, .unpassed:
            // a pairing's events reach the gene as its steps
            return nil
        }
    }

    static func flat(pairing step: String, reason: String? = nil) -> [String: Any] {
        var value: [String: Any] = ["kind": "pairing", "step": step]
        if let reason { value["reason"] = reason }
        return value
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

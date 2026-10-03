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
//   calls   state          at once, never waiting for a connection:
//                          { kind: "state", state, battery, paired, reason }
//                          the connection's state; the battery's percent,
//                          once the scanner has said it; paired, 1 when a
//                          scanner is paired with this phone and 0 when
//                          none is (a number); and reason, why a scanner
//                          is not connected (below)
//           feedback       data "accept" | "deny" | "error" (or {pattern: ...})
//           start-reading  results and duplicates start reaching the stream
//           stop-reading   they stop
//           reconnect      connects the paired scanner again, and answers
//                          when it is connected, however long that takes
//                          (a gene gives the call its time limit); with
//                          data {wait: 0} it answers at once with the
//                          state it moved to, in the state call's shape,
//                          and the connection comes on the stream
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
//   { kind: "state", state, reason }   a real connection change, at once:
//                                      idle, scanning, connecting, connected,
//                                      reconnecting, disconnected; the
//                                      package's reading during each scan is
//                                      held back (owner, 2026-10-01: "Hold
//                                      'reading' back"); and again when only
//                                      the reason has changed (Bluetooth
//                                      switched off or back on while the
//                                      scanner was away)
//   { kind: "battery", battery }       the percent
//   { kind: "warning", warning }       keyboard-mode: the scanner is set to
//                                      type as a keyboard and cannot be
//                                      connected until it is set back;
//                                      low-battery
//   { kind: "pairing", step, reason }  a pairing's step: looking, connecting,
//                                      confirm (the person scans any barcode
//                                      with the scanner in their hand),
//                                      paired, or failed, with the reason:
//                                      none-found, not-connected,
//                                      not-confirmed, stopped, bluetooth-off,
//                                      bluetooth-not-allowed; or, refused
//                                      at once because a scanner is
//                                      connected, already-connected
//
// A paired scanner that is away (Q011). The phone waits for a paired
// scanner with no time limit and connects it when it is heard again; the
// package's state while it waits is connecting, the same as while a first
// pairing connects its pick. So outside a pairing the adapter tells a paired
// scanner's connecting as reconnecting: the scanner is away, and comes back
// by itself. connecting is then only a first pairing's connection being
// made. The reason comes with a state of disconnected or reconnecting, and
// with idle when a scanner is paired: bluetooth-off, bluetooth-not-allowed
// (Bluetooth as the binding reads it now), out-of-range (the package said
// the link dropped, and has not connected since), switched-off (a package
// that can tell it; none does yet), else unknown. When Bluetooth comes
// back on, the adapter asks for the paired scanner again, since Bluetooth
// going off ends the phone's wait without a word.
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
    /// The package's listeners: its connection, Bluetooth, battery and
    /// warnings from first use on (so the adapter knows why a scanner is
    /// away whether or not a stream is open), and results while reading.
    private var watching: (() -> Void)?
    private var scanListener: (() -> Void)?
    private var foreground: NSObjectProtocol?
    /// The last state the streams heard, and its reason, so a held-back
    /// reading never shows as a change.
    private var heardState: String?
    private var heardReason: String?
    /// Why the scanner was last lost, as the package said it: kept while
    /// the package waits for it, until it is connected again or forgotten.
    private var lost: ScannerAway?
    /// The connections the adapter asked of the paired scanner that have
    /// been answered neither way, and the run they belong to (a forget
    /// starts a new run: an answer from before it counts for nothing).
    private var asks = 0
    private var asksRun = 0
    /// Bluetooth as the binding last said it, so its coming back on is
    /// told from its first word.
    private var bluetoothWas = ScannerBluetooth.unknown
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
        watching?()
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
                watching = scanner.listen { [weak self] in self?.heard($0) }
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
            answer(.success(stateAnswer()))
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
            if call == "forget" {
                lost = nil
                asks = 0
                asksRun += 1
                scanner.forget(id) { [weak self] error in
                    done(error)
                    self?.tellState()
                }
                return
            }
            if Self.waits(data) {
                // as ever: the answer is the connection, however long the
                // scanner is away
                ask(id, done: done)
                return
            }
            // at once: with Bluetooth off or not allowed nothing can be
            // asked (the scanner is asked for when Bluetooth is back); a
            // scanner that is connected needs nothing
            let bluetooth = scanner.bluetooth
            if shownNow() != "connected", bluetooth != .off, bluetooth != .notAllowed {
                ask(id)
            }
            answer(.success(stateAnswer()))
        case "start-pairing":
            if let pairing {
                // one pairing at a time: the one that runs goes on
                answer(.success(Self.flat(pairing: pairing.step)))
                return
            }
            // a scanner that is connected is never dropped by a pairing
            // (owner, 2026-10-02: "The shell refuses it, with a reason"):
            // nothing starts, and the call and the stream say failed,
            // already-connected. To change scanners: forget, then pair.
            if !scanner.pairsWhileConnected, Self.shown(scanner.connection.state) == "connected" {
                answer(.success(Self.flat(pairing: "failed", reason: "already-connected")))
                sendPairing("failed", reason: "already-connected")
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

    /// Whether a reconnect's answer waits for the connection. It does, as
    /// it always has, unless the gene's data says {wait: 0}.
    static func waits(_ data: Any?) -> Bool {
        guard let wait = (data as? [String: Any])?["wait"] as? NSNumber else { return true }
        return wait.boolValue
    }

    // MARK: the connection's state, and why a scanner is not connected

    private var paired: Bool { !scanner.pairedDeviceIDs.isEmpty }

    /// The connection's state as the gene hears it now. Outside a pairing,
    /// a paired scanner being connected is a scanner waited for: reconnecting.
    private func shownNow() -> String {
        let state = Self.shown(scanner.connection.state)
        guard state != "connected", pairing == nil, paired else { return state }
        return state == "connecting" || asks > 0 ? "reconnecting" : state
    }

    /// Why the scanner is not connected, for a state that says it is not:
    /// Bluetooth as it is now first, then what the package said when the
    /// scanner was lost.
    private func reason(_ state: String) -> String? {
        guard state == "disconnected" || state == "reconnecting" || (state == "idle" && paired) else { return nil }
        let bluetooth = scanner.bluetooth
        switch bluetooth {
        case .off: return "bluetooth-off"
        case .notAllowed: return "bluetooth-not-allowed"
        case .on, .unknown: break
        }
        switch lost ?? scanner.connection.away {
        case .outOfRange: return "out-of-range"
        case .switchedOff: return "switched-off"
        // Bluetooth has come back on since: the scanner is still not there
        case .bluetoothOff: return bluetooth == .on ? "unknown" : "bluetooth-off"
        case .bluetoothNotAllowed: return bluetooth == .on ? "unknown" : "bluetooth-not-allowed"
        case .unknown, nil: return "unknown"
        }
    }

    /// The state call's answer, and a reconnect's that does not wait.
    private func stateAnswer() -> [String: Any] {
        let state = shownNow()
        var value = Self.flat(state: state, reason: reason(state))
        value["paired"] = paired ? 1 : 0
        if let battery = scanner.batteryPercent { value["battery"] = battery }
        return value
    }

    /// Asks the package for the paired scanner. The package answers when it
    /// is connected or cannot be; until then the scanner is waited for.
    private func ask(_ id: String, done: ((Error?) -> Void)? = nil) {
        let run = asksRun
        asks += 1
        scanner.connect(id) { [weak self] error in
            if let self, self.asksRun == run { self.asks -= 1 }
            done?(error)
            self?.tellState()
        }
        tellState()
    }

    /// Bluetooth is back on: the paired scanner is asked for again, since
    /// Bluetooth going off ended the phone's wait for it.
    private func askAgain() {
        guard pairing == nil, Self.shown(scanner.connection.state) != "connected" else { return }
        let known = scanner.pairedDeviceIDs
        guard let id = known.first(where: { $0 == scanner.connection.deviceID }) ?? known.first else { return }
        ask(id)
    }

    /// What the package says of its connection, Bluetooth, battery and
    /// warnings, from first use on.
    private func heard(_ event: ScannerLibraryEvent) {
        switch event {
        case .connection(let state, let away):
            if Self.shown(state) == "connected" {
                lost = nil
            } else if let away {
                lost = away
            }
            tellState()
        case .bluetooth(let now):
            let was = bluetoothWas
            bluetoothWas = now
            if now == .on, was == .off || was == .notAllowed { askAgain() }
            tellState()
        case .battery, .warning:
            send(event)
        default:
            break
        }
    }

    /// Tells the streams the connection's state when it, or why the scanner
    /// is not connected, is not what they last heard: only a real change
    /// (reading is connected, and a scan's connected after it is no change).
    private func tellState() {
        guard !sinks.isEmpty else { return }
        let state = shownNow()
        let why = reason(state)
        guard state != heardState || why != heardReason else { return }
        heardState = state
        heardReason = why
        let value = Self.flat(state: state, reason: why)
        sinks.values.forEach { $0(value) }
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
        let now = shownNow()
        heardState = now
        heardReason = reason(now)
        each(Self.flat(state: now, reason: heardReason)) // where the stream begins
        if let pairing { each(Self.flat(pairing: pairing.step)) } // and a pairing that runs
        return { [weak self] in
            guard let self else { return }
            self.sinks.removeValue(forKey: key)
            if self.sinks.isEmpty {
                // the page has gone: nothing is listening, nothing is read
                self.heardState = nil
                self.heardReason = nil
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
        case .battery(let percent):
            return ["kind": "battery", "battery": percent]
        case .warning(let warning):
            return ["kind": "warning", "warning": warning == .keyboardMode ? "keyboard-mode" : "low-battery"]
        case .connection, .bluetooth:
            // told as the state, when it or its reason changes (tellState)
            return nil
        case .found, .confirming, .unpassed:
            // a pairing's events reach the gene as its steps
            return nil
        }
    }

    static func flat(state: String, reason: String?) -> [String: Any] {
        var value: [String: Any] = ["kind": "state", "state": state]
        if let reason { value["reason"] = reason }
        return value
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

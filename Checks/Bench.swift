// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

// What the checks of the Bluetooth ID scanner's adapter share (Checks/pairing,
// Checks/reader): a clock the check moves, a scanner that only records what
// it was asked and says what the check has it say, and a bench that holds an
// adapter over a scanner and what its stream heard.

import Foundation
import IDScannerSurface

/// A clock the check moves: work waits until its time is passed.
final class Clock {
    private var now = 0.0
    private var count = 0
    private var waiting: [(at: Double, id: Int, work: () -> Void)] = []

    func wait(_ seconds: TimeInterval, _ work: @escaping () -> Void) -> () -> Void {
        count += 1
        let id = count
        waiting.append((now + seconds, id, work))
        return { [weak self] in self?.waiting.removeAll { $0.id == id } }
    }

    func pass(_ seconds: Double) {
        let end = now + seconds
        while let next = waiting.filter({ $0.at <= end }).min(by: { ($0.at, $0.id) < ($1.at, $1.id) }) {
            waiting.removeAll { $0.id == next.id }
            now = next.at
            next.work()
        }
        now = end
    }
}

/// A scanner that only records what it was asked, and says what the check
/// has it say.
final class RecordedScanner: BluetoothIDScanner {
    var asked: [String] = []
    var paired: [String] = []
    var state = "idle"
    var away: ScannerAway?
    var deviceID: String?
    var bluetooth = ScannerBluetooth.unknown
    var battery: Int?
    var pairDone: ((ScannerPairingFailure?) -> Void)?
    /// the last connect's answer, and every connect's that waits
    var connectDone: ((Error?) -> Void)?
    var connectDones: [(Error?) -> Void] = []
    private var listeners: [UUID: (ScannerLibraryEvent) -> Void] = [:]

    func configure(_ policy: ScannerPolicy) throws {}
    var connection: ScannerConnection { ScannerConnection(state: state, deviceID: deviceID, away: away) }
    var batteryPercent: Int? { battery }
    var pairedDeviceIDs: [String] { paired }
    func feedback(_ kind: ScannerFeedback, done: @escaping (Error?) -> Void) { done(nil) }
    func connect(_ deviceID: String, done: @escaping (Error?) -> Void) {
        asked.append("connect \(deviceID)")
        connectDone = done
        connectDones.append(done)
    }
    func forget(_ deviceID: String, done: @escaping (Error?) -> Void) {
        asked.append("forget \(deviceID)")
        paired.removeAll { $0 == deviceID }
        done(nil)
    }
    func becameActive() {}
    func listen(_ each: @escaping (ScannerLibraryEvent) -> Void) -> () -> Void {
        let key = UUID()
        listeners[key] = each
        return { [weak self] in self?.listeners.removeValue(forKey: key) }
    }
    func pair(_ place: ScannerPlace, done: @escaping (ScannerPairingFailure?) -> Void) {
        asked.append("pair \(place.venue)/\(place.door)/\(place.doorName)/\(place.phone)")
        pairDone = done
    }
    func stopPairing() { asked.append("stop") }

    func say(_ event: ScannerLibraryEvent) {
        switch event {
        case .connection(let now, let why): (state, away) = (now, why)
        case .bluetooth(let now): bluetooth = now
        case .battery(let percent): battery = percent
        default: break
        }
        listeners.values.forEach { $0(event) }
    }
    func hear(_ deviceID: String, _ signal: Int) { say(.found(deviceID: deviceID, signal: signal)) }
    /// Every connect that waits is answered, as the package answers them together.
    func answerConnects(_ error: Error? = nil) {
        let dones = connectDones
        connectDones = []
        dones.forEach { $0(error) }
    }
}

struct Refused: Error {}

/// An event or an answer in a few words: its kind, its step or state, its reason.
func words(_ value: [String: Any]) -> String {
    var parts = [value["kind"], value["step"] ?? value["state"] ?? value["result"], value["reason"]].compactMap { $0 as? String }
    let others = value.keys.filter { !["kind", "step", "state", "result", "reason"].contains($0) }.sorted()
    if !others.isEmpty { parts.append("+" + others.joined(separator: "+")) }
    return parts.isEmpty ? "{}" : parts.joined(separator: " ")
}

/// An adapter over a scanner, with the clock, and what its stream heard.
final class Bench {
    let clock = Clock()
    let adapter: IDScannerAdapter
    var heard: [String] = []
    /// every call's answer, whenever it came
    var answered: [String] = []
    /// how an event or an answer is written down
    let written: ([String: Any]) -> String
    private var stop: (() -> Void)?

    init(_ scanner: BluetoothIDScanner, stream: Bool = true, written: @escaping ([String: Any]) -> String = words) {
        self.written = written
        adapter = IDScannerAdapter(name: "id-reader", scanner: scanner)
        adapter.wait = clock.wait
        if stream { open() }
    }

    func open() {
        stop = adapter.listen("events", data: nil,
            each: { [weak self] value in
                guard let self else { return }
                self.heard.append(self.written(value))
            },
            failed: { [weak self] in self?.heard.append("failed: \($0.message)") })
    }

    func call(_ name: String, _ data: Any? = nil) -> String {
        var said = "no answer"
        adapter.call(name, data: data) { result in
            switch result {
            case .success(let value): said = self.written(value)
            case .failure(let err): said = "error: \(err.message)"
            }
            self.answered.append(said)
        }
        return said
    }
}

func recorded(paired: [String] = [], stream: Bool = true) -> (RecordedScanner, Bench) {
    let scanner = RecordedScanner()
    scanner.paired = paired
    return (scanner, Bench(scanner, stream: stream))
}

/// A pairing brought to connecting: A alone was heard and picked.
func connecting(paired: [String] = []) -> (RecordedScanner, Bench) {
    let (scanner, bench) = recorded(paired: paired)
    _ = bench.call("start-pairing")
    scanner.hear("A", -60)
    bench.clock.pass(3)
    return (scanner, bench)
}

/// And on to the wait for the confirming scan.
func confirming(paired: [String] = []) -> (RecordedScanner, Bench) {
    let (scanner, bench) = connecting(paired: paired)
    scanner.connectDone?(nil)
    scanner.say(.confirming)
    return (scanner, bench)
}

func last(_ list: [String], _ count: Int) -> [String] { Array(list.suffix(count)) }

var passed = 0, failed = 0
func check(_ name: String, _ got: [String], _ want: [String]) {
    if got == want { passed += 1 } else { failed += 1; print("FAIL \(name):\n  got  \(got)\n  want \(want)") }
}

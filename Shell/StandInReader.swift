// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

import AVFoundation
import UIKit

// A stand-in for the Bluetooth ID scanner, for tests without the device
// (owner, 2026-09-30, E42: "Shell stand-in + Go tests"): a build whose
// INSPO_NATIVE_STAND_IN names the library (id-reader) carries this in the
// scanner's place, behind the same surface (BluetoothIDScanner) and the
// same adapter (IDScannerAdapter, E47), so its answers take the shape the
// device's do and the gene's records run unchanged. Its calls succeed (the
// state is connected; a feedback plays a haptic on the phone), and each
// press of either volume button plays the next event of the script to the
// stream, in turn (owner: "simulate scans using maybe the side button on
// the phone"; iOS lets an app hear the volume buttons, never the side
// button). The script is made-up people only, never a real ID; its dates
// are counted from today, so the ages and expiries never go stale.

final class StandInReader: NSObject, BluetoothIDScanner {
    private var next = 0
    private var listeners: [UUID: (ScannerLibraryEvent) -> Void] = [:]
    private var observation: NSKeyValueObservation?
    private var battery = 90

    /// The events a press plays, in turn: every kind the stream carries,
    /// and a failed validation for each issue the policy checks.
    static func script(today: Date = Date()) -> [ScannerLibraryEvent] {
        let calendar = Calendar(identifier: .gregorian)
        let format = DateFormatter()
        format.calendar = calendar
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd"
        func holder(_ name: String, age: Int, expiresIn years: Int) -> ScannerHolder {
            let born = calendar.date(byAdding: DateComponents(year: -age, day: -30), to: today) ?? today
            let expires = calendar.date(byAdding: DateComponents(year: years, day: years < 0 ? -30 : 0), to: today) ?? today
            return ScannerHolder(fullName: name, dateOfBirth: format.string(from: born),
                                 expirationDate: format.string(from: expires),
                                 isOver21: age >= 21, isExpired: years < 0)
        }
        let over21 = holder("Test Person One", age: 36, expiresIn: 4)
        return [
            .result(ScannerResult(kind: .read, holder: over21, issueCodes: [])),
            .duplicate(ScannerResult(kind: .read, holder: over21, issueCodes: [])),
            .result(ScannerResult(kind: .failedRead, holder: nil, issueCodes: ["incomplete"])),
            .result(ScannerResult(kind: .failedValidation, holder: holder("Test Person Two", age: 18, expiresIn: 5),
                                  issueCodes: ["UNDER_MINIMUM_AGE"])),
            .result(ScannerResult(kind: .failedValidation, holder: holder("Test Person Three", age: 41, expiresIn: -1),
                                  issueCodes: ["EXPIRED"])),
            .result(ScannerResult(kind: .failedValidation, holder: nil, issueCodes: ["NOT_AAMVA"])),
            .battery(15),
            .connection("reconnecting"),
        ]
    }

    override init() {
        super.init()
    }

    /// The stand-in the build names, in the adapter, if any.
    static func fromBuild() -> NativeLibrary? {
        guard let name = Bundle.main.object(forInfoDictionaryKey: "InspoNativeStandIn") as? String,
              !name.isEmpty else { return nil }
        return IDScannerAdapter(name: name, scanner: StandInReader())
    }

    // MARK: BluetoothIDScanner

    func configure(_ policy: ScannerPolicy) throws {}

    private(set) var connection = ScannerConnection(state: "connected", deviceID: "stand-in")

    var batteryPercent: Int? { battery }

    var pairedDeviceIDs: [String] { ["stand-in"] }

    func feedback(_ kind: ScannerFeedback, done: @escaping (Error?) -> Void) {
        UINotificationFeedbackGenerator().notificationOccurred(kind == .success ? .success : .error)
        done(nil)
    }

    func connect(_ deviceID: String, done: @escaping (Error?) -> Void) {
        emit(.connection("connected"))
        done(nil)
    }

    func forget(_ deviceID: String, done: @escaping (Error?) -> Void) {
        done(nil)
    }

    func becameActive() {}

    func listen(_ each: @escaping (ScannerLibraryEvent) -> Void) -> () -> Void {
        let key = UUID()
        listeners[key] = each
        followVolume()
        return { [weak self] in
            self?.listeners.removeValue(forKey: key)
            if self?.listeners.isEmpty == true {
                self?.observation = nil
            }
        }
    }

    // MARK: the volume buttons

    /// Either volume button plays the next event to every listener.
    private func followVolume() {
        guard observation == nil else { return }
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.ambient, options: [.mixWithOthers])
        try? audio.setActive(true)
        observation = audio.observe(\.outputVolume, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.press() }
        }
    }

    /// Plays the script's next event; the stream's own test hook too.
    func press() {
        let script = Self.script()
        let event = script[next % script.count]
        next += 1
        emit(event)
        if case .connection = event {
            // a dropped link comes back, as the package's reconnection does
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.emit(.connection("connected"))
            }
        }
    }

    private func emit(_ event: ScannerLibraryEvent) {
        switch event {
        case .connection(let state): connection.state = state
        case .battery(let percent): battery = percent
        default: break
        }
        listeners.values.forEach { $0(event) }
    }
}

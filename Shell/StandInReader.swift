// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

import Foundation
import IDScannerSurface
#if os(iOS)
import AVFoundation
import UIKit
#endif

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
//
// A first pairing plays as the device's does, with the same button: two
// made-up scanners are heard a second after it starts, the far one first,
// so the adapter's pick of the nearest shows; the pick connects; and while
// the pairing waits for the confirming scan, the next press is that scan:
// it plays no event, the script does not move, and the scanner is paired.
// No press, and the adapter's time limit fails the pairing. The stand-in
// forgets nothing: it stays paired and connected whatever a pairing does,
// so the flows that need no pairing run as they did. On a Mac (the check,
// scripts/check-pairing.sh) it has no buttons and no haptic: press() is called.

final class StandInReader: NSObject, BluetoothIDScanner {
    private var next = 0
    private var listeners: [UUID: (ScannerLibraryEvent) -> Void] = [:]
    private var observation: NSKeyValueObservation?
    private var battery = 90
    /// A pairing that runs: its done, the scanner the adapter picked once
    /// it waits for the confirming scan, and the step that is on its way.
    private var pairingDone: ((ScannerPairingFailure?) -> Void)?
    private var confirmingWith: String?
    private var pending: (() -> Void)?
    var wait = IDScannerAdapter.onMain

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
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(kind == .success ? .success : .error)
        #endif
        done(nil)
    }

    func connect(_ deviceID: String, done: @escaping (Error?) -> Void) {
        guard pairingDone != nil else {
            emit(.connection("connected"))
            done(nil)
            return
        }
        // a pairing's pick: the link, then the wait for the confirming scan
        emit(.connection("connecting"))
        pending = wait(0.8) { [weak self] in
            self?.emit(.connection("connected"))
            done(nil)
            self?.confirmingWith = deviceID
            self?.emit(.confirming)
        }
    }

    func forget(_ deviceID: String, done: @escaping (Error?) -> Void) {
        done(nil)
    }

    func becameActive() {}

    func pair(_ place: ScannerPlace, done: @escaping (ScannerPairingFailure?) -> Void) {
        stopPairing()
        pairingDone = done
        pending = wait(1) { [weak self] in
            self?.emit(.found(deviceID: "stand-in-far", signal: -72))
            self?.emit(.found(deviceID: "stand-in", signal: -48))
        }
    }

    func stopPairing() {
        guard let done = pairingDone else { return }
        pending?()
        pending = nil
        pairingDone = nil
        confirmingWith = nil
        if connection.state != "connected" {
            emit(.connection("connected")) // the link the stand-in always has
        }
        done(.stopped)
    }

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
        #if os(iOS)
        guard observation == nil else { return }
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.ambient, options: [.mixWithOthers])
        try? audio.setActive(true)
        observation = audio.observe(\.outputVolume, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.press() }
        }
        #endif
    }

    /// Plays the script's next event; the stream's own test hook too. While
    /// a pairing waits for the confirming scan, the press is that scan.
    func press() {
        if let picked = confirmingWith, let done = pairingDone {
            // read and discarded, as the package's is; a press confirms
            // only the scanner in the hand, never the far one
            guard picked == "stand-in" else { return }
            confirmingWith = nil
            pending = wait(0.5) { [weak self] in
                self?.pairingDone = nil
                done(nil)
            }
            return
        }
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

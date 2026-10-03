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
// so the flows that need no pairing run as they did. On a Mac (the checks,
// scripts/check-pairing.sh and check-reader.sh) it has no buttons and no
// haptic: press() and play() are called.
//
// A scanner that is away plays too (Q011), by a link to the app, since a
// simulator has no buttons to press: <the app's url scheme>://stand-in/<scene>
// (on a simulator: xcrun simctl openurl booted <scheme>://stand-in/away; on
// a phone: the link, tapped in Notes or Safari). The link is the stand-in's:
// it does not reach the page. The scenes:
//
//   away              the paired scanner goes out of range: the link drops,
//                     and the phone waits for it (as the scanner's package
//                     does, it says reconnecting, then connecting at once).
//                     As the link that opens the app, it plays a phone
//                     opened with its scanner away: paired, idle, nothing
//                     asked of it yet
//   bluetooth-off     Bluetooth is switched off: a connected scanner drops,
//                     and nothing can be connected
//   bluetooth-refused Bluetooth is not allowed for this app
//   back              Bluetooth is on and allowed again and the scanner is
//                     near: a scanner that is waited for connects in under
//                     a second
//   keyboard-mode     the scanner is set to type as a keyboard: the warning,
//                     the link drops, and a connection fails with the
//                     warning again until back
//   low-battery       the battery at 8 percent, and the warning
//   unpaired          no scanner is paired with this phone (a first pairing
//                     pairs the stand-in again)
//   paired            the stand-in as it starts: paired and connected

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
    /// The scenes' state: whether a scanner is paired, Bluetooth, the
    /// scanner out of range or in keyboard mode, the connections that wait
    /// for it, and the connection on its way.
    private var paired = true
    private(set) var bluetooth = ScannerBluetooth.on
    private var away = false
    private var keyboard = false
    private var waiting: [(Error?) -> Void] = []
    private var arriving: (() -> Void)?
    /// Bluetooth went off while the phone waited for the scanner: the wait
    /// has ended without a word, as the phone's does, until a connection is
    /// asked for again.
    private var waitEnded = false
    /// The stand-in this build runs, for the links that play its scenes.
    private static weak var built: StandInReader?

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
            .connection("reconnecting", away: .outOfRange),
        ]
    }

    /// The stand-in the build names, in the adapter, if any.
    static func fromBuild() -> NativeLibrary? {
        guard let name = Bundle.main.object(forInfoDictionaryKey: "InspoNativeStandIn") as? String,
              !name.isEmpty else { return nil }
        let reader = StandInReader()
        built = reader
        return IDScannerAdapter(name: name, scanner: reader)
    }

    /// A link to the app that plays a scene: <scheme>://stand-in/<scene>.
    /// True when the link was the stand-in's, so it does not reach the page.
    static func plays(_ url: URL) -> Bool {
        guard let reader = built, url.host == "stand-in" else { return false }
        reader.play(url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        return true
    }

    // MARK: BluetoothIDScanner

    func configure(_ policy: ScannerPolicy) throws {}

    private(set) var connection = ScannerConnection(state: "connected", deviceID: "stand-in")

    var batteryPercent: Int? { battery }

    var pairedDeviceIDs: [String] { paired ? ["stand-in"] : [] }
    /// The stand-in is always connected and still plays a first pairing.
    var pairsWhileConnected: Bool { true }

    func feedback(_ kind: ScannerFeedback, done: @escaping (Error?) -> Void) {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(kind == .success ? .success : .error)
        #endif
        done(nil)
    }

    func connect(_ deviceID: String, done: @escaping (Error?) -> Void) {
        guard pairingDone != nil else {
            if bluetooth != .on {
                done(StandInError.bluetoothUnavailable)
            } else if keyboard {
                emit(.warning(.keyboardMode))
                done(StandInError.notConnected)
            } else if connection.state == "connected" {
                emit(.connection("connected"))
                done(nil)
            } else {
                // the phone waits for the scanner, with no time limit
                waitEnded = false
                emit(.connection("connecting"))
                waiting.append(done)
                if !away { arrive() }
            }
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

    // MARK: the scenes

    /// Plays a scene (the list is at the top of this file); a name that is
    /// no scene plays nothing.
    func play(_ scene: String) {
        #if DEBUG
        print("stand-in: \(scene)") // a development build says so
        #endif
        switch scene {
        case "away":
            guard paired else { return }
            away = true
            stopArriving()
            if listeners.isEmpty {
                // the app was opened by this link: nothing was connected yet
                connection.state = "idle"
            } else if connection.state == "connected" {
                emit(.connection("reconnecting", away: .outOfRange))
                emit(.connection("connecting"))
            }
        case "bluetooth-off", "bluetooth-refused":
            let off = scene == "bluetooth-off"
            guard bluetooth != (off ? .off : .notAllowed) else { return }
            bluetooth = off ? .off : .notAllowed
            stopArriving()
            if connection.state == "connecting" { waitEnded = true }
            emit(.bluetooth(bluetooth))
            if connection.state == "connected" {
                emit(.connection(off ? "reconnecting" : "disconnected", away: off ? .bluetoothOff : .bluetoothNotAllowed))
            }
        case "back", "paired":
            if scene == "paired" {
                paired = true
                connection.deviceID = "stand-in"
            }
            away = false
            keyboard = false
            if bluetooth != .on {
                bluetooth = .on
                emit(.bluetooth(.on))
                // as the scanner's package does: a link Bluetooth took is asked for again
                if connection.state == "reconnecting" { emit(.connection("connecting")) }
            }
            if scene == "paired", connection.state != "connected", connection.state != "connecting" {
                emit(.connection("connecting"))
            }
            if connection.state == "connecting", !waitEnded { arrive() }
        case "keyboard-mode":
            guard paired else { return }
            keyboard = true
            stopArriving()
            emit(.warning(.keyboardMode))
            if connection.state != "disconnected" { emit(.connection("disconnected", away: .unknown)) }
            answerWaiting(StandInError.notConnected)
        case "low-battery":
            emit(.battery(8))
            emit(.warning(.lowBattery))
        case "unpaired":
            paired = false
            away = false
            keyboard = false
            stopArriving()
            connection.deviceID = nil
            if connection.state != "idle" { emit(.connection("idle")) }
            answerWaiting(StandInError.notConnected)
        default:
            break
        }
    }

    /// The scanner is there: the link is made in under a second, and every
    /// connection that waited for it is answered.
    private func arrive() {
        guard arriving == nil else { return }
        arriving = wait(0.8) { [weak self] in
            self?.arriving = nil
            self?.emit(.connection("connected"))
            self?.answerWaiting(nil)
        }
    }

    private func stopArriving() {
        arriving?()
        arriving = nil
    }

    private func answerWaiting(_ error: Error?) {
        let dones = waiting
        waiting = []
        dones.forEach { $0(error) }
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
        let rest = paired ? "connected" : "idle" // the link the stand-in has while it is paired
        if connection.state != rest {
            emit(.connection(rest))
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
                self?.paired = true
                self?.connection.deviceID = picked
                done(nil)
            }
            return
        }
        // a scanner that is not there scans nothing
        guard paired, !away, !keyboard, bluetooth == .on else { return }
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
        case .connection(let state, let away):
            connection.state = state
            connection.away = state == "connected" ? nil : away ?? connection.away
        case .battery(let percent): battery = percent
        default: break
        }
        listeners.values.forEach { $0(event) }
    }
}

/// Why the stand-in could not connect.
enum StandInError: Error {
    case bluetoothUnavailable, notConnected
}

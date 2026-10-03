// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

// The binding that links a vendor's Bluetooth ID scanner package to the
// shell (E47), as a template. It is not compiled here: this folder is in no
// target, and the package is never in this repository (its terms grant no
// licence to add it). A customer's Xcode workspace holds the shell's
// project beside a Swift package named IDScannerBinding, in the customer's
// lane, whose one source is this file with the vendor module's import added,
// and which depends on the shell's Packages/IDScannerSurface and on the
// vendor's package (README, "The Bluetooth ID scanner"). Xcode builds that
// package in place of the shell's own IDScannerBinding, which links none;
// the build's INSPO_ID_SCANNER names the library, and the shell registers
// IDScannerAdapter over IDScannerBinding.scanner().
//
// The binding only translates types: the vendor's events into
// ScannerLibraryEvent, its scan into ScannerResult (the holder's five kept
// fields and the issue codes, nothing else), its async calls into
// callbacks on the main thread. Every mapping decision is the adapter's:
// in a first pairing the binding passes on each scanner the package hears
// and the adapter picks which to connect.
//
// One thing the package does not say, the binding reads from iOS itself:
// Bluetooth on this phone (BluetoothWatch, below). The package warns when
// Bluetooth goes off or is refused and says nothing when it comes back, and
// a connection it was waiting for when Bluetooth went off is not asked for
// again; with Bluetooth's own word the adapter can tell why a paired scanner
// is not connected, at any moment, and ask for it again when Bluetooth is
// back.

import CoreBluetooth
import Foundation
import IDScannerSurface
// import <the vendor package's module>

/// The scanner this build links.
public enum IDScannerBinding {
    public static func scanner() -> BluetoothIDScanner? { VendorIDScanner() }
}

final class VendorIDScanner: BluetoothIDScanner {
    private let scanner = Scanner.shared
    /// Counts the pairings asked for and stopped, so one that was stopped
    /// while it waited for Bluetooth is not started after all.
    private var pairings = 0
    /// Bluetooth on this phone, and who hears it change.
    private var watch: BluetoothWatch?
    private var listeners: [UUID: (ScannerLibraryEvent) -> Void] = [:]

    /// Age and expiry policy on (the package's minimum age as delivered),
    /// the duplicate window as delivered. Reporting off the phone is never
    /// configured here, so the package keeps its default: off.
    func configure(_ policy: ScannerPolicy) throws {
        var options = scanner.options
        options.minimumAge = policy.checksAge ? (options.minimumAge ?? ScannerOptions().minimumAge) : nil
        options.rejectExpired = policy.checksExpiry
        try scanner.configure(options)
        // Bluetooth is watched from the moment the package first uses it,
        // so iOS asks the person once, for both. A package set to use no
        // Bluetooth (its own simulation) is watched for none.
        if options.usesCoreBluetooth, watch == nil {
            watch = BluetoothWatch { [weak self] now in
                self?.listeners.values.forEach { $0(.bluetooth(now)) }
            }
        }
    }

    var connection: ScannerConnection {
        let status = scanner.connectionStatus
        return ScannerConnection(state: status.state.rawValue, deviceID: status.identity?.peripheralId.uuidString,
                                 away: status.reason.map(Self.away))
    }

    var bluetooth: ScannerBluetooth { watch?.now ?? .unknown }

    var batteryPercent: Int? { scanner.battery?.percent }

    var pairedDeviceIDs: [String] { scanner.pairedScanners().map { $0.identity.peripheralId.uuidString } }

    func feedback(_ kind: ScannerFeedback, done: @escaping (Error?) -> Void) {
        run(done) { try await self.scanner.feedback(kind == .success ? .success : .error) }
    }

    /// The package's connect: it answers when the scanner is connected, and
    /// waits for a paired scanner that is away with no time limit. Like a
    /// pairing (below), it is refused while the package's Bluetooth has not
    /// yet said it is on, so a refusal is tried again for three seconds
    /// unless Bluetooth is known to be off or not allowed.
    func connect(_ deviceID: String, done: @escaping (Error?) -> Void) {
        guard let id = UUID(uuidString: deviceID) else { return done(BindingError.notAScannerID) }
        Task { @MainActor in
            for attempt in 0... {
                do {
                    try await self.scanner.connect(peripheralId: id)
                    return done(nil)
                } catch ScannerError.bluetoothUnavailable where attempt < 6 && self.bluetooth != .off && self.bluetooth != .notAllowed {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                } catch {
                    return done(error)
                }
            }
        }
    }

    func forget(_ deviceID: String, done: @escaping (Error?) -> Void) {
        guard let id = UUID(uuidString: deviceID) else { return done(BindingError.notAScannerID) }
        run(done) { await self.scanner.forget(peripheralId: id) }
    }

    func becameActive() {
        scanner.applicationDidBecomeActive()
    }

    /// The package's whole pairing: it looks, the adapter connects its pick
    /// (connect), the package waits for the confirming scan, configures the
    /// scanner and keeps the pairing with the place. The package refuses a
    /// pairing while its Bluetooth has not yet said it is on (the moment
    /// after it is first configured, and while iOS asks the person), so a
    /// refusal is tried again for three seconds before it is believed.
    func pair(_ place: ScannerPlace, done: @escaping (ScannerPairingFailure?) -> Void) {
        let door = DoorBinding(venueId: place.venue, doorId: place.door, doorName: place.doorName, phoneId: place.phone)
        pairings += 1
        let mine = pairings
        Task { @MainActor in
            for attempt in 0... {
                do {
                    _ = try await self.scanner.startPairing(door: door)
                    return done(nil)
                } catch ScannerError.bluetoothUnavailable where attempt < 6 && !Self.bluetoothRefused {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    guard mine == self.pairings else { return done(.stopped) }
                } catch {
                    return done(Self.failure(error))
                }
            }
        }
    }

    /// The package's cancel leaves its looking on; both are stopped.
    func stopPairing() {
        pairings += 1
        scanner.cancelPairing()
        scanner.stopDiscovery()
    }

    /// The person, or the phone's rules, said no to Bluetooth for this app.
    static var bluetoothRefused: Bool {
        CBCentralManager.authorization == .denied || CBCentralManager.authorization == .restricted
    }

    /// Why the package's pairing threw, in the surface's terms. Its
    /// Bluetooth not being on is not allowed when the person has not said
    /// yes (refused, or still being asked), and off otherwise.
    static func failure(_ error: Error) -> ScannerPairingFailure {
        switch error {
        case ScannerError.unauthorized:
            return .bluetoothNotAllowed
        case ScannerError.bluetoothUnavailable:
            return CBCentralManager.authorization == .allowedAlways ? .bluetoothOff : .bluetoothNotAllowed
        default:
            return .stopped
        }
    }

    func listen(_ each: @escaping (ScannerLibraryEvent) -> Void) -> () -> Void {
        let key = UUID()
        listeners[key] = each
        let token = scanner.addListener { each(Self.event($0)) }
        return { [weak self] in
            token.cancel()
            self?.listeners.removeValue(forKey: key)
        }
    }

    static func event(_ event: ScannerEvent) -> ScannerLibraryEvent {
        switch event {
        case .scanReceived(let scan): return .result(result(scan))
        case .scanDebounced(let scan): return .duplicate(result(scan))
        case .connectionStateChanged(let status): return .connection(status.state.rawValue, away: status.reason.map(away))
        case .batteryChanged(let battery): return .battery(battery.percent)
        case .warning(.hidBondDetected): return .warning(.keyboardMode)
        case .warning(.lowBattery): return .warning(.lowBattery)
        case .deviceFound(let device): return .found(deviceID: device.peripheralId.uuidString, signal: device.rssi)
        case .pairingStep(.confirmByScan): return .confirming
        default: return .unpassed
        }
    }

    /// Why the package says the scanner is not connected, in the surface's
    /// terms. The package tells a dropped link and a connection that timed
    /// out, never a scanner switched off from one out of range; a
    /// disconnection the app asked for, and anything else, is not known.
    static func away(_ reason: DisconnectReason) -> ScannerAway {
        switch reason {
        case .peripheralDropped, .timeout: return .outOfRange
        case .bluetoothOff: return .bluetoothOff
        case .unauthorized: return .bluetoothNotAllowed
        default: return .unknown
        }
    }

    static func result(_ scan: ScanEvent) -> ScannerResult {
        ScannerResult(
            kind: ScannerResult.Kind(rawValue: scan.result.rawValue) ?? .failedRead,
            holder: scan.parsed.map {
                ScannerHolder(fullName: $0.fullName, dateOfBirth: $0.dateOfBirth, expirationDate: $0.expirationDate,
                              isOver21: $0.isOver21, isExpired: $0.isExpired)
            },
            issueCodes: (scan.validation.errors + scan.validation.warnings).map(\.code))
    }

    private func run(_ done: @escaping (Error?) -> Void, _ work: @escaping () async throws -> Void) {
        Task { @MainActor in
            do {
                try await work()
                done(nil)
            } catch {
                done(error)
            }
        }
    }
}

enum BindingError: Error {
    case notAScannerID
}

/// Bluetooth on this phone, from iOS itself: a central of the binding's own
/// that connects nothing and only hears Bluetooth's state. It shows no alert
/// of its own when Bluetooth is off. Its word comes on the main thread.
final class BluetoothWatch: NSObject, CBCentralManagerDelegate {
    private var central: CBCentralManager?
    private let changed: (ScannerBluetooth) -> Void
    private(set) var now = ScannerBluetooth.unknown

    init(changed: @escaping (ScannerBluetooth) -> Void) {
        self.changed = changed
        super.init()
        central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = Self.reading(central.state)
        guard state != now else { return }
        now = state
        changed(state)
    }

    /// Bluetooth's state in the surface's terms; a state iOS has not yet
    /// settled (or a simulator's, which has no Bluetooth) is not known.
    static func reading(_ state: CBManagerState) -> ScannerBluetooth {
        switch state {
        case .poweredOn: return .on
        case .poweredOff: return .off
        case .unauthorized: return .notAllowed
        default: return .unknown
        }
    }
}

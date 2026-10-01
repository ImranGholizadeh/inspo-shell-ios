// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

// The binding that links a vendor's Bluetooth ID scanner package to the
// shell (E47). It is not compiled here: this folder is in no target, and the
// package is never in this repository (its terms grant no licence to add
// it). A customer build compiles this file with the package and sets
// INSPO_ID_SCANNER to the library's name in its urls; the shell then finds
// the class below by its Objective-C name and registers IDScannerAdapter
// over it (Shell/IDScanner.swift). When the package is linked as a Swift
// package rather than compiled into the app, add its import line here.
//
// The binding only translates types: the vendor's events into
// ScannerLibraryEvent, its scan into ScannerResult (the holder's five kept
// fields and the issue codes, nothing else), its async calls into
// callbacks on the main thread. Every mapping decision is the adapter's.

import Foundation

@objc(InspoBluetoothIDScanner)
final class VendorIDScanner: NSObject, BluetoothIDScanner {
    private let scanner = Scanner.shared

    override init() {
        super.init()
    }

    /// Age and expiry policy on (the package's minimum age as delivered),
    /// the duplicate window as delivered. Reporting off the phone is never
    /// configured here, so the package keeps its default: off.
    func configure(_ policy: ScannerPolicy) throws {
        var options = scanner.options
        options.minimumAge = policy.checksAge ? (options.minimumAge ?? ScannerOptions().minimumAge) : nil
        options.rejectExpired = policy.checksExpiry
        try scanner.configure(options)
    }

    var connection: ScannerConnection {
        let status = scanner.connectionStatus
        return ScannerConnection(state: status.state.rawValue, deviceID: status.identity?.peripheralId.uuidString)
    }

    var batteryPercent: Int? { scanner.battery?.percent }

    var pairedDeviceIDs: [String] { scanner.pairedScanners().map { $0.identity.peripheralId.uuidString } }

    func feedback(_ kind: ScannerFeedback, done: @escaping (Error?) -> Void) {
        run(done) { try await self.scanner.feedback(kind == .success ? .success : .error) }
    }

    func connect(_ deviceID: String, done: @escaping (Error?) -> Void) {
        guard let id = UUID(uuidString: deviceID) else { return done(NativeError(message: "not a scanner id")) }
        run(done) { try await self.scanner.connect(peripheralId: id) }
    }

    func forget(_ deviceID: String, done: @escaping (Error?) -> Void) {
        guard let id = UUID(uuidString: deviceID) else { return done(NativeError(message: "not a scanner id")) }
        run(done) { await self.scanner.forget(peripheralId: id) }
    }

    func becameActive() {
        scanner.applicationDidBecomeActive()
    }

    func listen(_ each: @escaping (ScannerLibraryEvent) -> Void) -> () -> Void {
        let token = scanner.addListener { each(Self.event($0)) }
        return { token.cancel() }
    }

    static func event(_ event: ScannerEvent) -> ScannerLibraryEvent {
        switch event {
        case .scanReceived(let scan): return .result(result(scan))
        case .scanDebounced(let scan): return .duplicate(result(scan))
        case .connectionStateChanged(let status): return .connection(status.state.rawValue)
        case .batteryChanged(let battery): return .battery(battery.percent)
        default: return .unpassed
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

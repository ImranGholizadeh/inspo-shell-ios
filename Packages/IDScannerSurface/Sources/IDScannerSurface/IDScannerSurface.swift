// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

// The Bluetooth ID scanner's surface (E47), in plain terms: what the shell's
// adapter needs from a scanner package. A binding conforms the vendor's
// package to it (built in a customer's workspace, never in the shell's
// repository); the shell's stand-in conforms a made-up scanner. Nothing
// beyond these types reaches the adapter: the raw scan, the document's
// number and every other field of a vendor's result have no place here.

/// The scanner's surface the adapter needs. Callbacks come on the main thread.
public protocol BluetoothIDScanner: AnyObject {
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
    /// Starts pairing a scanner this phone has never used. The package looks
    /// for scanners and says each one it hears (.found, again and again
    /// while it looks); the adapter picks one and connects it (connect); the
    /// package then waits for the person to scan any barcode with the
    /// scanner in their hand (.confirming), reads and discards that scan,
    /// and keeps the pairing. done is called once: nil when the scanner is
    /// paired, or why the package stopped. The adapter keeps the time
    /// limits; the package's own stand behind them.
    func pair(_ place: ScannerPlace, done: @escaping (ScannerPairingFailure?) -> Void)
    /// Stops the pairing that runs, and its looking. None runs: nothing happens.
    func stopPairing()
}

/// Where a scanner is paired: the venue and the door as the gene gives
/// them (what it does not give is empty), and this phone, as the shell
/// knows it. The package keeps it with the pairing, on the phone.
public struct ScannerPlace {
    public var venue: String
    public var door: String
    public var doorName: String
    public var phone: String

    public init(venue: String, door: String, doorName: String, phone: String) {
        self.venue = venue
        self.door = door
        self.doorName = doorName
        self.phone = phone
    }
}

/// Why a pairing did not finish, as far as the package can say.
public enum ScannerPairingFailure {
    case bluetoothOff, bluetoothNotAllowed
    /// anything else (it gave up, or was stopped): the adapter names it
    /// by the step the pairing had reached
    case stopped
}

/// The package's checks: holders under its minimum age, and expired
/// documents, fail validation with an issue code. The duplicate window is
/// left as the package delivers it.
public struct ScannerPolicy {
    public var checksAge: Bool
    public var checksExpiry: Bool

    public init(checksAge: Bool, checksExpiry: Bool) {
        self.checksAge = checksAge
        self.checksExpiry = checksExpiry
    }
}

public struct ScannerConnection {
    public var state: String
    public var deviceID: String?

    public init(state: String, deviceID: String?) {
        self.state = state
        self.deviceID = deviceID
    }
}

/// The package's two feedback kinds on the scanner (a beep and a vibration).
public enum ScannerFeedback {
    case success, error
}

/// One event of the package, reduced to what the gene may receive.
public enum ScannerLibraryEvent {
    case result(ScannerResult)
    /// a result the package suppressed as a repeat
    case duplicate(ScannerResult)
    case connection(String)
    case battery(Int)
    /// a scanner heard while a pairing looks: its id, and its signal in
    /// dBm (nearer to zero is stronger), smoothed by the package
    case found(deviceID: String, signal: Int)
    /// a pairing's picked scanner is connected, and the package waits for
    /// the confirming scan
    case confirming
    /// reporting and warnings: not passed on
    case unpassed
}

/// A scan's result: its kind, the holder's kept fields when the document
/// was read, and the codes of its issues (errors first, then warnings).
public struct ScannerResult {
    public enum Kind: String {
        case read, failedRead, failedValidation
    }
    public var kind: Kind
    public var holder: ScannerHolder?
    public var issueCodes: [String]

    public init(kind: Kind, holder: ScannerHolder?, issueCodes: [String]) {
        self.kind = kind
        self.holder = holder
        self.issueCodes = issueCodes
    }
}

public struct ScannerHolder {
    public var fullName: String
    public var dateOfBirth: String // ISO, YYYY-MM-DD
    public var expirationDate: String?
    public var isOver21: Bool
    public var isExpired: Bool?

    public init(fullName: String, dateOfBirth: String, expirationDate: String?, isOver21: Bool, isExpired: Bool?) {
        self.fullName = fullName
        self.dateOfBirth = dateOfBirth
        self.expirationDate = expirationDate
        self.isOver21 = isOver21
        self.isExpired = isExpired
    }
}

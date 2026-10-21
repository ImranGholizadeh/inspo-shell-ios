// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

// A check of the holder's age (Shell/IDScanner.swift): whole years, worked
// out on the phone from the holder's dateOfBirth and the phone's own day,
// one less while this year's birthday is still to come; none when the birth
// date is missing or is no date as the reader writes one; handed to a page
// only when its endpoint's keep names it, as dateOfBirth is; and the
// stand-in's made-up people (Shell/StandInReader.swift) each read with the
// age they were made with. On this Mac: scripts/check-age.sh.

import Foundation
import IDScannerSurface

func fields(_ value: [String: Any]) -> String {
    value.isEmpty ? "{}" : value.keys.sorted().map { "\($0)=\(value[$0]!)" }.joined(separator: " ")
}

func on(_ year: Int, _ month: Int, _ day: Int) -> DateComponents {
    DateComponents(year: year, month: month, day: day)
}

func age(_ born: String, _ today: DateComponents) -> String {
    IDScannerAdapter.age(born: born, on: today).map(String.init) ?? "none"
}

// MARK: the years

do {
    check("born 2000-08-31 is 26 on 2026-10-21", [age("2000-08-31", on(2026, 10, 21))], ["26"])
    check("a birthday tomorrow counts one less", [age("2000-10-22", on(2026, 10, 21))], ["25"])
    check("a birthday today counts", [age("2000-10-21", on(2026, 10, 21))], ["26"])
    check("the day before and after a birthday, and the last day of the year before it",
          [age("2005-01-01", on(2026, 12, 31)), age("2005-01-01", on(2027, 1, 1)), age("2005-12-31", on(2026, 12, 30))],
          ["21", "22", "20"])
    check("a leap day: in a year with no 29 February, the birthday is once 28 February is over",
          [age("2000-02-29", on(2027, 2, 28)), age("2000-02-29", on(2027, 3, 1)),
           age("2000-02-29", on(2028, 2, 28)), age("2000-02-29", on(2028, 2, 29))],
          ["26", "27", "27", "28"])
    check("one born today is 0", [age("2026-10-21", on(2026, 10, 21))], ["0"])
}

// MARK: no age

do {
    check("a missing birth date gives no age: the reader writes \"\" for a date it could not read",
          [age("", on(2026, 10, 21)), age("   ", on(2026, 10, 21))], ["none", "none"])
    check("a day no calendar has gives no age", [age("1990-02-30", on(2026, 10, 21)), age("2001-02-29", on(2026, 10, 21)),
                                                 age("1900-02-29", on(2026, 10, 21)), age("1990-13-01", on(2026, 10, 21)),
                                                 age("1990-00-10", on(2026, 10, 21)), age("1990-04-31", on(2026, 10, 21))],
          ["none", "none", "none", "none", "none", "none"])
    check("2000 and 1996 have a 29 February", [age("2000-02-29", on(2026, 10, 21)), age("1996-02-29", on(2026, 10, 21))], ["26", "30"])
    check("a date written another way than the reader writes it gives no age, never a guess at its order",
          [age("03141986", on(2026, 10, 21)), age("19860314", on(2026, 10, 21)), age("03/14/1986", on(2026, 10, 21)),
           age("1986-3-14", on(2026, 10, 21)), age("86-03-14", on(2026, 10, 21)), age("1986-03-14T00:00:00Z", on(2026, 10, 21)),
           age("１９８６-03-14", on(2026, 10, 21)), age("+986-03-14", on(2026, 10, 21)), age("not a date", on(2026, 10, 21))],
          ["none", "none", "none", "none", "none", "none", "none", "none", "none"])
    check("a birth after the day gives no age", [age("2026-10-22", on(2026, 10, 21)), age("2030-01-01", on(2026, 10, 21))], ["none", "none"])
    check("a day the phone could not say gives no age", [age("2000-08-31", DateComponents(year: 2026, month: 10))], ["none"])
}

// MARK: the phone's own day

do {
    // 20:00 on 21 October 2026, UTC: already 22 October at seven hours east
    let evening = Date(timeIntervalSince1970: 1_792_612_800)
    let east = IDScannerAdapter.day(of: evening, in: TimeZone(secondsFromGMT: 7 * 3600)!)
    let utc = IDScannerAdapter.day(of: evening, in: TimeZone(identifier: "UTC")!)
    check("the day is the phone's where it is, in the Gregorian calendar",
          ["\(east.year!)-\(east.month!)-\(east.day!)", "\(utc.year!)-\(utc.month!)-\(utc.day!)"], ["2026-10-22", "2026-10-21"])
    check("so one whose birthday it is there is a year older there than at UTC",
          [age("2000-10-22", east), age("2000-10-22", utc)], ["26", "25"])
    let now = IDScannerAdapter.phoneToday()
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = .current
    check("the adapter's own day is today's, in the Gregorian calendar",
          [String(now.year == gregorian.component(.year, from: Date()) && now.month == gregorian.component(.month, from: Date()))], ["true"])
}

// MARK: a read, flat, and what a page is handed

func read(born: String) -> ScannerResult {
    ScannerResult(kind: .read, holder: ScannerHolder(fullName: "Test Person One", dateOfBirth: born, expirationDate: "2030-01-01",
                                                   isOver21: true, isExpired: false), issueCodes: [])
}

do {
    check("a read carries the age beside the birth date",
          [fields(IDScannerAdapter.flat(read(born: "2000-08-31"), today: on(2026, 10, 21)))],
          ["age=26 dateOfBirth=2000-08-31 expirationDate=2030-01-01 fullName=Test Person One isExpired=false isOver21=true kind=read"])
    check("a read with no birth date carries no age",
          [fields(IDScannerAdapter.flat(read(born: ""), today: on(2026, 10, 21)))],
          ["dateOfBirth= expirationDate=2030-01-01 fullName=Test Person One isExpired=false isOver21=true kind=read"])
    check("a read that failed its validation carries it too, and one with no holder carries none",
          [fields(IDScannerAdapter.flat(ScannerResult(kind: .failedValidation, holder: read(born: "2010-05-05").holder,
                                                      issueCodes: ["UNDER_MINIMUM_AGE"]), today: on(2026, 10, 21))),
           fields(IDScannerAdapter.flat(ScannerResult(kind: .failedRead, holder: nil, issueCodes: ["incomplete"]), today: on(2026, 10, 21)))],
          ["age=16 dateOfBirth=2010-05-05 expirationDate=2030-01-01 fullName=Test Person One isExpired=false isOver21=true issueCode=UNDER_MINIMUM_AGE kind=failedValidation",
           "issueCode=incomplete kind=failedRead"])
}

/// A scanner that says what the check has it say, and nothing else.
final class Scanner: BluetoothIDScanner {
    var listeners: [UUID: (ScannerLibraryEvent) -> Void] = [:]
    func configure(_ policy: ScannerPolicy) throws {}
    var connection = ScannerConnection(state: "connected", deviceID: "A")
    var batteryPercent: Int? { nil }
    var pairedDeviceIDs: [String] { ["A"] }
    var bluetooth: ScannerBluetooth { .on }
    var pairsWhileConnected: Bool { false }
    func feedback(_ kind: ScannerFeedback, done: @escaping (Error?) -> Void) { done(nil) }
    func connect(_ deviceID: String, done: @escaping (Error?) -> Void) { done(nil) }
    func forget(_ deviceID: String, done: @escaping (Error?) -> Void) { done(nil) }
    func becameActive() {}
    func pair(_ place: ScannerPlace, done: @escaping (ScannerPairingFailure?) -> Void) {}
    func stopPairing() {}
    func listen(_ each: @escaping (ScannerLibraryEvent) -> Void) -> () -> Void {
        let key = UUID()
        listeners[key] = each
        return { [weak self] in self?.listeners.removeValue(forKey: key) }
    }
    func say(_ event: ScannerLibraryEvent) { listeners.values.forEach { $0(event) } }
}

/// What a page is handed of the scans through the shell, by a stream whose
/// endpoint keeps the fields named (the stream's first word, the state, left out).
func handed(keep: [String], _ results: [ScannerResult], scanner: BluetoothIDScanner? = nil,
            today: DateComponents? = on(2026, 10, 21), play: ((BluetoothIDScanner) -> Void)? = nil) -> [String] {
    let reader = scanner ?? Scanner()
    let adapter = IDScannerAdapter(name: "id-reader", scanner: reader)
    if let today { adapter.today = { today } }
    NativeLibraries.shared.register(adapter)
    var got: [String] = []
    NativeLibraries.shared.handle(["id": "s", "url": "native://id-reader/events", "listen": true, "keep": keep],
                                  answered: { _, value in got.append(fields(value)) }, failed: { _, error in got.append("error: " + error) })
    NativeLibraries.shared.handle(["id": "r", "url": "native://id-reader/start-reading", "keep": [String]()],
                                  answered: { _, _ in }, failed: { _, error in got.append("error: " + error) })
    results.forEach { (reader as? Scanner)?.say(.result($0)) }
    play?(reader)
    NativeLibraries.shared.stopAll()
    return Array(got.dropFirst())
}

do {
    check("the age reaches a page whose endpoint keeps it, as the birth date does",
          handed(keep: ["kind", "age", "dateOfBirth"], [read(born: "2000-08-31")]), ["age=26 dateOfBirth=2000-08-31 kind=read"])
    check("a page that keeps the age alone is handed no birth date", handed(keep: ["kind", "age"], [read(born: "2000-08-31")]),
          ["age=26 kind=read"])
    check("a page whose endpoint does not keep it is handed none",
          handed(keep: ["kind", "fullName", "dateOfBirth", "expirationDate", "isOver21", "isExpired"], [read(born: "2000-08-31")]),
          ["dateOfBirth=2000-08-31 expirationDate=2030-01-01 fullName=Test Person One isExpired=false isOver21=true kind=read"])
    check("a read with no birth date hands no age to a page that keeps it", handed(keep: ["kind", "age"], [read(born: "")]), ["kind=read"])
    check("the adapter counts by the day it is told: a birthday tomorrow, then that day",
          handed(keep: ["age"], [read(born: "2000-10-22")]) + handed(keep: ["age"], [read(born: "2000-10-22")], today: on(2026, 10, 22)),
          ["age=25", "age=26"])
}

// MARK: the stand-in's made-up people

do {
    // its script is counted from today, so each is read with the age it was made with, on the phone's own day
    let reader = StandInReader()
    let got = handed(keep: ["kind", "fullName", "age"], [], scanner: reader, today: nil) { _ in
        for _ in 0..<6 { reader.press() }
    }
    check("the stand-in's people each read with their age: 36, 18 and 41; a failed read and a document no reader knows carry none",
          got, ["age=36 fullName=Test Person One kind=read", "kind=duplicate", "kind=failedRead",
                "age=18 fullName=Test Person Two kind=failedValidation", "age=41 fullName=Test Person Three kind=failedValidation",
                "kind=failedValidation"])
    // made on any day, a leap day and the days around one among them, the script's people are the same ages that day
    let days = [1_709_164_800, 1_709_078_400, 1_740_787_200, 1_740_700_800, 1_792_612_800].map { Date(timeIntervalSince1970: TimeInterval($0) + 12 * 3600) }
    let ages = days.map { day in
        StandInReader.script(today: day).compactMap { event -> String? in
            guard case .result(let result) = event, let holder = result.holder else { return nil }
            return age(holder.dateOfBirth, IDScannerAdapter.day(of: day, in: .current))
        }.joined(separator: " ")
    }
    check("whatever day the script is made, its people are 36, 18 and 41 that day",
          ages, Array(repeating: "36 18 41", count: days.count))
}

print("age: \(passed) passed, \(failed) failed")
if failed > 0 { exit(1) }

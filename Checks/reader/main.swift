// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

// A check of what the adapter says of a paired scanner that is not connected
// (Shell/IDScanner.swift, Q011): the state call's answer at once, with paired
// and the reason; the stream's state events when the link drops, when
// Bluetooth goes off, is refused or comes back, and when the scanner is back;
// the reconnect call that waits as ever and the one that answers at once;
// the warnings; and the stand-in's scenes (Shell/StandInReader.swift). On
// this Mac, with a scanner that only records what it was asked and a clock
// the check moves: scripts/check-reader.sh.

import Foundation
import IDScannerSurface

/// An event or an answer with every field: key=value, in the keys' order.
func fields(_ value: [String: Any]) -> String {
    value.isEmpty ? "{}" : value.keys.sorted().map { "\($0)=\(value[$0]!)" }.joined(separator: " ")
}

func bench(paired: [String] = [], state: String = "idle") -> (RecordedScanner, Bench) {
    let scanner = RecordedScanner()
    scanner.paired = paired
    scanner.state = state
    scanner.deviceID = paired.first
    return (scanner, Bench(scanner, written: fields))
}

/// A paired scanner that was connected and dropped out of range: the package
/// says reconnecting, then at once connecting, and waits.
func dropped() -> (RecordedScanner, Bench) {
    let (scanner, bench) = bench(paired: ["A"], state: "connected")
    scanner.say(.connection("reconnecting", away: .outOfRange))
    scanner.say(.connection("connecting"))
    return (scanner, bench)
}

// MARK: the state call

do {
    let (scanner, bench) = bench()
    check("no scanner paired: paired is 0, and an idle phone gives no reason", [bench.call("state")],
          ["kind=state paired=0 state=idle"])
    scanner.paired = ["A"]
    check("a scanner paired and nothing asked yet: paired is 1, with a reason, at once", [bench.call("state")],
          ["kind=state paired=1 reason=unknown state=idle"])
    check("the state call asks the scanner nothing", scanner.asked, [])
    var json = ""
    bench.adapter.call("state", data: nil) { result in
        if case .success(let value) = result, let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
            json = String(data: data, encoding: .utf8) ?? ""
        }
    }
    check("paired is a number, not true or false", [json], [#"{"kind":"state","paired":1,"reason":"unknown","state":"idle"}"#])
    scanner.say(.battery(84))
    scanner.say(.connection("connected"))
    check("connected: the battery once the scanner has said it, and no reason", [bench.call("state")],
          ["battery=84 kind=state paired=1 state=connected"])
    scanner.say(.connection("reading"))
    check("reading is connected, as ever", [bench.call("state")], ["battery=84 kind=state paired=1 state=connected"])
}

do {
    let (scanner, bench) = dropped()
    check("a paired scanner the package waits for is reconnecting, out of range, though the package says connecting",
          [bench.call("state"), scanner.state], ["kind=state paired=1 reason=out-of-range state=reconnecting", "connecting"])
    scanner.say(.bluetooth(.off))
    check("Bluetooth off is the reason while it is off", [bench.call("state")],
          ["kind=state paired=1 reason=bluetooth-off state=reconnecting"])
    scanner.say(.bluetooth(.notAllowed))
    check("Bluetooth not allowed", [bench.call("state")], ["kind=state paired=1 reason=bluetooth-not-allowed state=reconnecting"])
    scanner.say(.bluetooth(.on))
    check("Bluetooth on again: the scanner is out of range still", [bench.call("state")],
          ["kind=state paired=1 reason=out-of-range state=reconnecting"])
}

do {
    var said: [String] = []
    for (away, reason) in [(ScannerAway.outOfRange, "out-of-range"), (.switchedOff, "switched-off"), (.bluetoothOff, "bluetooth-off"),
                           (.bluetoothNotAllowed, "bluetooth-not-allowed"), (.unknown, "unknown")] {
        let (scanner, bench) = bench(paired: ["A"], state: "connected")
        scanner.say(.connection("disconnected", away: away))
        said.append(bench.call("state") == "kind=state paired=1 reason=\(reason) state=disconnected" ? "ok" : "\(reason): \(bench.call("state"))")
    }
    check("each cause the package gives is told in the gene's words", said, ["ok", "ok", "ok", "ok", "ok"])
    let (scanner, bench) = bench(paired: ["A"], state: "connected")
    scanner.say(.connection("reconnecting", away: .bluetoothOff))
    scanner.say(.bluetooth(.on))
    check("a link Bluetooth took, once Bluetooth is on again, is a scanner not there for a reason not known",
          [bench.call("state")], ["kind=state paired=1 reason=unknown state=reconnecting"])
}

do {
    let (scanner, _) = bench(paired: ["A"], state: "connected")
    let quiet = Bench(scanner, stream: false, written: fields) // no stream open: the adapter still hears why
    _ = quiet.call("state")
    scanner.say(.connection("reconnecting", away: .outOfRange))
    scanner.say(.connection("connecting"))
    check("with no stream open the adapter still knows why the scanner is away", [quiet.call("state")],
          ["kind=state paired=1 reason=out-of-range state=reconnecting"])
}

// MARK: the stream

do {
    let (scanner, bench) = bench(paired: ["A"], state: "connected")
    check("a stream begins with the state", bench.heard, ["kind=state paired=1 state=connected"])
    scanner.say(.connection("reconnecting", away: .outOfRange))
    scanner.say(.connection("connecting"))
    check("the link drops: one state event at once, reconnecting, out of range; the package's connecting adds none",
          last(bench.heard, 2), ["kind=state paired=1 state=connected", "kind=state paired=1 reason=out-of-range state=reconnecting"])
    scanner.say(.bluetooth(.off))
    check("Bluetooth goes off while it is away: a state event at once, with the new reason", last(bench.heard, 1),
          ["kind=state paired=1 reason=bluetooth-off state=reconnecting"])
    check("and nothing is asked of the scanner while Bluetooth is off", scanner.asked, [])
    scanner.say(.bluetooth(.on))
    check("Bluetooth comes back: the scanner is asked for again, since the phone's wait ended with Bluetooth",
          scanner.asked + last(bench.heard, 1), ["connect A", "kind=state paired=1 reason=out-of-range state=reconnecting"])
    scanner.say(.connection("connected"))
    scanner.answerConnects()
    check("the scanner comes back: connected, at once", last(bench.heard, 1), ["kind=state paired=1 state=connected"])
    let count = bench.heard.count
    scanner.say(.connection("reading"))
    scanner.say(.connection("connected"))
    scanner.say(.bluetooth(.on))
    check("a scan's reading, and a word that changes nothing, are no events", [String(bench.heard.count - count)], ["0"])
}

do {
    let (scanner, bench) = bench(paired: ["A"], state: "connected")
    scanner.say(.bluetooth(.on)) // the binding's first word
    scanner.say(.bluetooth(.off))
    scanner.say(.connection("reconnecting", away: .bluetoothOff))
    check("Bluetooth goes off under a connected scanner: one event, reconnecting, bluetooth-off", last(bench.heard, 2),
          ["kind=state paired=1 state=connected", "kind=state paired=1 reason=bluetooth-off state=reconnecting"])
    scanner.say(.bluetooth(.on))
    scanner.say(.connection("connecting"))
    scanner.say(.connection("connected"))
    scanner.answerConnects()
    check("and back on: it is asked for, waited for, and connected", scanner.asked + last(bench.heard, 2),
          ["connect A", "kind=state paired=1 reason=unknown state=reconnecting", "kind=state paired=1 state=connected"])
}

do {
    let (scanner, bench) = bench(paired: ["A"])
    scanner.say(.bluetooth(.on))
    check("the binding's first word of Bluetooth, on, asks for nothing and tells nothing new", scanner.asked + bench.heard,
          ["kind=state paired=1 reason=unknown state=idle"])
    scanner.say(.bluetooth(.notAllowed))
    check("Bluetooth refused: a state event at once, with the reason", last(bench.heard, 1),
          ["kind=state paired=1 reason=bluetooth-not-allowed state=idle"])
    let (none, empty) = Checks.bench()
    none.say(.bluetooth(.off))
    none.say(.bluetooth(.on))
    check("with no scanner paired, Bluetooth going off and on asks and tells nothing", none.asked + empty.heard,
          ["kind=state paired=0 state=idle"])
}

do {
    let (scanner, bench) = bench(paired: ["A"])
    _ = bench.call("start-pairing")
    scanner.say(.connection("scanning"))
    scanner.hear("B", -50)
    bench.clock.pass(3)
    scanner.say(.connection("connecting"))
    check("while a first pairing connects its pick, connecting is connecting, though a scanner is paired",
          last(bench.heard, 2), ["kind=pairing step=connecting", "kind=state paired=1 state=connecting"])
}

do {
    let (scanner, bench) = bench(paired: ["A"], state: "connected")
    scanner.say(.warning(.keyboardMode))
    scanner.say(.connection("disconnected", away: .unknown))
    scanner.say(.battery(9))
    scanner.say(.warning(.lowBattery))
    scanner.say(.unpassed)
    check("a scanner in keyboard mode and a low battery are warnings on the stream; the battery is an event; nothing else passes",
          last(bench.heard, 4), ["kind=warning warning=keyboard-mode", "kind=state paired=1 reason=unknown state=disconnected",
                                 "battery=9 kind=battery", "kind=warning warning=low-battery"])
}

do {
    let (scanner, bench) = bench(paired: ["A"], state: "connected")
    NativeLibraries.shared.register(bench.adapter)
    var kept: [String] = []
    let take: (String, [String: Any]) -> Void = { id, value in kept.append(id + ": " + fields(value)) }
    let fail: (String, String) -> Void = { id, error in kept.append(id + ": error: " + error) }
    NativeLibraries.shared.handle(["id": "s", "url": "native://id-reader/events", "listen": true, "keep": ["kind", "state"]],
                                  answered: take, failed: fail)
    NativeLibraries.shared.handle(["id": "c", "url": "native://id-reader/state", "keep": ["state", "battery"]],
                                  answered: take, failed: fail)
    scanner.say(.connection("reconnecting", away: .outOfRange))
    NativeLibraries.shared.stopAll()
    check("a gene built before this keeps what it kept: no paired and no reason reach it", kept,
          ["s: kind=state state=connected", "c: state=connected", "s: kind=state state=reconnecting"])
}

// MARK: reconnect

do {
    let (scanner, bench) = bench(paired: ["A"])
    let first = bench.call("reconnect")
    check("reconnect with no data waits for the connection, as ever: no answer while the scanner is away",
          [first] + scanner.asked + bench.answered, ["no answer", "connect A"])
    check("and the stream says the scanner is waited for", last(bench.heard, 1), ["kind=state paired=1 reason=unknown state=reconnecting"])
    scanner.say(.connection("connecting"))
    bench.clock.pass(100)
    check("it waits as long as the scanner is away", bench.answered, [])
    scanner.say(.connection("connected"))
    scanner.answerConnects()
    check("and answers when it is connected, with the empty answer it always gave", bench.answered + last(bench.heard, 1),
          ["{}", "kind=state paired=1 state=connected"])
    _ = bench.call("reconnect", ["wait": 1])
    scanner.answerConnects(Refused())
    check("a connection that fails is the call's error, as ever", last(bench.answered, 1), ["error: Refused()"])
}

do {
    let (scanner, bench) = bench(paired: ["A"])
    let answer = bench.call("reconnect", ["wait": 0])
    check("reconnect with wait 0 answers at once with the state it moved to, in the state call's shape",
          [answer] + scanner.asked, ["kind=state paired=1 reason=unknown state=reconnecting", "connect A"])
    check("and the stream hears it", last(bench.heard, 1), ["kind=state paired=1 reason=unknown state=reconnecting"])
    scanner.say(.connection("connecting"))
    scanner.say(.connection("connected"))
    scanner.answerConnects()
    check("the connection comes on the stream, and the call is not answered twice", bench.answered + last(bench.heard, 1),
          ["kind=state paired=1 reason=unknown state=reconnecting", "kind=state paired=1 state=connected"])
    let again = bench.call("reconnect", ["wait": false])
    check("a scanner that is connected is asked nothing: connected, at once", [again] + scanner.asked,
          ["kind=state paired=1 state=connected", "connect A"])
}

do {
    let (scanner, bench) = bench(paired: ["A"])
    _ = bench.call("reconnect", ["wait": 0])
    scanner.answerConnects(Refused())
    check("a connection that cannot be made: the stream says the scanner is no longer waited for", last(bench.heard, 2),
          ["kind=state paired=1 reason=unknown state=reconnecting", "kind=state paired=1 reason=unknown state=idle"])
}

do {
    let (scanner, bench) = bench(paired: ["A"])
    scanner.say(.bluetooth(.off))
    let answer = bench.call("reconnect", ["wait": 0])
    check("with Bluetooth off, reconnect with wait 0 says so at once and asks the scanner nothing", [answer] + scanner.asked,
          ["kind=state paired=1 reason=bluetooth-off state=idle"])
    scanner.say(.bluetooth(.on))
    check("and the scanner is asked for when Bluetooth is back, with no tap", scanner.asked + last(bench.heard, 1),
          ["connect A", "kind=state paired=1 reason=unknown state=reconnecting"])
}

do {
    let (scanner, bench) = bench()
    check("with no scanner paired both reconnects fail, as ever", [bench.call("reconnect"), bench.call("reconnect", ["wait": 0])] + scanner.asked,
          ["error: reconnect: no paired scanner", "error: reconnect: no paired scanner"])
}

do {
    let (scanner, bench) = dropped()
    _ = bench.call("reconnect", ["wait": 0])
    let forgot = bench.call("forget")
    scanner.say(.connection("disconnected", away: .unknown))
    check("forget: the scanner is forgotten, paired is 0, and the stream says disconnected, with paired 0",
          [forgot, bench.call("state")] + last(scanner.asked, 1) + last(bench.heard, 1),
          ["{}", "kind=state paired=0 reason=unknown state=disconnected", "forget A", "kind=state paired=0 reason=unknown state=disconnected"])
    scanner.paired = ["B"]
    scanner.answerConnects(Refused()) // the forgotten scanner's connection, answered late
    check("a connection asked before the forget counts for nothing after it: not waited for, and the next one is",
          [bench.call("state"), bench.call("reconnect", ["wait": 0])],
          ["kind=state paired=1 reason=unknown state=disconnected", "kind=state paired=1 reason=unknown state=reconnecting"])
}

// MARK: paired on the stream's state events

do {
    let (_, bench) = bench(paired: ["A"], state: "connected")
    var json = ""
    let stop = bench.adapter.listen("events", data: nil, each: { value in
        if json.isEmpty, let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
            json = String(data: data, encoding: .utf8) ?? ""
        }
    }, failed: { _ in })
    stop()
    check("a state event says paired as the state call does: a number, not true or false", [json],
          [#"{"kind":"state","paired":1,"state":"connected"}"#])
    let (_, none) = Checks.bench()
    check("and 0 where no scanner is paired, from the stream's first event", none.heard, ["kind=state paired=0 state=idle"])
}

do {
    let (scanner, bench) = bench(paired: ["A"], state: "connected")
    scanner.say(.connection("disconnected", away: .unknown))
    let count = bench.heard.count
    let forgot = bench.call("forget")
    check("a scanner forgotten while it is disconnected: the state and its reason are what they were, and a state event says paired 0 at once",
          [forgot] + Array(bench.heard.suffix(from: count)), ["{}", "kind=state paired=0 reason=unknown state=disconnected"])
}

do {
    let (scanner, bench) = bench(paired: ["A"], state: "connected")
    scanner.say(.connection("disconnected", away: .outOfRange))
    scanner.paired = [] // unpaired in the phone's own settings: the package says nothing of it
    let count = bench.heard.count
    bench.adapter.cameToFront()
    check("a scanner unpaired outside the app is told when the app comes to the front: paired 0, the state as it was",
          Array(bench.heard.suffix(from: count)), ["kind=state paired=0 reason=out-of-range state=disconnected"])
    bench.adapter.cameToFront()
    check("and coming to the front with nothing changed tells nothing", [String(bench.heard.count - count)], ["1"])
}

do {
    let (scanner, bench) = bench()
    _ = bench.call("start-pairing")
    scanner.hear("A", -60)
    bench.clock.pass(3)
    scanner.say(.connection("connected"))
    scanner.connectDone?(nil)
    scanner.say(.confirming)
    check("a pick that is connected and not yet confirmed is no paired scanner", last(bench.heard, 2),
          ["kind=state paired=0 state=connected", "kind=pairing step=confirm"])
    scanner.paired = ["A"]
    scanner.pairDone?(nil)
    check("once the pairing is paired, a state event says paired 1, though the state is what it was", last(bench.heard, 2),
          ["kind=pairing step=paired", "kind=state paired=1 state=connected"])
}

do {
    let reader = StandInReader()
    reader.play("away") // a phone opened with its scanner away: paired, idle
    let bench = Bench(reader, written: fields)
    reader.wait = bench.clock.wait
    reader.play("unpaired")
    check("the stand-in unpaired while it is idle: the state is idle still, and a state event says paired 0",
          last(bench.heard, 2), ["kind=state paired=1 reason=unknown state=idle", "kind=state paired=0 state=idle"])
}

// MARK: a scanner that types as a keyboard, and reconnects asked of it

/// A recorded scanner put in keyboard mode as the package tells it: the
/// warning, and the link drops.
func typing() -> (RecordedScanner, Bench) {
    let (scanner, bench) = bench(paired: ["A"], state: "connected")
    scanner.say(.warning(.keyboardMode))
    scanner.say(.connection("disconnected", away: .unknown))
    return (scanner, bench)
}

/// The package's answer to a connection asked of a scanner in keyboard
/// mode: the warning again, and the connection fails.
func refuseAsKeyboard(_ scanner: RecordedScanner) {
    scanner.say(.warning(.keyboardMode))
    scanner.answerConnects(Refused())
}

func warnings(_ bench: Bench) -> Int { bench.heard.filter { $0 == "kind=warning warning=keyboard-mode" }.count }

do {
    let (scanner, bench) = typing()
    var answers: Set<String> = []
    for _ in 0..<50 {
        answers.insert(bench.call("reconnect", ["wait": 0]))
        refuseAsKeyboard(scanner) // the package says the warning again at each connection it is asked for
        bench.clock.pass(0.02)
    }
    check("fifty reconnects asked in a second of a scanner in keyboard mode: the package is asked once, and each is answered at once with the state",
          scanner.asked + answers.sorted(), ["connect A", "kind=state paired=1 reason=unknown state=disconnected"])
    check("and the stream heard the keyboard-mode warning once, at the change of mode, not once for each", [String(warnings(bench))], ["1"])
    bench.clock.pass(1)
    refuseAsKeyboard(scanner)
    check("the adapter asks again by itself two seconds after the one before, since nothing else says the mode has changed",
          scanner.asked + [String(warnings(bench))], ["connect A", "connect A", "1"])
    bench.clock.pass(2)
    scanner.say(.connection("connecting")) // set back: the package no longer refuses, and waits for it
    check("set back, the next of its own tries is not refused: the scanner is waited for, and the stream says so",
          [String(scanner.asked.count)] + last(bench.heard, 1), ["3", "kind=state paired=1 reason=unknown state=reconnecting"])
    scanner.say(.connection("connected"))
    scanner.answerConnects()
    bench.clock.pass(100)
    check("and connects with no tap; then nothing more is asked", [String(scanner.asked.count)] + last(bench.heard, 1),
          ["3", "kind=state paired=1 state=connected"])
    scanner.say(.warning(.keyboardMode))
    scanner.say(.connection("disconnected", away: .unknown))
    check("set to keyboard mode again, the warning is said again: once for each change of mode", [String(warnings(bench))], ["2"])
}

do {
    let (scanner, bench) = typing()
    let waited = bench.call("reconnect")
    refuseAsKeyboard(scanner)
    check("a reconnect that waits, asked of a scanner in keyboard mode, waits for it: no answer, no error, and no new warning",
          [waited] + bench.answered + [String(warnings(bench))], ["no answer", "1"])
    bench.clock.pass(2)
    scanner.say(.connection("connected"))
    scanner.answerConnects()
    check("and is answered when the scanner is connected, as a reconnect that waits always is", bench.answered, ["{}"])
}

do {
    let (scanner, bench) = bench(paired: ["A"])
    _ = bench.call("reconnect", ["wait": 0]) // the app opened with the scanner already in keyboard mode: the adapter does not know yet
    refuseAsKeyboard(scanner)
    check("a reconnect that finds the keyboard mode out: the warning once, the state as it is, and the scanner no longer said to be waited for",
          [String(warnings(bench))] + last(bench.heard, 1) + scanner.asked,
          ["1", "kind=state paired=1 reason=unknown state=idle", "connect A"])
    bench.clock.pass(2)
    check("and the adapter goes on asking by itself, two seconds apart", scanner.asked, ["connect A", "connect A"])
}

do {
    let (scanner, bench) = typing()
    _ = bench.call("reconnect", ["wait": 0])
    refuseAsKeyboard(scanner)
    var began: [String] = []
    let stop = bench.adapter.listen("events", data: nil, each: { began.append(fields($0)) }, failed: { _ in })
    stop()
    check("a stream that opens while the scanner is in keyboard mode hears the state, then the warning that stands", began,
          ["kind=state paired=1 reason=unknown state=disconnected", "kind=warning warning=keyboard-mode"])
}

do {
    let (scanner, bench) = typing()
    let waited = bench.call("reconnect")
    refuseAsKeyboard(scanner)
    let forgot = bench.call("forget")
    bench.clock.pass(100)
    check("forget ends it: the reconnect that waited fails, and the scanner is asked for no more",
          [waited, forgot] + [String(bench.answered.count)] + scanner.asked, ["no answer", "{}", "2", "connect A", "forget A"])
}

do {
    let (scanner, bench) = typing()
    _ = bench.call("reconnect", ["wait": 0])
    refuseAsKeyboard(scanner)
    scanner.say(.bluetooth(.off))
    bench.clock.pass(10)
    check("with Bluetooth off nothing is asked of a scanner in keyboard mode", scanner.asked, ["connect A"])
    scanner.say(.bluetooth(.on))
    bench.clock.pass(2)
    check("and it is asked for again once Bluetooth is back", [String(scanner.asked.count >= 2)], ["true"])
}

do {
    let reader = StandInReader()
    let bench = Bench(reader, written: fields)
    reader.wait = bench.clock.wait
    _ = bench.call("start-reading")
    reader.play("keyboard-mode")
    for _ in 0..<50 {
        _ = bench.call("reconnect", ["wait": 0])
        bench.clock.pass(0.02)
    }
    check("the stand-in in keyboard mode, fifty reconnects in a second: one warning", [String(warnings(bench))], ["1"])
    reader.play("back")
    bench.clock.pass(3)
    let connections = bench.heard.filter { $0 == "kind=state paired=1 state=connected" }.count
    check("back: one connection, with no reconnect asked after it, and no warning more",
          [String(connections - 1), String(warnings(bench)), bench.call("state")],
          ["1", "1", "battery=90 kind=state paired=1 state=connected"])
}

// MARK: a scan nobody reads

do {
    let (scanner, bench) = bench(paired: ["A"], state: "connected")
    let one = ScannerResult(kind: .read, holder: ScannerHolder(fullName: "Test Person One", dateOfBirth: "1990-01-01",
                                                               expirationDate: "2030-01-01", isOver21: true, isExpired: false), issueCodes: [])
    var count = bench.heard.count
    scanner.say(.result(one))
    check("a scan made while nothing reads is told to the stream, with no field of it", Array(bench.heard[count...]), ["kind=unread"])
    count = bench.heard.count
    scanner.say(.duplicate(one))
    check("and so is its repeat", Array(bench.heard[count...]), ["kind=unread"])
    _ = bench.call("start-reading")
    count = bench.heard.count
    scanner.say(.result(one))
    scanner.say(.duplicate(one))
    check("while it reads: the result and its repeat, and nothing more", Array(bench.heard[count...]),
          ["age=36 dateOfBirth=1990-01-01 expirationDate=2030-01-01 fullName=Test Person One isExpired=false isOver21=true kind=read",
           "kind=duplicate result=read"])
    _ = bench.call("stop-reading")
    count = bench.heard.count
    scanner.say(.result(ScannerResult(kind: .failedRead, holder: nil, issueCodes: ["incomplete"])))
    scanner.say(.result(ScannerResult(kind: .failedValidation, holder: one.holder, issueCodes: ["EXPIRED"])))
    scanner.say(.result(ScannerResult(kind: .failedValidation, holder: nil, issueCodes: ["NOT_AAMVA"])))
    scanner.say(.duplicate(ScannerResult(kind: .failedValidation, holder: one.holder, issueCodes: ["EXPIRED"])))
    check("reading stopped: a scan is unread again, whatever its kind, with or without a holder",
          Array(bench.heard[count...]), ["kind=unread", "kind=unread", "kind=unread", "kind=unread"])
    count = bench.heard.count
    scanner.say(.battery(60))
    scanner.say(.connection("reading"))
    scanner.say(.connection("connected"))
    check("what is no scan is as ever", Array(bench.heard[count...]), ["battery=60 kind=battery"])
}

do {
    let reader = StandInReader()
    let bench = Bench(reader, written: fields)
    reader.wait = bench.clock.wait
    let count = bench.heard.count
    reader.press()
    check("the stand-in's press while nothing reads", Array(bench.heard[count...]), ["kind=unread"])
}

do {
    // no stream open: nothing is said, and nothing is kept for a stream that opens later
    let scanner = RecordedScanner()
    scanner.paired = ["A"]
    scanner.state = "connected"
    scanner.deviceID = "A"
    let bench = Bench(scanner, stream: false, written: fields)
    _ = bench.call("state") // first use: the adapter hears the scanner from here on
    let one = ScannerResult(kind: .read, holder: nil, issueCodes: [])
    scanner.say(.result(one))
    scanner.say(.result(one))
    bench.open()
    check("a scan made with no stream open is told to none, and none is kept for a stream that opens later",
          bench.heard, ["kind=state paired=1 state=connected"])
    // two streams: each hears it once
    var second: [String] = []
    let stop = bench.adapter.listen("events", data: nil, each: { second.append(fields($0)) }, failed: { _ in })
    let count = bench.heard.count
    second = []
    scanner.say(.result(one))
    check("two streams open: each hears one", Array(bench.heard[count...]) + second, ["kind=unread", "kind=unread"])
    stop()
}

do {
    // the app behind (the scanner goes on working there): unread scans are not handed to a page that is not shown
    let (scanner, bench) = bench(paired: ["A"], state: "connected")
    let one = ScannerResult(kind: .read, holder: nil, issueCodes: [])
    bench.adapter.wentBehind()
    var count = bench.heard.count
    for _ in 0..<40 { scanner.say(.result(one)) }
    check("forty scans nobody reads, made while the app is behind: none is handed over", Array(bench.heard[count...]), [])
    bench.adapter.cameToFront()
    check("the app comes to the front: one unread says scans were made, however many", Array(bench.heard[count...]), ["kind=unread"])
    count = bench.heard.count
    bench.adapter.cameToFront()
    check("and it is said once", Array(bench.heard[count...]), [])
    scanner.say(.result(one))
    check("in front again, a scan nobody reads is told as it is made", Array(bench.heard[count...]), ["kind=unread"])
    // reading started before the app came back: nothing is owed
    bench.adapter.wentBehind()
    scanner.say(.result(one))
    _ = bench.call("start-reading")
    count = bench.heard.count
    bench.adapter.cameToFront()
    check("scans made behind, and reading started since: none is said", Array(bench.heard[count...]), [])
}

do {
    // the page gone while the app was behind: what was owed is owed to no one
    let scanner = RecordedScanner()
    scanner.paired = ["A"]
    scanner.state = "connected"
    scanner.deviceID = "A"
    let adapter = IDScannerAdapter(name: "id-reader", scanner: scanner)
    var first: [String] = [], second: [String] = []
    let stop = adapter.listen("events", data: nil, each: { first.append(fields($0)) }, failed: { _ in })
    adapter.wentBehind()
    scanner.say(.result(ScannerResult(kind: .read, holder: nil, issueCodes: [])))
    stop()
    _ = adapter.listen("events", data: nil, each: { second.append(fields($0)) }, failed: { _ in })
    adapter.cameToFront()
    check("a stream that ended while the app was behind took what it was owed with it",
          Array(first.dropFirst()) + Array(second.dropFirst()), [])
}

// MARK: the stand-in's scenes

func standIn() -> (StandInReader, Bench) {
    let reader = StandInReader()
    let bench = Bench(reader, written: fields)
    reader.wait = bench.clock.wait
    _ = bench.call("start-reading")
    return (reader, bench)
}

do {
    let (reader, bench) = standIn()
    check("the stand-in starts paired and connected", [bench.call("state")] + bench.heard,
          ["battery=90 kind=state paired=1 state=connected", "kind=state paired=1 state=connected"])
    reader.play("away")
    check("away: the link drops, and the scanner is waited for", [bench.call("state")] + last(bench.heard, 1),
          ["battery=90 kind=state paired=1 reason=out-of-range state=reconnecting", "kind=state paired=1 reason=out-of-range state=reconnecting"])
    let count = bench.heard.count
    reader.press()
    bench.clock.pass(100)
    check("a scanner that is away scans nothing, and stays away", [String(bench.heard.count - count), bench.call("reconnect", ["wait": 0])],
          ["0", "battery=90 kind=state paired=1 reason=out-of-range state=reconnecting"])
    reader.play("back")
    bench.clock.pass(0.7)
    check("back: it is not connected before its time", last(bench.heard, 1), ["kind=state paired=1 reason=out-of-range state=reconnecting"])
    bench.clock.pass(0.1)
    check("and is connected in under a second, with no tap", [bench.call("state")] + last(bench.heard, 1),
          ["battery=90 kind=state paired=1 state=connected", "kind=state paired=1 state=connected"])
    reader.press()
    check("and scans again", [String(last(bench.heard, 1)[0].hasPrefix("age=36 dateOfBirth="))], ["true"])
}

do {
    let reader = StandInReader()
    reader.play("away") // the link that opens the app, before anything is asked of the stand-in
    let bench = Bench(reader, written: fields)
    reader.wait = bench.clock.wait
    check("away as the app opens: a phone opened with its scanner away, paired, idle, nothing asked",
          [bench.call("state")] + bench.heard,
          ["battery=90 kind=state paired=1 reason=unknown state=idle", "kind=state paired=1 reason=unknown state=idle"])
    check("its opening reconnect answers at once that the scanner is waited for", [bench.call("reconnect", ["wait": 0])] + last(bench.heard, 1),
          ["battery=90 kind=state paired=1 reason=unknown state=reconnecting", "kind=state paired=1 reason=unknown state=reconnecting"])
    bench.clock.pass(100)
    reader.play("back")
    bench.clock.pass(0.8)
    check("and the scanner connects when it is back, with no tap", last(bench.heard, 2),
          ["kind=state paired=1 reason=unknown state=reconnecting", "kind=state paired=1 state=connected"])
}

do {
    let (reader, bench) = standIn()
    reader.play("bluetooth-off")
    check("Bluetooth off: the link drops, with the reason", last(bench.heard, 1), ["kind=state paired=1 reason=bluetooth-off state=reconnecting"])
    check("a reconnect that waits fails while Bluetooth is off; one with wait 0 says why",
          [bench.call("reconnect"), bench.call("reconnect", ["wait": 0])],
          ["error: bluetoothUnavailable", "battery=90 kind=state paired=1 reason=bluetooth-off state=reconnecting"])
    reader.play("back")
    bench.clock.pass(0.8)
    check("back: Bluetooth is on, and the scanner connects by itself", last(bench.heard, 2),
          ["kind=state paired=1 reason=unknown state=reconnecting", "kind=state paired=1 state=connected"])
}

do {
    let (reader, bench) = standIn()
    reader.play("away")
    reader.play("bluetooth-off")
    check("away, then Bluetooth off: the reason is Bluetooth", last(bench.heard, 1), ["kind=state paired=1 reason=bluetooth-off state=reconnecting"])
    reader.play("back")
    check("back: the reason is the scanner's again until it connects", last(bench.heard, 1),
          ["kind=state paired=1 reason=out-of-range state=reconnecting"])
    bench.clock.pass(0.8)
    check("the wait Bluetooth ended is asked for again by the adapter, and the scanner connects", last(bench.heard, 1),
          ["kind=state paired=1 state=connected"])
    let alone = StandInReader()
    let clock = Clock()
    alone.wait = clock.wait
    var states: [String] = []
    _ = alone.listen { if case .connection(let state, _) = $0 { states.append(state) } }
    alone.play("away")
    alone.play("bluetooth-off")
    alone.play("back")
    clock.pass(100)
    check("with no adapter to ask again, that wait never ends: the stand-in plays the phone's silence", states,
          ["reconnecting", "connecting"])
}

do {
    let (reader, bench) = standIn()
    reader.play("bluetooth-refused")
    check("Bluetooth refused: disconnected, with the reason", [bench.call("state")] + last(bench.heard, 1),
          ["battery=90 kind=state paired=1 reason=bluetooth-not-allowed state=disconnected",
           "kind=state paired=1 reason=bluetooth-not-allowed state=disconnected"])
}

do {
    let (reader, bench) = standIn()
    reader.play("keyboard-mode")
    check("keyboard mode: the warning, and the link drops", last(bench.heard, 2),
          ["kind=warning warning=keyboard-mode", "kind=state paired=1 reason=unknown state=disconnected"])
    let answer = bench.call("reconnect", ["wait": 0])
    check("a reconnect meets the keyboard again: still disconnected, and the warning is not said again", [answer] + last(bench.heard, 2),
          ["battery=90 kind=state paired=1 reason=unknown state=disconnected", "kind=warning warning=keyboard-mode",
           "kind=state paired=1 reason=unknown state=disconnected"])
    reader.play("back")
    bench.clock.pass(1.9)
    check("set back, it is not asked for before the adapter's next try", last(bench.heard, 1), ["kind=state paired=1 reason=unknown state=disconnected"])
    bench.clock.pass(0.1 + 0.8)
    check("and the reconnect that was kept connects it then, with no other asked", last(bench.heard, 2),
          ["kind=state paired=1 reason=unknown state=reconnecting", "kind=state paired=1 state=connected"])
    reader.play("low-battery")
    check("low battery: the percent and the warning", [bench.call("state")] + last(bench.heard, 2),
          ["battery=8 kind=state paired=1 state=connected", "battery=8 kind=battery", "kind=warning warning=low-battery"])
}

do {
    let (reader, bench) = standIn()
    reader.play("unpaired")
    check("unpaired: no scanner, paired 0, no reason, on the stream as in the call, and a reconnect fails",
          [bench.call("state"), bench.call("reconnect", ["wait": 0])] + last(bench.heard, 1),
          ["battery=90 kind=state paired=0 state=idle", "error: reconnect: no paired scanner", "kind=state paired=0 state=idle"])
    _ = bench.call("start-pairing")
    bench.clock.pass(1)
    bench.clock.pass(3)
    bench.clock.pass(0.8)
    reader.press()
    bench.clock.pass(0.5)
    check("a first pairing pairs the stand-in again, and the stream says paired 1 after the pairing's last step",
          [bench.call("state")] + last(bench.heard, 2),
          ["battery=90 kind=state paired=1 state=connected", "kind=pairing step=paired", "kind=state paired=1 state=connected"])
    reader.play("unpaired")
    reader.play("paired")
    bench.clock.pass(0.8)
    check("paired: the stand-in as it starts", [bench.call("state")], ["battery=90 kind=state paired=1 state=connected"])
}

do {
    // a simulator has no volume button: the scene press is one
    let (reader, bench) = standIn()
    reader.play("press")
    reader.play("press")
    check("the scene press plays the script's next event, as a press of a volume button does",
          last(bench.heard, 2).map { $0.contains("fullName=Test Person One") && $0.contains("kind=read") ? "the first read" : $0 },
          ["the first read", "kind=duplicate result=read"])
    reader.play("away")
    let count = bench.heard.count
    reader.play("press")
    check("and a scanner that is not there scans nothing by it either", [String(bench.heard.count - count)], ["0"])
}

// MARK: a read's four more fields: the document's number, sex, postal code and issuing state

/// A read of a made-up document that says all four, or what the check gives.
func read(_ kind: ScannerResult.Kind = .read, number: String? = "T1234567", sex: String? = "F", postal: String? = "99999",
          state: String? = "CA", issues: [String] = []) -> ScannerResult {
    ScannerResult(kind: kind, holder: ScannerHolder(fullName: "Test Person One", dateOfBirth: "1990-01-01", expirationDate: "2030-01-01",
                                                   isOver21: true, isExpired: false, licenseNumber: number, sex: sex,
                                                   postalCode: postal, issuingState: state), issueCodes: issues)
}

/// What a page is handed of the events through the shell's own door, by a
/// stream whose endpoint keeps the fields named: the stream's first word,
/// the state, is left out.
func handed(keep: [String], _ events: [ScannerLibraryEvent], reading: Bool = true) -> [String] {
    let (scanner, bench) = bench(paired: ["A"], state: "connected")
    NativeLibraries.shared.register(bench.adapter)
    var got: [String] = []
    NativeLibraries.shared.handle(["id": "s", "url": "native://id-reader/events", "listen": true, "keep": keep],
                                  answered: { _, value in got.append(fields(value)) }, failed: { _, error in got.append("error: " + error) })
    if reading { _ = bench.call("start-reading") }
    events.forEach(scanner.say)
    NativeLibraries.shared.stopAll()
    return Array(got.dropFirst())
}

let before = ["kind", "fullName", "dateOfBirth", "expirationDate", "isOver21", "isExpired", "issueCode"]
let four = ["licenseNumber", "sex", "postalCode", "issuingState"]

do {
    check("a read's four more fields reach a page whose endpoint keeps them", handed(keep: before + four, [.result(read())]),
          ["dateOfBirth=1990-01-01 expirationDate=2030-01-01 fullName=Test Person One isExpired=false isOver21=true issuingState=CA kind=read licenseNumber=T1234567 postalCode=99999 sex=F"])
    check("and none of them reaches a page whose endpoint keeps what it kept before", handed(keep: before, [.result(read())]),
          ["dateOfBirth=1990-01-01 expirationDate=2030-01-01 fullName=Test Person One isExpired=false isOver21=true kind=read"])
    check("each reaches a page alone when it alone is named", four.flatMap { handed(keep: ["kind", $0], [.result(read())]) },
          ["kind=read licenseNumber=T1234567", "kind=read sex=F", "kind=read postalCode=99999", "issuingState=CA kind=read"])
    check("an endpoint that keeps nothing is handed nothing of a read", handed(keep: [], [.result(read())]), ["{}"])
    check("a read that failed its validation says them as a read does", handed(keep: ["kind", "issueCode"] + four, [.result(read(.failedValidation, issues: ["EXPIRED"]))]),
          ["issueCode=EXPIRED issuingState=CA kind=failedValidation licenseNumber=T1234567 postalCode=99999 sex=F"])
    check("a repeat says none of them, and neither does a scan nobody reads",
          handed(keep: before + four + ["result"], [.duplicate(read())]) + handed(keep: before + four, [.result(read())], reading: false),
          ["kind=duplicate result=read", "kind=unread"])
}

do {
    check("a document that says none of the four: no such field, and never an empty one",
          handed(keep: ["kind"] + four, [.result(read(number: nil, sex: nil, postal: nil, state: nil)),
                                         .result(read(number: "", sex: "", postal: "", state: "")),
                                         .result(read(number: "  ", sex: " ", postal: "   ", state: " "))]),
          ["kind=read", "kind=read", "kind=read"])
    check("the number and the state are said without the document's padding",
          handed(keep: ["kind", "licenseNumber", "issuingState"], [.result(read(number: " T1234567   ", state: "CA "))]),
          ["issuingState=CA kind=read licenseNumber=T1234567"])
    check("a sex is M, F or X as the document says it; a word that says it is not known is no field",
          ["M", "F", "X", "unknown", "m", "9"].flatMap { handed(keep: ["kind", "sex"], [.result(read(sex: $0))]) },
          ["kind=read sex=M", "kind=read sex=F", "kind=read sex=X", "kind=read", "kind=read", "kind=read"])
    check("a postal code is said without its padding: nine digits whose last four are zeros are the first five, nine others are five and four, and any other is as written",
          ["99999", "999990000", "999990000  ", "999981234", "99998-1234", "99999-0000", "K1A 0B1", "K1A0B1     "].map { IDScannerAdapter.postalCode($0) ?? "none" },
          ["99999", "99999", "99999", "99998-1234", "99998-1234", "99999", "K1A 0B1", "K1A0B1"])
    check("and one that is not there, or only padding, is none", [nil, "", "           "].map { IDScannerAdapter.postalCode($0) ?? "none" },
          ["none", "none", "none"])
}

do {
    // the stand-in: every scripted read gives made-up values for the four,
    // so a lane's rehearsal plays them
    let reads = StandInReader.script().compactMap { event -> ScannerHolder? in
        if case .result(let result) = event { return result.holder }
        return nil
    }
    check("the stand-in's every read says the four, each a made-up value",
          reads.map { [$0.fullName, $0.licenseNumber ?? "none", $0.sex ?? "none", $0.postalCode ?? "none", $0.issuingState ?? "none"].joined(separator: " / ") },
          ["Test Person One / TEST0000001 / F / 999990000 / CA", "Test Person Two / TEST0000002 / M / 99998-1234 / NY",
           "Test Person Three / TEST0000003 / X / 99997 / TX"])
    let reader = StandInReader()
    NativeLibraries.shared.register(IDScannerAdapter(name: "id-reader", scanner: reader))
    var got: [String] = []
    for (id, keep) in [("named", ["kind"] + four), ("not named", ["kind", "fullName"])] {
        NativeLibraries.shared.handle(["id": id, "url": "native://id-reader/events", "listen": true, "keep": keep],
                                      answered: { id, value in got.append(id + ": " + fields(value)) }, failed: { id, error in got.append(id + ": error: " + error) })
    }
    NativeLibraries.shared.handle(["id": "r", "url": "native://id-reader/start-reading", "keep": [String]()], answered: { _, _ in }, failed: { _, _ in })
    reader.press()
    NativeLibraries.shared.stopAll()
    check("a press of the stand-in hands them to the stream whose endpoint names them, tidied, and to no other", last(got, 2).sorted(),
          ["named: issuingState=CA kind=read licenseNumber=TEST0000001 postalCode=99999 sex=F", "not named: fullName=Test Person One kind=read"])
}

do {
    // the binding's template is compiled in no target here (the vendor's
    // package is never in this repository): its text is held to the four
    // fields by the library's own names, so a customer's binding copied
    // from it passes them on
    let template = (try? String(contentsOfFile: "Bindings/VendorIDScanner.swift", encoding: .utf8)) ?? ""
    check("the binding's template passes the four on, by the library's own names",
          ["licenseNumber: $0.licenseNumber", "sex: $0.sex", "postalCode: $0.fields[\"DAK\"]", "issuingState: $0.issuingState"]
              .filter { !template.contains($0) }, [])
    check("and still hands the adapter no raw scan, and no field of the document but the postal code",
          ["scan.raw", "$0.raw", "$0.fields,", "$0.fields)"].filter(template.contains), [])
}

// MARK: the shell prints and keeps nothing of a read

/// A source's lines, each without the space around it.
func lines(_ path: String) -> [String] {
    ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "").split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
}

/// The lines a source prints, and whether each is a development build's alone (inside #if DEBUG).
func printed(_ path: String) -> [(line: String, debug: Bool)] {
    var out: [(String, Bool)] = [], debug = 0
    for line in lines(path) {
        if line.hasPrefix("#if DEBUG") { debug += 1 } else if line.hasPrefix("#endif"), debug > 0 { debug -= 1 }
        if !line.hasPrefix("//"), line.contains("print(") { out.append((line, debug > 0)) }
    }
    return out
}

do {
    let kept = ["UserDefaults", "FileManager", ".write(", "os_log", "NSLog", "Logger(", "SecItem", "Keychain", "dump(", "debugPrint("]
    check("the adapter and the door print nothing and keep nothing: no defaults, no file, no log, no keychain",
          ["Shell/IDScanner.swift", "Shell/NativeLibrary.swift"].flatMap { path in
              (kept + ["print("]).filter { word in lines(path).contains { !$0.hasPrefix("//") && $0.contains(word) } }.map { path + ": " + $0 } }, [])
    check("the stand-in prints one line, a development build's alone, that names the scene played and nothing of a read; it keeps nothing",
          printed("Shell/StandInReader.swift").map { ($0.debug ? "" : "IN EVERY BUILD: ") + $0.line }
              + kept.filter { word in lines("Shell/StandInReader.swift").contains { !$0.hasPrefix("//") && $0.contains(word) } },
          [#"print("stand-in: \(scene)") // a development build says so"#])
    let bridge = printed("Shell/ShellBridge.swift")
    check("every line the bridge prints is a development build's alone", bridge.filter { !$0.debug }.map(\.line), [])
    check("the bridge's line of what a page was handed says the fields' names and never a value, and no other line it prints holds an answer",
          bridge.map(\.line).filter { $0.contains("value") || $0.contains("body") || $0.contains("handed the page") },
          [#"print("shell: \(endpoint) handed the page: \(ShellBridge.names(of: value))")"#])
    check("the names of an answer's fields are its keys alone",
          lines("Shell/ShellBridge.swift").filter { $0.contains("value.keys") }, [#"value.isEmpty ? "nothing" : value.keys.sorted().joined(separator: ", ")"#])
    let template = (try? String(contentsOfFile: "Bindings/VendorIDScanner.swift", encoding: .utf8)) ?? ""
    check("the binding's template reads one element of the document, the postal code, and no second",
          [String(template.components(separatedBy: ".fields[").count - 1), String(template.components(separatedBy: ".fields").count - 1)], ["1", "1"])
}

do {
    check("a read that failed, with no holder, says none of the four: not as an empty word either",
          handed(keep: before + four, [.result(ScannerResult(kind: .failedRead, holder: nil, issueCodes: ["incomplete"]))]),
          ["issueCode=incomplete kind=failedRead"])
    check("ten characters are five and four only with their hyphen after the fifth: a hyphen anywhere else, or two, is a code as written",
          ["9999-90000", "999990-000", "99999-000-", "-999990000"].map { IDScannerAdapter.postalCode($0) ?? "none" },
          ["9999-90000", "999990-000", "99999-000-", "-999990000"])
}

// MARK: a word of the document with new lines in it, or of great length

do {
    check("a word's padding is its spaces, tabs and new lines: the number, the state and the postal code are said without any of them",
          handed(keep: ["kind"] + four, [.result(read(number: "T1234567\n", sex: "F\n", postal: "\t999990000 \r\n", state: "\nCA\t"))]),
          ["issuingState=CA kind=read licenseNumber=T1234567 postalCode=99999 sex=F"])
    check("a word that is only new lines is no field",
          handed(keep: ["kind"] + four, [.result(read(number: "\n", sex: "\n", postal: "\r\n", state: "\n\n"))]), ["kind=read"])
    check("a word with a new line or another mark that is no character inside it is not a word of a document: no field, never a part of it",
          handed(keep: ["kind"] + four, [.result(read(number: "T123\n4567", sex: "F", postal: "99999\u{0}", state: "C\u{7}A"))]), ["kind=read sex=F"])
    let long = String(repeating: "7", count: 64), longer = String(repeating: "7", count: 65)
    check("a word of 64 characters is said whole; one of 65 or of a hundred thousand is no field, never cut: a cut number is another number",
          handed(keep: ["kind", "licenseNumber"], [.result(read(number: long)), .result(read(number: longer)),
                                                   .result(read(number: String(repeating: "9", count: 100_000)))]),
          ["kind=read licenseNumber=" + long, "kind=read", "kind=read"])
    check("the bound is each of the four's: a state or a postal code longer than it is no field",
          handed(keep: ["kind"] + four, [.result(read(number: "T1", sex: "F", postal: longer, state: longer))]), ["kind=read licenseNumber=T1 sex=F"])
    check("text that is no Latin letter, and text that looks like code, is said as written: it is a text, and the shell reads nothing in it",
          handed(keep: ["kind", "licenseNumber", "issuingState"], [.result(read(number: "Ж-12 №7", state: "<b>"))]),
          ["issuingState=<b> kind=read licenseNumber=Ж-12 №7"])
}

// MARK: the scanner's own id

/// A scan by a scanner that says its own id, or what the check gives; a
/// scan that read no document has no holder.
func scan(_ kind: ScannerResult.Kind = .read, by id: String? = "SN-000123", read document: Bool = true, issues: [String] = []) -> ScannerResult {
    var result = document ? read(kind, issues: issues) : ScannerResult(kind: kind, holder: nil, issueCodes: issues)
    result.scannerID = id
    return result
}

do {
    check("the scanner's own id reaches a page whose endpoint keeps it, beside every other field it keeps",
          handed(keep: before + four + ["scannerId"], [.result(scan())]),
          ["dateOfBirth=1990-01-01 expirationDate=2030-01-01 fullName=Test Person One isExpired=false isOver21=true issuingState=CA kind=read licenseNumber=T1234567 postalCode=99999 scannerId=SN-000123 sex=F"])
    check("and does not reach a page whose endpoint keeps what it kept before", handed(keep: before + four, [.result(scan())]),
          ["dateOfBirth=1990-01-01 expirationDate=2030-01-01 fullName=Test Person One isExpired=false isOver21=true issuingState=CA kind=read licenseNumber=T1234567 postalCode=99999 sex=F"])
    check("it reaches a page alone when it alone is named", handed(keep: ["scannerId"], [.result(scan())]), ["scannerId=SN-000123"])
    check("it is the scan's, not the holder's: a scan that read no document says it, and so does a read that failed its validation",
          handed(keep: ["kind", "issueCode", "scannerId"], [.result(scan(.failedRead, read: false, issues: ["incomplete"])),
                                                            .result(scan(.failedValidation, issues: ["EXPIRED"])),
                                                            .result(scan(.failedValidation, read: false, issues: ["NOT_AAMVA"]))]),
          ["issueCode=incomplete kind=failedRead scannerId=SN-000123", "issueCode=EXPIRED kind=failedValidation scannerId=SN-000123",
           "issueCode=NOT_AAMVA kind=failedValidation scannerId=SN-000123"])
    check("a repeat does not say it, and neither does a scan nobody reads",
          handed(keep: ["kind", "result", "scannerId"], [.duplicate(scan())]) + handed(keep: ["kind", "scannerId"], [.result(scan())], reading: false),
          ["kind=duplicate result=read", "kind=unread"])
    check("a scanner that gives no id: no such field, and never an empty one",
          handed(keep: ["kind", "scannerId"], [.result(scan(by: nil)), .result(scan(by: "")), .result(scan(by: "  \n"))]),
          ["kind=read", "kind=read", "kind=read"])
    check("it is said without padding, and one with a mark that is no character inside it, or longer than a word may be, is no field",
          handed(keep: ["kind", "scannerId"], [.result(scan(by: " SN-000123\r\n")), .result(scan(by: "SN\u{0}123")),
                                               .result(scan(by: String(repeating: "7", count: 65)))]),
          ["kind=read scannerId=SN-000123", "kind=read", "kind=read"])
    check("a result made as a binding copied before this makes it (no id passed) says none",
          handed(keep: ["kind", "scannerId"], [.result(ScannerResult(kind: .failedRead, holder: nil, issueCodes: []))]), ["kind=failedRead"])
    check("the state, the battery and a warning do not say it",
          handed(keep: ["kind", "state", "battery", "warning", "scannerId"], [.battery(40), .warning(.lowBattery), .connection("reconnecting", away: .outOfRange)])
              .filter { $0.contains("scannerId") }, [])
}

do {
    // the stand-in: its made-up scanner has an id, said with every scan
    // that is not a repeat, so a lane's rehearsal plays it
    let ids = StandInReader.script().compactMap { event -> String? in
        switch event {
        case .result(let result): return result.kind.rawValue + " by " + (result.scannerID ?? "none")
        case .duplicate(let result): return "a repeat by " + (result.scannerID ?? "none")
        default: return nil
        }
    }
    check("the stand-in's every scan is by its made-up scanner",
          ids, ["read by TEST-SCANNER-0001", "a repeat by TEST-SCANNER-0001", "failedRead by TEST-SCANNER-0001", "failedValidation by TEST-SCANNER-0001",
                "failedValidation by TEST-SCANNER-0001", "failedValidation by TEST-SCANNER-0001"])
    let reader = StandInReader()
    NativeLibraries.shared.register(IDScannerAdapter(name: "id-reader", scanner: reader))
    var got: [String] = []
    for (id, keep) in [("named", ["kind", "scannerId"]), ("not named", ["kind", "fullName"])] {
        NativeLibraries.shared.handle(["id": id, "url": "native://id-reader/events", "listen": true, "keep": keep],
                                      answered: { id, value in got.append(id + ": " + fields(value)) }, failed: { id, error in got.append(id + ": error: " + error) })
    }
    NativeLibraries.shared.handle(["id": "r", "url": "native://id-reader/start-reading", "keep": [String]()], answered: { _, _ in }, failed: { _, _ in })
    reader.press()
    NativeLibraries.shared.stopAll()
    check("a press of the stand-in hands its scanner's id to the stream whose endpoint names it, and to no other", last(got, 2).sorted(),
          ["named: kind=read scannerId=TEST-SCANNER-0001", "not named: fullName=Test Person One kind=read"])
}

do {
    // the binding's template, compiled in no target here: its text is held
    // to the scanner's serial by the package's own name, and to never
    // passing the phone's own name for the scanner in its place
    let template = (try? String(contentsOfFile: "Bindings/VendorIDScanner.swift", encoding: .utf8)) ?? ""
    check("the binding's template passes on the scanner's own serial, by the package's own name",
          ["scannerID: scan.identity.serial"].filter { !template.contains($0) }, [])
    check("and never the phone's own name for the scanner in its place",
          ["scannerID: scan.identity.peripheralId", "?? scan.identity.peripheralId"].filter(template.contains), [])
}

// MARK: a word's bound holds its bytes too

do {
    // marks piled on one letter are one character as a person reads it: a
    // word of one letter and five thousand marks is "one character long"
    let piled = "S" + String(repeating: "\u{0301}", count: 5_000)
    check("a scanner's id of one letter under five thousand marks (one character, ten thousand bytes) is no field",
          handed(keep: ["kind", "scannerId"], [.result(scan(by: piled))]), ["kind=read"])
    check("and neither is a document's word so written, any of the four",
          handed(keep: ["kind"] + four, [.result(read(number: piled, sex: "F" + String(repeating: "\u{0301}", count: 300), postal: piled, state: piled))]), ["kind=read"])
    // the bound in bytes is four for each character a word may have: a word
    // of 64 characters of the longest kind fits, whole
    let widest = String(repeating: "\u{1D7DF}", count: 64) // a digit written in four bytes
    check("a word of 64 characters of four bytes each (256 bytes) is said whole",
          handed(keep: ["kind", "scannerId", "licenseNumber"], [.result({ var r = read(number: widest); r.scannerID = widest; return r }())]),
          ["kind=read licenseNumber=" + widest + " scannerId=" + widest])
    check("one mark more on its last character (still 64 characters, 258 bytes) is no field, never cut",
          handed(keep: ["kind", "scannerId"], [.result(scan(by: widest + "\u{0301}"))]), ["kind=read"])
    check("a word of letters with their marks, as a name is written, is said as written",
          handed(keep: ["kind", "scannerId"], [.result(scan(by: "SE\u{0301}RIE-A\u{030A}-0042"))]), ["kind=read scannerId=SE\u{0301}RIE-A\u{030A}-0042"])
}

print("reader: \(passed) passed, \(failed) failed")
if failed > 0 { exit(1) }

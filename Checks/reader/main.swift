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
          ["dateOfBirth=1990-01-01 expirationDate=2030-01-01 fullName=Test Person One isExpired=false isOver21=true kind=read",
           "kind=duplicate result=read"])
    _ = bench.call("stop-reading")
    count = bench.heard.count
    scanner.say(.result(ScannerResult(kind: .failedRead, holder: nil, issueCodes: ["incomplete"])))
    check("reading stopped: a scan is unread again, whatever its kind", Array(bench.heard[count...]), ["kind=unread"])
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
    check("and scans again", [String(last(bench.heard, 1)[0].hasPrefix("dateOfBirth="))], ["true"])
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

print("reader: \(passed) passed, \(failed) failed")
if failed > 0 { exit(1) }

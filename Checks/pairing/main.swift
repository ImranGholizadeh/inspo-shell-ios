// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

// A check of a first pairing (Shell/IDScanner.swift, and the stand-in's
// played one, Shell/StandInReader.swift) on this Mac, with a scanner that
// only records what it was asked and a clock the check moves (no phone, no
// simulator, no scanner): scripts/check-pairing.sh. The clock, the scanner
// and the bench are Checks/Bench.swift, shared with the reader's check.

import Foundation
import IDScannerSurface

// MARK: the steps, in order

do {
    let (scanner, bench) = recorded()
    let answer = bench.call("start-pairing", ["venue": "v1", "door": "d1", "doorName": "Front door", "phone": "p1"])
    check("start-pairing answers at once, looking", [answer], ["pairing looking"])
    scanner.say(.connection("scanning"))
    scanner.hear("A", -60)
    scanner.hear("A", -58)
    bench.clock.pass(3)
    scanner.say(.connection("connecting"))
    scanner.say(.connection("connected"))
    scanner.connectDone?(nil)
    scanner.say(.confirming)
    scanner.say(.connection("reading")) // the confirming scan, read by the package
    scanner.say(.connection("connected"))
    scanner.pairDone?(nil)
    check("the steps come on the stream in order, among the states, and no scanner heard is passed on", bench.heard,
          ["state idle +paired", "pairing looking", "state scanning +paired", "pairing connecting", "state connecting +paired",
           "state connected +paired", "pairing confirm", "pairing paired"])
    check("the scanner is asked to pair at the gene's place (the phone is the shell's to say: none on a Mac), then to connect the pick, and nothing else",
          scanner.asked, ["pair v1/d1/Front door/", "connect A"])
    bench.clock.pass(100)
    scanner.hear("B", -30)
    scanner.say(.confirming)
    scanner.pairDone?(.stopped)
    check("a paired pairing is over: no limit of it fails later, and nothing more is heard of it",
          last(bench.heard, 1) + last(scanner.asked, 1), ["pairing paired", "connect A"])
}

do {
    let (scanner, bench) = recorded()
    _ = bench.call("start-pairing")
    _ = bench.call("stop-pairing")
    _ = bench.call("start-pairing", ["venue": 7, "door": ["x"], "doorName": "Side door"])
    _ = bench.call("stop-pairing")
    _ = bench.call("start-pairing", "text")
    check("what the gene does not give of the place is empty, and only text is taken",
          scanner.asked.filter { $0.hasPrefix("pair") }, ["pair ///", "pair //Side door/", "pair ///"])
}

// MARK: the nearest pick

do {
    let (scanner, bench) = recorded()
    _ = bench.call("start-pairing")
    scanner.hear("A", -70)
    bench.clock.pass(1)
    scanner.hear("B", -50)
    bench.clock.pass(1.9)
    check("nothing is picked while the window runs", scanner.asked + last(bench.heard, 1), ["pair ///", "pairing looking"])
    bench.clock.pass(0.2)
    check("the strongest signal is picked when the window ends, three seconds after the first scanner was heard",
          scanner.asked + last(bench.heard, 1), ["pair ///", "connect B", "pairing connecting"])
}

do {
    let (scanner, bench) = recorded()
    _ = bench.call("start-pairing")
    scanner.hear("A", -40)
    scanner.hear("B", -60)
    scanner.hear("A", -80) // the person walked away with it
    bench.clock.pass(3)
    check("a scanner's latest signal is the one that counts", scanner.asked, ["pair ///", "connect B"])
}

do {
    var picks: [String] = []
    for order in [["A", "B", "C"], ["C", "B", "A"]] {
        let (scanner, bench) = recorded()
        _ = bench.call("start-pairing")
        order.forEach { scanner.hear($0, $0 == "B" ? -70 : -55) }
        bench.clock.pass(3)
        picks += last(scanner.asked, 1)
    }
    check("of two equally strong, the first heard is picked", picks, ["connect A", "connect C"])
}

do {
    let (scanner, bench) = recorded()
    _ = bench.call("start-pairing")
    bench.clock.pass(14)
    scanner.hear("A", -60)
    bench.clock.pass(2.9)
    check("a scanner heard late still gets its whole window: none-found does not fail it",
          scanner.asked + last(bench.heard, 1), ["pair ///", "pairing looking"])
    bench.clock.pass(0.2)
    check("and is picked when its window ends", scanner.asked + last(bench.heard, 1),
          ["pair ///", "connect A", "pairing connecting"])
}

// MARK: the time limits

do {
    let (scanner, bench) = recorded()
    _ = bench.call("start-pairing")
    bench.clock.pass(14.9)
    check("looking goes on for fifteen seconds", scanner.asked + last(bench.heard, 1), ["pair ///", "pairing looking"])
    bench.clock.pass(0.2)
    check("no scanner heard in fifteen seconds fails as none-found, and the package's looking is stopped",
          scanner.asked + last(bench.heard, 1), ["pair ///", "stop", "pairing failed none-found"])
    scanner.pairDone?(.stopped)
    scanner.hear("A", -40)
    bench.clock.pass(100)
    check("a failed pairing is over: nothing more comes of it", scanner.asked + last(bench.heard, 1),
          ["pair ///", "stop", "pairing failed none-found"])
}

do {
    let (scanner, bench) = connecting()
    bench.clock.pass(9.9)
    check("the pick has ten seconds to connect", scanner.asked + last(bench.heard, 1),
          ["pair ///", "connect A", "pairing connecting"])
    bench.clock.pass(0.2)
    check("a pick that does not connect in ten seconds fails as not-connected, and is forgotten",
          scanner.asked + last(bench.heard, 1), ["pair ///", "connect A", "stop", "forget A", "pairing failed not-connected"])
}

do {
    let (scanner, bench) = connecting()
    scanner.connectDone?(Refused())
    check("a pick whose connect fails is not-connected at once", scanner.asked + last(bench.heard, 1),
          ["pair ///", "connect A", "stop", "forget A", "pairing failed not-connected"])
}

do {
    let (scanner, bench) = confirming()
    bench.clock.pass(29.9)
    check("the person has thirty seconds to scan", scanner.asked + last(bench.heard, 1),
          ["pair ///", "connect A", "pairing confirm"])
    bench.clock.pass(0.2)
    check("no confirming scan in thirty seconds fails as not-confirmed, and the pick is forgotten",
          scanner.asked + last(bench.heard, 1), ["pair ///", "connect A", "stop", "forget A", "pairing failed not-confirmed"])
}

do {
    let (scanner, bench) = confirming(paired: ["A"])
    bench.clock.pass(30)
    check("a scanner that was paired before the pairing began is not forgotten when it fails",
          scanner.asked + last(bench.heard, 1), ["pair ///", "connect A", "stop", "pairing failed not-confirmed"])
}

// MARK: stopping

do {
    let (scanner, bench) = recorded()
    let idle = bench.call("stop-pairing")
    check("stop-pairing with no pairing answers, and asks and tells nothing", [idle] + scanner.asked + bench.heard,
          ["{}", "state idle +paired"])
    _ = bench.call("start-pairing")
    let stopped = bench.call("stop-pairing")
    check("stop-pairing while it looks: failed, stopped, and no scanner to forget",
          [stopped] + scanner.asked + last(bench.heard, 1), ["{}", "pair ///", "stop", "pairing failed stopped"])
    scanner.pairDone?(.stopped)
    bench.clock.pass(100)
    check("the package's own word of the stop, and the limits of the stopped pairing, add nothing",
          last(bench.heard, 2), ["pairing looking", "pairing failed stopped"])
}

do {
    let (scanner, bench) = confirming()
    _ = bench.call("stop-pairing")
    check("stop-pairing while it waits for the scan: the pick is forgotten", scanner.asked + last(bench.heard, 1),
          ["pair ///", "connect A", "stop", "forget A", "pairing failed stopped"])
}

do {
    let (scanner, bench) = connecting()
    let (firstEnd, firstConnect) = (scanner.pairDone, scanner.connectDone)
    _ = bench.call("stop-pairing")
    _ = bench.call("start-pairing")
    firstEnd?(.stopped) // the package's word of the first one's stop comes late
    firstConnect?(Refused())
    scanner.hear("B", -60)
    bench.clock.pass(3)
    check("a stopped pairing's late end does not touch the one started after it", last(bench.heard, 3) + last(scanner.asked, 1),
          ["pairing failed stopped", "pairing looking", "pairing connecting", "connect B"])
}

// MARK: a second pairing while one runs

do {
    let (scanner, bench) = connecting()
    let second = bench.call("start-pairing", ["venue": "other"])
    check("a second start-pairing answers the step of the one that runs", [second], ["pairing connecting"])
    check("and starts nothing: the scanner is asked to pair once, the stream hears no second looking",
          scanner.asked + bench.heard, ["pair ///", "connect A", "state idle +paired", "pairing looking", "pairing connecting"])
    scanner.connectDone?(nil)
    scanner.say(.confirming)
    scanner.pairDone?(nil)
    check("the first goes on to paired", last(bench.heard, 2), ["pairing confirm", "pairing paired"])
    let third = bench.call("start-pairing", ["venue": "other"])
    check("once it is over, start-pairing starts a new one", [third] + last(scanner.asked, 1) + last(bench.heard, 1),
          ["pairing looking", "pair other///", "pairing looking"])
}

// MARK: the reasons

do {
    var reasons: [String] = []
    for failure in [ScannerPairingFailure.bluetoothOff, .bluetoothNotAllowed, .stopped] {
        let (scanner, bench) = recorded()
        _ = bench.call("start-pairing")
        scanner.pairDone?(failure)
        reasons += last(bench.heard, 1) + last(scanner.asked, 1)
    }
    check("Bluetooth off and not allowed are told as the package says them; its giving up while it looks is none-found",
          reasons, ["pairing failed bluetooth-off", "stop", "pairing failed bluetooth-not-allowed", "stop",
                    "pairing failed none-found", "stop"])
}

do {
    let (scanner, bench) = connecting()
    scanner.pairDone?(.stopped)
    let (later, bench2) = confirming()
    later.pairDone?(.stopped)
    check("the package giving up is named by the step reached: not-connected, not-confirmed",
          last(bench.heard, 1) + last(scanner.asked, 1) + last(bench2.heard, 1) + last(later.asked, 1),
          ["pairing failed not-connected", "forget A", "pairing failed not-confirmed", "forget A"])
}

// MARK: the streams

do {
    let (scanner, bench) = recorded(stream: false)
    _ = bench.call("start-pairing")
    scanner.say(.connection("scanning"))
    scanner.hear("A", -60)
    bench.clock.pass(3)
    bench.open()
    check("a stream opened while a pairing runs hears its step after its first state", bench.heard,
          ["state scanning +paired", "pairing connecting"])
}

do {
    let (scanner, bench) = recorded(stream: false)
    NativeLibraries.shared.register(bench.adapter)
    var kept: [String] = []
    let take: (String, [String: Any]) -> Void = { id, value in kept.append(id + ": " + words(value)) }
    let fail: (String, String) -> Void = { id, error in kept.append(id + ": error: " + error) }
    NativeLibraries.shared.handle(["id": "s", "url": "native://id-reader/events", "listen": true, "keep": ["kind", "step"]],
                                  answered: take, failed: fail)
    NativeLibraries.shared.handle(["id": "c", "url": "native://id-reader/start-pairing", "keep": [String]()],
                                  answered: take, failed: fail)
    scanner.pairDone?(.bluetoothOff)
    NativeLibraries.shared.stopAll()
    check("only the fields an endpoint's keep names leave the shell: a stream that keeps no reason gets none, a call that keeps nothing gets nothing",
          kept, ["s: state", "c: {}", "s: pairing looking", "s: pairing failed"])
}

// MARK: a scanner already connected

do {
    let (scanner, bench) = recorded(paired: ["A"])
    scanner.say(.connection("connected"))
    let answer = bench.call("start-pairing", ["venue": "v1", "door": "d1"])
    check("with a scanner connected, start-pairing answers failed, already-connected, and the stream says so",
          [answer] + last(bench.heard, 1), ["pairing failed already-connected", "pairing failed already-connected"])
    check("and the scanner is asked nothing: the one that works is not dropped", scanner.asked, [])
    scanner.say(.connection("reading"))
    check("a scanner that is reading is connected too", [bench.call("start-pairing")], ["pairing failed already-connected"])
    bench.clock.pass(100)
    check("no limit of a refused pairing fails later", last(bench.heard, 1), ["pairing failed already-connected"])
    scanner.say(.connection("disconnected"))
    check("once it is no longer connected a pairing starts", [bench.call("start-pairing")] + scanner.asked,
          ["pairing looking", "pair ///"])
}

// MARK: the stand-in's played pairing

func standIn() -> (StandInReader, Bench) {
    let reader = StandInReader()
    let bench = Bench(reader)
    reader.wait = bench.clock.wait
    _ = bench.call("start-reading")
    return (reader, bench)
}

do {
    let (reader, bench) = standIn()
    _ = bench.call("start-pairing")
    bench.clock.pass(1)
    bench.clock.pass(2.9)
    check("the stand-in looks for a second, and the window runs", bench.heard, ["state connected +paired", "pairing looking"])
    bench.clock.pass(0.1)
    bench.clock.pass(0.8)
    check("the stand-in's near scanner is picked and connects, and it waits for the confirming scan", last(bench.heard, 4),
          ["pairing connecting", "state connecting +paired", "state connected +paired", "pairing confirm"])
    reader.press()
    bench.clock.pass(0.5)
    check("a press while it waits is the confirming scan: paired, and no scan is played", last(bench.heard, 2),
          ["pairing confirm", "pairing paired"])
    reader.press()
    check("the script has not moved: the next press plays its first event", last(bench.heard, 1),
          ["read +dateOfBirth+expirationDate+fullName+isExpired+isOver21"])
}

do {
    let (reader, bench) = standIn()
    _ = bench.call("start-pairing")
    reader.press()
    bench.clock.pass(4.8)
    bench.clock.pass(30)
    check("a press before it waits is a scan as ever; with no press after, the stand-in's pairing fails as not-confirmed",
          bench.heard.filter { !$0.hasPrefix("state") },
          ["pairing looking", "read +dateOfBirth+expirationDate+fullName+isExpired+isOver21", "pairing connecting",
           "pairing confirm", "pairing failed not-confirmed"])
    _ = bench.call("start-pairing")
    bench.clock.pass(4)
    _ = bench.call("stop-pairing")
    bench.clock.pass(100)
    check("stopped while the stand-in connects: failed, stopped, and its link is back", last(bench.heard, 4),
          ["pairing connecting", "state connecting +paired", "state connected +paired", "pairing failed stopped"])
    let state = bench.call("state")
    let again = bench.call("reconnect")
    check("the stand-in stays paired and connected after a failed pairing", [state, again], ["state connected +battery+paired", "{}"])
}

print("pairing: \(passed) passed, \(failed) failed")
if failed > 0 { exit(1) }

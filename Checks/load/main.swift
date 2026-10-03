// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

// A check of Shell/LoadAgain.swift on this Mac, with a clock moved by hand
// (no phone, no simulator, no network): scripts/check-load.sh.

import Foundation

var passed = 0, failed = 0
func check<T: Equatable>(_ name: String, _ got: T, _ want: T) {
    if got == want { passed += 1 } else { failed += 1; print("FAIL \(name): got \(got), want \(want)") }
}

/// The waits asked for, each run by hand.
final class Waits {
    struct Wait { let seconds: TimeInterval; let block: () -> Void; var cancelled = false }
    var asked: [Wait] = []
    func schedule(_ seconds: TimeInterval, _ block: @escaping () -> Void) -> () -> Void {
        let at = asked.count
        asked.append(Wait(seconds: seconds, block: block))
        return { [weak self] in self?.asked[at].cancelled = true }
    }
    /// The last wait ends, unless it was cancelled.
    func end() { if let last = asked.last, !last.cancelled { last.block() } }
    var seconds: [TimeInterval] { asked.map(\.seconds) }
}

do {
    let waits = Waits()
    var loads = 0
    let again = LoadAgain(load: { loads += 1 }, schedule: waits.schedule)
    check("nothing waits before a load fails", again.waiting, false)
    again.wake()
    check("the network back with nothing waiting loads nothing", loads, 0)

    // an app opened with no signal: each try fails, and the wait doubles to its longest
    again.failed()
    check("a load that fails waits a second", waits.seconds, [1])
    check("and is waiting", again.waiting, true)
    waits.end()
    check("then it is loaded again", loads, 1)
    for _ in 0..<6 { again.failed(); waits.end() }
    check("the wait doubles to fifteen seconds and no further", waits.seconds, [1, 2, 4, 8, 15, 15, 15])
    check("each wait's end is one load", loads, 7)

    // the system says the network is back: the load that waits goes now, once
    again.failed()
    again.wake()
    check("the network back loads at once", loads, 8)
    check("and the wait it cut short is cancelled", waits.asked.last?.cancelled, true)
    waits.asked.last?.block() // a timer that fires all the same
    again.wake()
    check("once", loads, 8)
    check("nothing waits while the page loads", again.waiting, false)

    // the page loads: the next failure starts from the first wait
    again.loaded()
    again.failed()
    check("after a page that loaded, the wait is a second again", waits.seconds.last, 1)
    again.loaded()
    check("a page that loaded while a try waited: nothing waits", again.waiting, false)
    waits.end()
    check("and nothing is loaded over it", loads, 8)

    // two failures told for one try (the request, then the page): one wait
    again.failed()
    again.failed()
    check("a second failure replaces the wait, it does not add one", waits.asked.suffix(2).map(\.cancelled), [true, false])

    check("the waits by failures in a row", (1...7).map { LoadAgain.wait(afterFailures: $0) }, [1, 2, 4, 8, 15, 15, 15])
    check("a count no wait could reach is the longest", LoadAgain.wait(afterFailures: 100_000), 15)
}

print("\(passed)/\(passed + failed) passed")
exit(failed == 0 ? 0 : 1)

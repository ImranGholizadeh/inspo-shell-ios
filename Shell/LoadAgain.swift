// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

import Foundation

// Loading again a page that did not load (owner, 2026-10-03: an app opened
// with no signal is a real door's case). The shell loaded its page once: an
// app opened out of signal, or brought back by iOS while out of signal, was
// left on an empty view and never loaded when the signal returned, until it
// was quit and opened by hand.
//
// A load that fails is tried again after a wait that doubles from firstWait
// to longestWait, for as long as it takes; and at once, whatever is left of
// the wait, when the system says the network is back or the app comes to
// the front. The timer alone would leave a person waiting up to the longest
// wait after the signal is back; the system's word alone is not enough,
// since a network that is "there" may still not reach the page (a Wi-Fi
// with no way out, a mine that is restarting), and then nothing would ever
// say "back". A page that loads puts the wait back to the first.
//
// Nothing here knows a web view: load is what loads the page, schedule runs
// a block after a wait and returns what cancels it, so the timing is
// checked on a Mac with no phone (scripts/check-load.sh).
final class LoadAgain {
    static let firstWait: TimeInterval = 1
    static let longestWait: TimeInterval = 15

    private let load: () -> Void
    private let schedule: (TimeInterval, @escaping () -> Void) -> () -> Void
    private var failures = 0
    private var cancel: (() -> Void)?

    /// Whether a load is waiting to be tried again.
    var waiting: Bool { cancel != nil }

    init(load: @escaping () -> Void,
         schedule: @escaping (TimeInterval, @escaping () -> Void) -> () -> Void = LoadAgain.after) {
        self.load = load
        self.schedule = schedule
    }

    /// The wait before the try that follows the nth failure in a row.
    static func wait(afterFailures n: Int) -> TimeInterval {
        min(longestWait, firstWait * pow(2, Double(max(0, min(n, 16) - 1))))
    }

    /// A load failed: it is tried again after the wait.
    func failed() {
        failures += 1
        cancel?()
        cancel = schedule(LoadAgain.wait(afterFailures: failures)) { [weak self] in
            guard let self, self.cancel != nil else { return }
            self.cancel = nil
            self.load()
        }
    }

    /// The page loaded: nothing waits, and the next failure waits the first wait.
    func loaded() {
        failures = 0
        cancel?()
        cancel = nil
    }

    /// The network is back, or the app came to the front: a load that
    /// waits is tried now. With none waiting, nothing is loaded.
    func wake() {
        guard let stop = cancel else { return }
        stop()
        cancel = nil
        load()
    }

    /// Runs a block on the main queue after a wait; what it returns cancels it.
    static func after(_ wait: TimeInterval, _ block: @escaping () -> Void) -> () -> Void {
        let work = DispatchWorkItem(block: block)
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
        return { work.cancel() }
    }
}

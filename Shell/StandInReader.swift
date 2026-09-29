// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

import AVFoundation
import UIKit

// A stand-in for a native library, for tests without the device (owner,
// 2026-09-30, E42: "Shell stand-in + Go tests"): a build whose
// INSPO_NATIVE_STAND_IN names a library (id-reader) carries this in its
// place, behind the same protocol and path, so the gene's records run
// unchanged. Its calls succeed (a state call answers connected; a feedback
// call plays a light haptic), and a stream reports connected, then one
// scripted result per press of either volume button (owner: "simulate
// scans using maybe the side button on the phone"; iOS lets an app hear the
// volume buttons, never the side button). The script is made-up people
// only, never a real ID.

final class StandInReader: NSObject, NativeLibrary {
    let name: String
    private var next = 0
    private var listeners: [UUID: ([String: Any]) -> Void] = [:]
    private var observation: NSKeyValueObservation?

    /// The results a press plays, in turn: every kind a reader answers.
    static let script: [[String: Any]] = [
        ["kind": "read", "fullName": "Test Person One", "dateOfBirth": "1990-04-12", "expirationDate": "2030-04-12",
         "issuingState": "GA", "age": 36, "isOver21": true, "isExpired": false],
        ["kind": "failedRead"],
        ["kind": "read", "fullName": "Test Person Two", "dateOfBirth": "2008-01-02", "expirationDate": "2031-01-02",
         "issuingState": "NY", "age": 18, "isOver21": false, "isExpired": false],
        ["kind": "read", "fullName": "Test Person Three", "dateOfBirth": "1985-07-30", "expirationDate": "2024-07-30",
         "issuingState": "FL", "age": 41, "isOver21": true, "isExpired": true],
        ["kind": "failedValidation"],
    ]

    init(name: String) {
        self.name = name
    }

    /// The stand-in the build names, if any.
    static func fromBuild() -> StandInReader? {
        guard let name = Bundle.main.object(forInfoDictionaryKey: "InspoNativeStandIn") as? String,
              !name.isEmpty else { return nil }
        return StandInReader(name: name)
    }

    func call(_ call: String, data: Any?, answer: @escaping (Result<[String: Any], NativeError>) -> Void) {
        switch call {
        case "state", "status":
            answer(.success(["kind": "state", "state": "connected", "battery": 90]))
        case "feedback":
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            answer(.success([:]))
        default:
            answer(.success([:]))
        }
    }

    func listen(_ events: String, data: Any?, each: @escaping ([String: Any]) -> Void,
                failed: @escaping (NativeError) -> Void) -> () -> Void {
        let key = UUID()
        listeners[key] = each
        each(["kind": "state", "state": "connected"])
        followVolume()
        return { [weak self] in
            self?.listeners.removeValue(forKey: key)
            if self?.listeners.isEmpty == true {
                self?.observation = nil
            }
        }
    }

    /// Either volume button plays the next result to every stream.
    private func followVolume() {
        guard observation == nil else { return }
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.ambient, options: [.mixWithOthers])
        try? audio.setActive(true)
        observation = audio.observe(\.outputVolume, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.press() }
        }
    }

    private func press() {
        let result = Self.script[next % Self.script.count]
        next += 1
        listeners.values.forEach { $0(result) }
    }
}

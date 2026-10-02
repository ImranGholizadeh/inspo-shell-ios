// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

import AVFoundation

// The phone's light, for the device neuron's torch (owner, 2026-10-02: "Go
// fires, renderer acts"). iOS gives a page no light, so the page hands the
// shell one request and the shell switches it:
//
//   { type: "torch", mode: "on" }    the light on
//   { type: "torch", mode: "off" }   the light off
//
// Nothing is answered: Go took the neuron's hop when it asked, and a device
// with no light (an iPad without one, a simulator) switches nothing. A light
// the shell lit is put out when its page goes (a reload, a page that ended)
// and when the app leaves the screen, so no light stays on with no page to
// put it out; a light the person lit themselves is left alone.

/// A light the shell can switch: the phone's own, or a test's.
protocol TorchLight {
    /// Switches the light; false when it could not be switched.
    func switchTorch(on: Bool) -> Bool
}

/// The light the page asks for, and whether the shell lit it.
final class Torch {
    static let shared = Torch()
    /// The phone's light, looked for at each request; none where there is none.
    var light: () -> TorchLight? = { AVCaptureDevice.default(for: .video) }
    private(set) var lit = false

    /// Takes the page's request; a mode other than on or off switches nothing.
    func take(mode: String) {
        switch mode {
        case "on":
            lit = light()?.switchTorch(on: true) ?? false
        case "off":
            _ = light()?.switchTorch(on: false)
            lit = false
        default:
            break
        }
    }

    /// Puts out a light the shell lit: its page has gone, or the app has
    /// left the screen.
    func putOut() {
        guard lit else { return }
        take(mode: "off")
    }
}

extension AVCaptureDevice: TorchLight {
    func switchTorch(on: Bool) -> Bool {
        guard hasTorch, !on || (isTorchAvailable && isTorchModeSupported(.on)) else { return false }
        do {
            try lockForConfiguration()
            defer { unlockForConfiguration() }
            torchMode = on ? .on : .off
            return true
        } catch {
            return false
        }
    }
}

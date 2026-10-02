// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

// A check of Shell/Torch.swift on this Mac, with a light that only records
// what it was asked (no phone, no simulator): scripts/check-torch.sh.

import Foundation

final class RecordedLight: TorchLight {
    var asked: [Bool] = []
    var switches = true
    func switchTorch(on: Bool) -> Bool {
        asked.append(on)
        return switches
    }
}

var passed = 0, failed = 0
func check(_ name: String, _ got: [Bool], _ want: [Bool]) {
    if got == want { passed += 1 } else { failed += 1; print("FAIL \(name): got \(got), want \(want)") }
}

do {
    let light = RecordedLight()
    let torch = Torch()
    torch.light = { light }
    torch.putOut()
    check("a light the shell did not light is left alone", light.asked + [torch.lit], [false])
    torch.take(mode: "on")
    check("on switches the light on", light.asked + [torch.lit], [true, true])
    torch.take(mode: "blink")
    torch.take(mode: "")
    check("an unknown mode switches nothing", light.asked + [torch.lit], [true, true])
    torch.take(mode: "off")
    check("off switches it off", light.asked + [torch.lit], [true, false, false])
    torch.take(mode: "off")
    check("off is switched whoever lit the light", light.asked, [true, false, false])
    torch.take(mode: "on")
    torch.putOut()
    check("a light the shell lit is put out", light.asked + [torch.lit], [true, false, false, true, false, false])
    torch.putOut()
    check("and put out once", light.asked.count == 5 ? [true] : [false], [true])
}

do {
    let light = RecordedLight()
    light.switches = false
    let torch = Torch()
    torch.light = { light }
    torch.take(mode: "on")
    torch.putOut()
    check("a light that would not switch is not the shell's to put out", light.asked + [torch.lit], [true, false])
}

do {
    let torch = Torch()
    torch.light = { nil }
    torch.take(mode: "on")
    torch.take(mode: "off")
    torch.putOut()
    check("a device with no light switches nothing", [torch.lit], [false])
}

print("torch: \(passed) passed, \(failed) failed")
if failed > 0 { exit(1) }

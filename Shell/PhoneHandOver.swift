// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

import AudioToolbox
import UIKit

// The phone's own share sheet, clipboard and long vibration: what
// HandOver.swift and the bridge's haptic reach for. Nothing here decides
// anything; the rules are HandOver's, and scripts/check-share.sh holds them
// on a Mac with a sheet and a clipboard that only record.

/// iOS's share sheet, shown over the view the page is drawn in.
final class PhoneShareSheet: ShareSheet {
    private weak var view: UIView?

    init(over view: UIView) { self.view = view }

    func open(_ items: [SharedItem], closed: @escaping () -> Void) -> Bool {
        guard let view, var top = view.window?.rootViewController else { return false }
        while let next = top.presentedViewController { top = next }
        // a sheet iOS still shows is not opened over
        guard !(top is UIActivityViewController) else { return false }
        let things: [Any] = items.map { item in
            switch item {
            case .text(let text): return text
            case .link(let url), .file(let url): return url
            }
        }
        let sheet = UIActivityViewController(activityItems: things, applicationActivities: nil)
        // shared or put away: iOS says which, and the page is told only that it closed
        sheet.completionWithItemsHandler = { _, _, _, _ in closed() }
        // an iPad shows the sheet as a popover, which needs a place: the middle of the page
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        top.present(sheet, animated: true)
        return true
    }
}

/// iOS's clipboard.
struct PhoneClipboard: Clipboard {
    func hold(_ text: String) { UIPasteboard.general.string = text }
}

/// The system's own long vibration (the haptic's mode vibrate): about 0.4 s
/// of the phone's motor, as a message's. It plays on silent too, unless the
/// person switched vibration off in Settings; a device with no motor (an
/// iPad, a simulator) plays nothing.
func playLongVibration() {
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
}

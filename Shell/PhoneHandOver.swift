// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

import AudioToolbox
import UIKit
import UniformTypeIdentifiers

// The phone's own share sheet, clipboard and long vibration: what
// HandOver.swift and the bridge's haptic reach for. Nothing here decides
// anything; the rules are HandOver's, and scripts/check-share.sh holds them
// on a Mac with a sheet and a clipboard that only record.

/// iOS's share sheet, shown over the view the page is drawn in.
final class PhoneShareSheet: ShareSheet {
    private weak var view: UIView?
    private weak var sheet: UIActivityViewController?
    private var opening = false

    init(over view: UIView) { self.view = view }

    var showing: Bool { opening || sheet?.presentingViewController != nil }

    func open(_ items: [SharedItem], ended: @escaping (_ shown: Bool) -> Void) {
        guard let view, var top = view.window?.rootViewController else { return ended(false) }
        // the controller on top, not counting one on its way out
        var leaving: UIViewController?
        while let next = top.presentedViewController {
            if next.isBeingDismissed { leaving = next; break }
            top = next
        }
        // a sheet iOS still shows is not opened over
        guard !(top is UIActivityViewController) else { return ended(false) }
        let things: [Any] = items.map { item in
            switch item {
            case .text(let text): return text
            case .link(let url), .file(let url): return url
            }
        }
        let sheet = UIActivityViewController(activityItems: things, applicationActivities: nil)
        // shared or put away: iOS says which, and the page is told only that it closed
        sheet.completionWithItemsHandler = { _, _, _, _ in ended(true) }
        // an iPad shows the sheet as a popover, which needs a place: the middle of the page
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        self.sheet = sheet
        opening = true
        let present = { [weak self] in
            top.present(sheet, animated: true)
            // UIKit refuses a presentation without a word (the controller
            // under it is not on the screen, or already presents): a sheet
            // that is not on its way in a moment later was never opened
            DispatchQueue.main.async {
                self?.opening = false
                if sheet.presentingViewController == nil && !sheet.isBeingPresented { ended(false) }
            }
        }
        // a share asked as the sheet before it closes: this one opens when that has gone
        if let moving = leaving?.transitionCoordinator {
            moving.animate(alongsideTransition: nil) { _ in present() }
        } else {
            present()
        }
    }
}

/// iOS's clipboard. A copy is passed to the person's other devices on the
/// same account and stays until they copy something else; one told how long
/// it may stay is kept to this phone and expires.
struct PhoneClipboard: Clipboard {
    func hold(_ text: String, forSeconds: Int?) {
        guard let forSeconds else {
            UIPasteboard.general.string = text
            return
        }
        UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: text]], options: [
            .localOnly: true,
            .expirationDate: Date().addingTimeInterval(TimeInterval(forSeconds)),
        ])
    }
}

/// The system's own long vibration (the haptic's mode vibrate): about 0.4 s
/// of the phone's motor, as a message's. It plays on silent too, unless the
/// person switched vibration off in Settings; a device with no motor (an
/// iPad, a simulator) plays nothing.
func playLongVibration() {
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
}

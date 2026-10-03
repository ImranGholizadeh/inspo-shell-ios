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
    /// Whether the sheet asked for came up, while that is not yet known.
    private var arrival: SheetArrival?
    /// A sheet that waits for the one before it to go.
    private var queued = false

    init(over view: UIView) { self.view = view }

    var showing: Bool { queued || arrival?.waiting == true || sheet?.presentingViewController != nil }

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
        sheet.completionWithItemsHandler = { [weak self] _, _, _, _ in
            self?.arrival?.came()
            ended(true)
        }
        // an iPad shows the sheet as a popover, which needs a place: the middle of the page
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        self.sheet = sheet
        queued = true
        let present = { [weak self] in
            guard let self else { return ended(false) }
            self.queued = false
            // UIKit refuses a presentation without a word (the controller
            // under it is not on the screen, or already presents), and iOS
            // puts a share sheet up a moment after it is asked: the sheet
            // is looked for until it is up, and is never opened only when
            // it is still not up after the longest a sheet may take
            let arrival = SheetArrival(up: { [weak sheet] in
                guard let sheet else { return false }
                return sheet.presentingViewController != nil || sheet.isBeingPresented
            }, never: { ended(false) })
            self.arrival = arrival
            top.present(sheet, animated: true) { [weak sheet] in
                // one that comes after it was given up is taken down again:
                // its page was told it could not open, and its file is gone
                if arrival.gaveUp { sheet?.dismiss(animated: false) } else { arrival.came() }
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

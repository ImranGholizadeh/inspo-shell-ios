<!-- Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
     Proprietary and confidential. -->
# The Inspo shell for iOS

The native iOS mine: one web view on a gene's page, served by the Go engine
(audit-runner) and drawn by the thin renderer (inspo-core-js), plus what only a
phone has. Mobile is a mine of its own, separate from the web mine (owner,
2026-09-26); Swift was chosen for it as the low-hanging fruit (2026-09-29).

## What the shell adds

| The page asks or hears | The shell |
|---|---|
| a haptic (the device neuron's `haptic`) | `window.webkit.messageHandlers.inspo.postMessage({type: "haptic", mode})`, played by iOS's feedback generators |
| the camera (the device neuron's `camera`) | grants the web view's camera to the gene's own site only; iOS asks the person once |
| `link-opened` | a link to the app's URL scheme calls `window.inspo.linkOpened(url)` |
| a native library's call or event stream (a db neuron of type exotic on a `native://<library>/<name>` endpoint) | `{type: "native", id, url, data, keep, listen}` or `{type: "native", id, stop: true}`; the library's adapter (a `NativeLibrary`, registered with `NativeLibraries.shared`) answers, and the shell keeps only the fields `keep` names before calling `window.inspo.nativeAnswered(id, value)` or `nativeFailed(id, error)` |

Calls made before the page is ready wait in `window.inspoWaiting`; the page's
`app.js` takes them in order.

## Building

Nothing of a customer is in this repository. `Config/Default.xcconfig` points
at Inspo's own tally test (https://client-inspo.web.app/tally). A customer's
lane builds with its own xcconfig, which sets `INSPO_URL` (written
`https:/$()/...`, since `//` starts a comment), `INSPO_APP_NAME`,
`INSPO_BUNDLE_ID` and `INSPO_URL_SCHEME`:

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
      -project Shell.xcodeproj -scheme Shell -sdk iphonesimulator \
      -destination 'platform=iOS Simulator,name=iPhone 17' \
      -xcconfig <lane>/deploy/ios.xcconfig build

A test build may set `INSPO_NATIVE_STAND_IN` to a library's name (`id-reader`):
`StandInReader` then stands in for the Bluetooth ID scanner, with made-up
events played one per press of either volume button, so a gene's scan flow
runs with no device.

## The Bluetooth ID scanner (E47)

`Shell/IDScanner.swift` is the adapter that maps a vendor's Bluetooth ID
scanner package onto a gene's endpoint documents. It is written against
`BluetoothIDScanner`, the scanner's surface in plain terms; the vendor's
package is never in this repository. A customer build compiles the package
with `Bindings/VendorIDScanner.swift` (in no target here) and sets
`INSPO_ID_SCANNER` to the library's name in its urls; the shell finds the
binding by its Objective-C name and registers the adapter. The stand-in
conforms to the same surface, so its answers take the same shape.

| Endpoint (`native://<library>/<name>`) | What the adapter does |
|---|---|
| `state` (call) | `{kind: "state", state, battery}` from the package's connection status and battery |
| `feedback` (call, data `accept`, `deny` or `error`, or `{pattern}`) | accept plays the package's success feedback; deny and error its error feedback |
| `start-reading`, `stop-reading` (calls) | subscribe and unsubscribe the package's result listener |
| `reconnect`, `forget` (calls) | connect again to, or forget, the paired scanner the package's status names |
| `events` (stream) | every event flat, with a kind: `read`, `failedRead` or `failedValidation` (with `fullName`, `dateOfBirth`, `expirationDate`, `isOver21`, `isExpired` when read, and `issueCode`, the first issue), `duplicate`, `state` (`state`), `battery` (`battery`) |

The adapter configures the package once, on first use: its age and expiry
checks on, its duplicate window as delivered, reporting off the phone never
configured. Nothing but the fields above leaves the adapter, and the shell
keeps only those the endpoint's `keep` names.

To upload a lane's build: `scripts/archive.sh <lane xcconfig>`, then
`scripts/upload.sh` (the newest lane archive, or one named), which sends it
to App Store Connect with its team's signing, no Organizer needed. An archive
made from Xcode's Product > Archive carries the shell's defaults, not a lane's.

For a phone, open `Shell.xcodeproj` in Xcode, choose the team, and run; for
TestFlight, Product > Archive, then Distribute to App Store Connect.

## The Inspo desktop app (the Desktop target)

The desktop app (owner, 2026-09-30: the top priority outside client work;
"macOS target in inspo-shell-ios", "The audit binary as a helper"): a window
with one web view, and the Go engine inside the app. Its build phase
(`scripts/bundle-engine.sh`) builds `audit` from audit-runner for this Mac
and copies the built renderer from inspo-core-js into
`Inspo.app/Contents/Resources/engine`, with the pages in
`Config/desktop-pages/`. At launch the app starts `audit mine-serve` on a
free loopback port, serving that page to its own web view; the engine reads
`INSPO_DESKTOP_READ` in `INSPO_DESKTOP_PROJECT` with the person's own gcloud
sign-in, and stops when the app quits. It opens the p viewer first
(`Config/Desktop.xcconfig`). `NativeLibrary.swift` is shared with the iOS
shell; a haptic plays on the trackpad.

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
      -project Shell.xcodeproj -scheme Desktop -configuration Debug build

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
`StandInReader` then stands in for it, with made-up results played one per
press of either volume button, so a gene's scan flow runs with no device.

For a phone, open `Shell.xcodeproj` in Xcode, choose the team, and run; for
TestFlight, Product > Archive, then Distribute to App Store Connect.

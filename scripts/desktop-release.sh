#!/bin/sh
# Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
# Proprietary and confidential.
# The Inspo desktop app as a download for someone else's Mac (the editor's
# pilot, owner 22 Oct 2026: a signed Mac app): it opens the page at an
# address (INSPO_DESKTOP_ADDRESS, the staging place), so no engine is put
# inside it (bundle-engine.sh). Archived for Release with the hardened
# runtime Apple's check needs, exported with the team's Developer ID
# Application certificate, sent to Apple's notary and stapled, then packed
# as a zip a person double-clicks open.
# Usage: scripts/desktop-release.sh [<address>]
#   (from this repository; none: the xcconfig's INSPO_DESKTOP_ADDRESS)
# Needs, once, on this Mac: the Developer ID Application certificate of team
# JX6XLUJKLY in the Keychain, and the notary profile inspo-notary
# (xcrun notarytool store-credentials inspo-notary --apple-id <email> --team-id JX6XLUJKLY).
set -eu
team=JX6XLUJKLY
profile=inspo-notary
address=${1:-}
cd "$(dirname "$0")/.."
security find-identity -v -p codesigning | grep -q "Developer ID Application: .*($team)" ||
  { echo "desktop-release.sh: no Developer ID Application certificate of team $team in the Keychain. Nothing was built."; exit 2; }
xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1 ||
  { echo "desktop-release.sh: no notary profile $profile (xcrun notarytool store-credentials $profile --apple-id <email> --team-id $team). Nothing was built."; exit 2; }
out="$HOME/Desktop/Inspo-desktop-release/$(date +%Y-%m-%d-%H%M)"
mkdir -p "$out"
echo "+ archiving the Desktop app (opens ${address:-the address in Config/Desktop.xcconfig}) into $out"
xcodebuild archive -project Shell.xcodeproj -scheme Desktop -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$out/Inspo.xcarchive" \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$team" ENABLE_HARDENED_RUNTIME=YES \
  INSPO_DESKTOP_OPENS=address ${address:+INSPO_DESKTOP_ADDRESS="$address"} \
  CURRENT_PROJECT_VERSION="$(date +%Y%m%d%H%M)" | grep -E 'error|ARCHIVE (SUCCEEDED|FAILED)' || true
test -d "$out/Inspo.xcarchive" || { echo "desktop-release.sh: the archive failed; see above."; exit 1; }
cat > "$out/export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>developer-id</string>
<key>teamID</key><string>$team</string>
<key>signingStyle</key><string>automatic</string>
</dict></plist>
PLIST
echo "+ signing with Developer ID"
xcodebuild -exportArchive -archivePath "$out/Inspo.xcarchive" -exportPath "$out/export" \
  -exportOptionsPlist "$out/export.plist" -allowProvisioningUpdates | grep -E 'error|EXPORT (SUCCEEDED|FAILED)' || true
app=$(ls -d "$out"/export/*.app | head -1)
test -d "$app" || { echo "desktop-release.sh: the export failed; see above."; exit 1; }
codesign --verify --deep --strict "$app"
echo "+ sending to Apple's notary (a few minutes)"
ditto -c -k --keepParent "$app" "$out/for-notary.zip"
xcrun notarytool submit "$out/for-notary.zip" --keychain-profile "$profile" --wait
xcrun stapler staple "$app"
spctl -a -t exec -vv "$app"
name=$(basename "$app" .app)
ditto -c -k --keepParent "$app" "$out/$name.zip"
rm -f "$out/for-notary.zip"
echo "ready to send: $out/$name.zip"

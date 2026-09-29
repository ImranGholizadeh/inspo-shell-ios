#!/bin/sh
# Uploads an archive to App Store Connect (TestFlight), with no trip
# through the Organizer: the archive's own team signs it automatically.
# The newest archive archive.sh made for a lane is used when none is named.
# Usage: scripts/upload.sh [<path to .xcarchive>]
set -eu
newest_lane_archive() {
  ls -dt "$HOME"/Library/Developer/Xcode/Archives/*/*.xcarchive | grep -v '/Shell[^/]*\.xcarchive$' | head -1
}
if [ $# -ge 1 ]; then archive=$1; else archive=$(newest_lane_archive); fi
test -d "$archive" || { echo "no archive: $archive"; exit 1; }
info="$archive/Info.plist"
bundle=$(plutil -extract ApplicationProperties.CFBundleIdentifier raw "$info")
build=$(plutil -extract ApplicationProperties.CFBundleVersion raw "$info")
team=$(plutil -extract ApplicationProperties.Team raw "$info")
echo "+ uploading $bundle build $build (team $team) from $archive"
opts=$(mktemp -t upload).plist
cat > "$opts" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$team</string>
  <key>uploadSymbols</key><true/>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$opts" -allowProvisioningUpdates \
  -exportPath "$(mktemp -d -t upload)" 2>&1 | grep -E 'error|Upload|EXPORT (SUCCEEDED|FAILED)|Progress' || true

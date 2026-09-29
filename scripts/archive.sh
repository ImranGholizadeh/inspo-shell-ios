#!/bin/sh
# Archives the Inspo shell for the App Store with a lane's values, into
# Xcode's own Archives folder, so the Organizer lists it for upload
# (Distribute App). The build number is the time, so every upload differs.
# Signing is automatic with the project's team; the first archive of a new
# bundle id registers it in that team (-allowProvisioningUpdates).
# Usage: scripts/archive.sh [<lane xcconfig>]   (from this repository; none: Inspo's defaults)
set -eu
conf=${1:-Config/Default.xcconfig}
day=$(date +%Y-%m-%d)
name=$(sed -n 's/^INSPO_APP_NAME *= *//p' "$conf" | tail -1)
out="$HOME/Library/Developer/Xcode/Archives/$day/${name:-Shell} $(date +%H.%M.%S).xcarchive"
echo "+ archiving ${name:-Shell} with $conf"
xcodebuild archive -project Shell.xcodeproj -scheme Shell -configuration Release \
  -destination 'generic/platform=iOS' -xcconfig "$conf" -archivePath "$out" \
  -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$(date +%Y%m%d%H%M)" | \
  grep -E 'error|warning: |ARCHIVE (SUCCEEDED|FAILED)' || true
test -d "$out" && echo "archive: $out" && echo "upload it from Xcode: Window > Organizer > Distribute App"

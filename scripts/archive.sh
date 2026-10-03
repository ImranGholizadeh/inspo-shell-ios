#!/bin/sh
# Archives the Inspo shell for the App Store with a lane's values, into
# Xcode's own Archives folder, so the Organizer lists it for upload
# (Distribute App). The build number is the time, so every upload differs.
# Signing is automatic with the project's team; the first archive of a new
# bundle id registers it in that team (-allowProvisioningUpdates).
# Usage: scripts/archive.sh [<lane xcconfig> [<lane workspace>]]
#   (from this repository; none: Inspo's defaults). A lane whose app links a
#   native library's package (the Bluetooth ID scanner, README) names its
#   Xcode workspace, which holds this project and the package's binding.
#   A lane's icon and splash: INSPO_BRAND_ASSETS in its xcconfig names the
#   folder of its asset sets, laid over the shell's own in a temporary copy
#   for this build only (brand-overlay.sh).
set -eu
conf=${1:-Config/Default.xcconfig}
workspace=${2:-}
. "$(dirname "$0")/brand-overlay.sh"
day=$(date +%Y-%m-%d)
name=$(xcconfig_value INSPO_APP_NAME "$conf")
out="$HOME/Library/Developer/Xcode/Archives/$day/${name:-Shell} $(date +%H.%M.%S).xcarchive"
echo "+ archiving ${name:-Shell} with $conf"
xcodebuild archive "$container_flag" "$container_path" -scheme Shell -configuration Release \
  -destination 'generic/platform=iOS' -xcconfig "$conf" -archivePath "$out" \
  ${derived:+-derivedDataPath} ${derived:+"$derived"} \
  -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$(date +%Y%m%d%H%M)" | \
  grep -E 'error|warning: |ARCHIVE (SUCCEEDED|FAILED)' || true
test -d "$out" && echo "archive: $out" && echo "upload it from Xcode: Window > Organizer > Distribute App"

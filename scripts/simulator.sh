#!/bin/sh
# Builds the Inspo shell for the iOS Simulator with a lane's values: a
# development build, unsigned, for trying a lane's app (its icon and splash
# too) with no phone. The app is left where the last line says.
# Usage: scripts/simulator.sh [<lane xcconfig> [<lane workspace>]]
#   (from this repository; none: Inspo's defaults). A lane whose app links a
#   native library's package names its Xcode workspace, as for archive.sh.
#   A lane's icon and splash: INSPO_BRAND_ASSETS in its xcconfig names the
#   folder of its asset sets, laid over the shell's own in a temporary copy
#   for this build only (brand-overlay.sh).
#   INSPO_BUILD_DIR: where the build goes (none: build/simulator, here).
set -eu
conf=${1:-Config/Default.xcconfig}
workspace=${2:-}
. "$(dirname "$0")/brand-overlay.sh"
out=${INSPO_BUILD_DIR:-$(pwd)/build/simulator}
mkdir -p "$out"
app="$out/Build/Products/Debug-iphonesimulator/Shell.app"
name=$(xcconfig_value INSPO_APP_NAME "$conf")
echo "+ building ${name:-Shell} for the simulator with $conf"
if ! xcodebuild build "$container_flag" "$container_path" -scheme Shell -configuration Debug \
    -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -xcconfig "$conf" \
    -derivedDataPath "$out" > "$out/build.log" 2>&1; then
  grep -E 'error|BUILD FAILED' "$out/build.log" || tail -20 "$out/build.log"
  echo "the build failed: $out/build.log" >&2
  exit 1
fi
test -d "$app" || { echo "no app was built: $out/build.log" >&2; exit 1; }
echo "app: $app"
echo "to run it: xcrun simctl install booted \"$app\" && xcrun simctl launch booted $(xcconfig_value INSPO_BUNDLE_ID "$conf")"

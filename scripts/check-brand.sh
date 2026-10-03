#!/bin/sh
# Checks the brand overlay (scripts/brand-overlay.sh) on this Mac, with no
# build: a made-up lane in a folder whose name has a space (an xcconfig that
# includes another, three asset sets, a workspace holding the shell's project
# beside a binding), and a stand-in xcodebuild that only records what it was
# asked to build. It holds that the build is run on a copy with the lane's
# sets laid over the shell's, that the copy names the packages and the lane's
# binding where they are, that the copy is gone after (a stopped build too),
# that a build with no brand runs in place, that each fault stops the build
# with its reason, and that nothing in this repository changes.
# Usage: scripts/check-brand.sh (from this repository)
set -eu
repo=$(pwd)
test -f "$repo/scripts/brand-overlay.sh" || { echo "run from the shell's repository"; exit 1; }
tmp=$(mktemp -d "${TMPDIR:-/tmp}/inspo brand check.XXXXXX")
tmp=$(cd "$tmp" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
failed=0
ok() { echo "ok    $1"; }
bad() { echo "FAIL  $1"; failed=1; }
hold() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# the made-up lane
lane="$tmp/a lane"
mkdir -p "$lane/deploy" "$lane/ios/brand/AppIcon.appiconset" "$lane/ios/brand/LaunchBackground.colorset" \
  "$lane/ios/brand/LaunchMark.imageset" "$lane/ios/Lane.xcworkspace" "$lane/ios/Binding"
echo '{"images":[{"filename":"icon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}' > "$lane/ios/brand/AppIcon.appiconset/Contents.json"
echo "the lane's icon" > "$lane/ios/brand/AppIcon.appiconset/icon.png"
echo '{"colors":[],"info":{"author":"xcode","version":1}}' > "$lane/ios/brand/LaunchBackground.colorset/Contents.json"
echo '{"images":[{"filename":"mark.svg","idiom":"universal"}],"info":{"author":"xcode","version":1}}' > "$lane/ios/brand/LaunchMark.imageset/Contents.json"
echo "<svg/>" > "$lane/ios/brand/LaunchMark.imageset/mark.svg"
cat > "$lane/deploy/base.xcconfig" <<EOF
INSPO_APP_NAME = Base Name
INSPO_BUNDLE_ID = test.brand.check
INSPO_BRAND_ASSETS = ../ios/brand   // from the xcconfig's own place
EOF
printf '#include "base.xcconfig"\nINSPO_APP_NAME = Lane Name\n' > "$lane/deploy/ios.xcconfig"
printf 'INSPO_APP_NAME = Plain\nINSPO_BUNDLE_ID = test.brand.plain\n' > "$lane/deploy/plain.xcconfig"
cat > "$lane/ios/Lane.xcworkspace/contents.xcworkspacedata" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "absolute:$repo/Shell.xcodeproj">
   </FileRef>
   <FileRef
      location = "group:Binding">
   </FileRef>
</Workspace>
EOF

# the stand-in xcodebuild: what it was asked, and what it would have built
mkdir "$tmp/bin" "$tmp/seen"
cat > "$tmp/bin/xcodebuild" <<'EOF'
#!/bin/sh
seen=$BRAND_CHECK_SEEN
rm -rf "$seen"; mkdir -p "$seen"
kind=; place=; derived=
for arg in "$@"; do
  printf '%s\n' "$arg" >> "$seen/args"
  case $last in
    -project|-workspace) kind=$last; place=$arg ;;
    -derivedDataPath) derived=$arg ;;
  esac
  last=$arg
done
printf '%s\n' "$kind" > "$seen/kind"; printf '%s\n' "$place" > "$seen/place"; printf '%s\n' "$derived" > "$seen/derived"
project=$place
if [ "$kind" = -workspace ]; then
  cp "$place/contents.xcworkspacedata" "$seen/workspace"
  project=$(sed -n 's/.*location = "absolute:\(.*Shell\.xcodeproj\)".*/\1/p' "$place/contents.xcworkspacedata")
fi
shell=$(cd "$(dirname "$project")" && pwd -P)
printf '%s\n' "$shell" > "$seen/shell"
cp -R "$shell/Shell/Assets.xcassets" "$seen/assets"
grep 'relativePath' "$project/project.pbxproj" > "$seen/packages"
if [ -n "${BRAND_CHECK_STOP:-}" ]; then kill -TERM "$PPID"; sleep 1; exit 1; fi
if [ -n "$derived" ]; then mkdir -p "$derived/Build/Products/Debug-iphonesimulator/Shell.app"; fi
echo "** BUILD SUCCEEDED **"
EOF
chmod +x "$tmp/bin/xcodebuild"
export BRAND_CHECK_SEEN="$tmp/seen/last"
run() { PATH="$tmp/bin:$PATH" HOME="$tmp/home" INSPO_BUILD_DIR="$tmp/out" sh "$@" > "$tmp/said" 2>&1; }
before=$(cd "$repo" && { git status --porcelain 2>/dev/null; find Shell/Assets.xcassets -type f -exec cksum {} +; })
copies() { ls -d "${TMPDIR:-/tmp}"/inspo-shell-brand.* 2>/dev/null | wc -l | tr -d ' '; }
copies_before=$(copies)

# 1. a lane's workspace and its brand, for the simulator
if run scripts/simulator.sh "$lane/deploy/ios.xcconfig" "$lane/ios/Lane.xcworkspace"; then ok "a lane's build with a brand runs"; else bad "a lane's build with a brand runs: $(cat "$tmp/said")"; fi
seen=$BRAND_CHECK_SEEN
hold "it is built from a copy, not from this repository" '[ "$(cat "$seen/shell")" != "$repo" ] && [ "$(cat "$seen/kind")" = -workspace ]'
hold "the copy holds the lane's icon, colour and mark" 'diff -r "$lane/ios/brand/AppIcon.appiconset" "$seen/assets/AppIcon.appiconset" > /dev/null && diff -r "$lane/ios/brand/LaunchBackground.colorset" "$seen/assets/LaunchBackground.colorset" > /dev/null && diff -r "$lane/ios/brand/LaunchMark.imageset" "$seen/assets/LaunchMark.imageset" > /dev/null'
hold "nothing of the shell's own icon is left beside it" '[ "$(ls "$seen/assets/AppIcon.appiconset" | wc -l | tr -d " ")" = 2 ]'
hold "the copy's workspace holds the lane's binding where it is" 'grep -q "absolute:$lane/ios/Binding\"" "$seen/workspace"'
hold "the copy's project names the packages in this repository" '[ "$(grep -c "relativePath = \"$repo/Packages/" "$seen/packages")" = "$(wc -l < "$seen/packages" | tr -d " ")" ]'
hold "the name is the including xcconfig's, the last set" 'grep -q "building Lane Name for the simulator" "$tmp/said"'
hold "the copy is gone after the build" '[ ! -e "$(cat "$seen/shell")" ] && [ "$(copies)" = "$copies_before" ]'

# 2. the project alone, with the brand
if run scripts/simulator.sh "$lane/deploy/ios.xcconfig"; then ok "the project alone with a brand runs"; else bad "the project alone with a brand runs: $(cat "$tmp/said")"; fi
hold "it is the copy's project, with the lane's icon" '[ "$(cat "$seen/kind")" = -project ] && [ "$(cat "$seen/shell")" != "$repo" ] && diff -r "$lane/ios/brand/AppIcon.appiconset" "$seen/assets/AppIcon.appiconset" > /dev/null'

# 3. no brand: in place, the shell's own sets
if run scripts/simulator.sh "$lane/deploy/plain.xcconfig" "$lane/ios/Lane.xcworkspace"; then ok "a build with no brand runs"; else bad "a build with no brand runs: $(cat "$tmp/said")"; fi
hold "it is built in place, from the lane's own workspace" '[ "$(cat "$seen/shell")" = "$repo" ] && [ "$(cat "$seen/place")" = "$lane/ios/Lane.xcworkspace" ]'
hold "the shell has its own icon, colour and mark" '[ -f "$repo/Shell/Assets.xcassets/AppIcon.appiconset/Contents.json" ] && [ -f "$repo/Shell/Assets.xcassets/LaunchBackground.colorset/Contents.json" ] && [ -f "$repo/Shell/Assets.xcassets/LaunchMark.imageset/Contents.json" ]'

# 4. an archive: the same copy, its derived data inside it, the place whole
run scripts/archive.sh "$lane/deploy/ios.xcconfig" "$lane/ios/Lane.xcworkspace" || true
hold "an archive is built from a copy, its derived data in the copy" '[ "$(cat "$seen/shell")" != "$repo" ] && [ "$(cat "$seen/derived")" = "$(cat "$seen/shell")/DerivedData" ]'
hold "a place with a space reaches xcodebuild whole" 'grep -q "^$lane/deploy/ios.xcconfig\$" "$seen/args" && grep -q "^$tmp/home/Library/Developer/Xcode/Archives/.*/Lane Name .*xcarchive\$" "$seen/args"'
hold "the copy is gone after the archive" '[ ! -e "$(cat "$seen/shell")" ]'

# 5. a build stopped by a signal leaves no copy
BRAND_CHECK_STOP=1 run scripts/simulator.sh "$lane/deploy/ios.xcconfig" "$lane/ios/Lane.xcworkspace" && bad "a stopped build ends as failed" || ok "a stopped build ends as failed"
hold "the copy is gone after a stopped build" '[ ! -e "$(cat "$seen/shell")" ] && [ "$(copies)" = "$copies_before" ]'

# 6. faults stop the build, each with its reason, and nothing is built
rm -rf "$seen"
mv "$lane/ios/brand/AppIcon.appiconset" "$lane/ios/icon-away"
run scripts/simulator.sh "$lane/deploy/ios.xcconfig" && bad "a brand with no icon is refused" || ok "a brand with no icon is refused"
hold "it says so, and nothing was built" 'grep -q "no AppIcon.appiconset" "$tmp/said" && [ ! -e "$seen" ]'
mv "$lane/ios/icon-away" "$lane/ios/brand/AppIcon.appiconset"
rm "$lane/ios/brand/LaunchMark.imageset/Contents.json"
run scripts/simulator.sh "$lane/deploy/ios.xcconfig" && bad "a set with no Contents.json is refused" || ok "a set with no Contents.json is refused"
hold "it says so, nothing was built, and the copy is gone" 'grep -q "no Contents.json" "$tmp/said" && [ ! -e "$seen" ] && [ "$(copies)" = "$copies_before" ]'
echo '{"images":[{"filename":"mark.svg","idiom":"universal"}],"info":{"author":"xcode","version":1}}' > "$lane/ios/brand/LaunchMark.imageset/Contents.json"
sed -e "s#absolute:$repo/Shell.xcodeproj#group:Elsewhere#" "$lane/ios/Lane.xcworkspace/contents.xcworkspacedata" > "$tmp/data"
mkdir "$lane/ios/Other.xcworkspace" && mv "$tmp/data" "$lane/ios/Other.xcworkspace/contents.xcworkspacedata"
run scripts/simulator.sh "$lane/deploy/ios.xcconfig" "$lane/ios/Other.xcworkspace" && bad "a workspace without the shell's project is refused" || ok "a workspace without the shell's project is refused"
hold "it says so, nothing was built, and the copy is gone" 'grep -q "does not hold Shell.xcodeproj" "$tmp/said" && [ ! -e "$seen" ] && [ "$(copies)" = "$copies_before" ]'
run scripts/simulator.sh "$lane/deploy/none.xcconfig" && bad "an xcconfig that is not there is refused" || ok "an xcconfig that is not there is refused"

# 7. this repository is as it was
after=$(cd "$repo" && { git status --porcelain 2>/dev/null; find Shell/Assets.xcassets -type f -exec cksum {} +; })
hold "nothing in this repository changed" '[ "$before" = "$after" ]'

if [ "$failed" = 0 ]; then echo "the brand overlay holds"; else echo "the brand overlay does NOT hold"; exit 1; fi

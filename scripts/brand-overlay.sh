# Sourced by the build scripts (archive.sh, simulator.sh), after $conf (the
# lane's xcconfig) and $workspace (the lane's Xcode workspace, or empty) are
# set. It sets what the build is run on: $container_flag and $container_path
# (-project or -workspace, and its place) and $derived (where the build's
# derived data goes when it must not outlive the build; else empty).
#
# A lane's own icon and splash never enter this repository: when the xcconfig
# names a folder of asset sets (INSPO_BRAND_ASSETS: AppIcon.appiconset, and
# LaunchBackground.colorset and LaunchMark.imageset for the splash), the build
# runs from a temporary copy of the shell with those sets laid over its own,
# and the copy is removed when the script ends, however it ends. Without the
# key nothing changes: the shell builds in place with its placeholder icon
# and its plain splash (a set the lane's folder leaves out stays the shell's).
set -eu

# An xcconfig's lines, with the files it includes in their place.
xcconfig_lines() (
  dir=$(cd "$(dirname "$1")" && pwd)
  while IFS= read -r line || [ -n "$line" ]; do
    case $line in
      '#include'*)
        inc=$(printf '%s\n' "$line" | sed -e 's/^#include[?]*[[:space:]]*"//' -e 's/".*$//')
        case $inc in /*) ;; *) inc=$dir/$inc ;; esac
        if [ -f "$inc" ]; then xcconfig_lines "$inc"; fi ;;
      *) printf '%s\n' "$line" ;;
    esac
  done < "$1"
)

# A key's value in an xcconfig (the last one set, as Xcode reads it), with
# no comment and no space after it. Usage: xcconfig_value <key> <xcconfig>
xcconfig_value() {
  xcconfig_lines "$2" | sed -n "s/^$1[[:space:]]*=[[:space:]]*//p" | tail -1 |
    sed -e 's|[[:space:]]*//.*$||' -e 's/[[:space:]]*$//'
}

# A path as an Xcode workspace's file names it.
xml_escaped() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'
}

test -f "$conf" || { echo "no xcconfig: $conf" >&2; exit 1; }
if [ -n "${workspace:-}" ]; then
  test -f "$workspace/contents.xcworkspacedata" || { echo "no Xcode workspace: $workspace" >&2; exit 1; }
  container_flag=-workspace
  container_path=$workspace
else
  container_flag=-project
  container_path=Shell.xcodeproj
fi
derived=

brand=$(xcconfig_value INSPO_BRAND_ASSETS "$conf")
if [ -n "$brand" ]; then
  # a folder named from the xcconfig's own place, unless from the root
  case $brand in /*) ;; *) brand=$(cd "$(dirname "$conf")" && pwd)/$brand ;; esac
  test -f "$brand/AppIcon.appiconset/Contents.json" || {
    echo "INSPO_BRAND_ASSETS: no AppIcon.appiconset in $brand" >&2; exit 1; }
  src=$(pwd)
  test -d "$src/Shell/Assets.xcassets" || {
    echo "run from the shell's repository: no Shell/Assets.xcassets in $src" >&2; exit 1; }
  work=$(mktemp -d "${TMPDIR:-/tmp}/inspo-shell-brand.XXXXXX")
  work=$(cd "$work" && pwd -P)
  # the copy goes when the script ends: done, failed or stopped by a signal
  trap 'rm -rf "$work"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM HUP
  # the packages stay where they are, and the copy's project names them
  # there: a lane's binding names them by their place in this repository, and
  # the same package reached by a second path is a second package to Xcode
  rsync -a --exclude .git --exclude build --exclude DerivedData --exclude xcuserdata \
    --exclude Packages "$src"/ "$work"/
  project=$work/Shell.xcodeproj/project.pbxproj
  there=$(printf '%s' "$src" | sed -e 's/[\\&|"]/\\&/g')
  sed "s|relativePath = Packages/\([^;]*\);|relativePath = \"$there/Packages/\1\";|" "$project" > "$project.new"
  mv "$project.new" "$project"
  if grep -q 'relativePath = Packages/' "$project" || ! grep -q "relativePath = \"" "$project"; then
    echo "the copy's project does not name the shell's packages in $src/Packages" >&2; exit 1
  fi
  laid=0
  for set in "$brand"/*.appiconset "$brand"/*.colorset "$brand"/*.imageset; do
    [ -e "$set" ] || continue
    test -f "$set/Contents.json" || { echo "INSPO_BRAND_ASSETS: no Contents.json in $set" >&2; exit 1; }
    name=$(basename "$set")
    rm -rf "$work/Shell/Assets.xcassets/$name"
    cp -R "$set" "$work/Shell/Assets.xcassets/$name"
    diff -r "$set" "$work/Shell/Assets.xcassets/$name" > /dev/null || {
      echo "INSPO_BRAND_ASSETS: $name was not laid over the shell's" >&2; exit 1; }
    laid=$((laid + 1))
  done
  if [ "$container_flag" = -workspace ]; then
    # the lane's workspace again, in the copy: the shell's project is the
    # copy's, and everything else it holds is named from the root
    lane=$(cd "$(dirname "$workspace")" && pwd)
    mkdir "$work/Lane.xcworkspace"
    sed -n 's/.*location[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$workspace/contents.xcworkspacedata" > "$work/refs"
    shells=0
    {
      printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' '<Workspace' '   version = "1.0">'
      while IFS= read -r ref; do
        case $ref in
          *:Shell.xcodeproj|*/Shell.xcodeproj)
            ref="absolute:$(xml_escaped "$work")/Shell.xcodeproj"
            shells=$((shells + 1)) ;;
          group:*) ref="absolute:$(xml_escaped "$lane")/${ref#group:}" ;;
          container:*) ref="absolute:$(xml_escaped "$lane")/${ref#container:}" ;;
        esac
        printf '   <FileRef\n      location = "%s">\n   </FileRef>\n' "$ref"
      done < "$work/refs"
      printf '%s\n' '</Workspace>'
    } > "$work/Lane.xcworkspace/contents.xcworkspacedata"
    rm "$work/refs"
    # a workspace that does not hold the shell's project would build the
    # shell from somewhere else, with no brand, and say nothing
    [ "$shells" -eq 1 ] || {
      echo "$workspace does not hold Shell.xcodeproj once: the brand cannot be laid" >&2; exit 1; }
    container_path=$work/Lane.xcworkspace
  else
    container_path=$work/Shell.xcodeproj
  fi
  derived=$work/DerivedData
  echo "+ brand: $laid asset sets from $brand, built from a temporary copy"
fi

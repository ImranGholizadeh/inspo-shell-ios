#!/bin/sh
# Puts the Go engine and the renderer inside the desktop app (the Desktop
# target's build phase runs it; owner, 2026-09-30: "The audit binary as a
# helper"): engine/audit, built from audit-runner for this Mac; engine/client,
# the built renderer from inspo-core-js; engine/pages, the pages it may open.
# Paths come from Config/Desktop.xcconfig.
set -eu
out="${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}/engine"
mkdir -p "$out/pages"
export PATH="/usr/local/go/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
export GOCACHE="${GOCACHE:-$HOME/Library/Caches/go-build}"
(cd "${INSPO_AUDIT_RUNNER:?}" && go build -trimpath -o "$out/audit" ./cmd/audit)
# always built: an old dist would ship a renderer behind the engine
(cd "${INSPO_CORE_JS:?}" && npm run build >/dev/null)
rm -rf "$out/client" && cp -R "$INSPO_CORE_JS/dist/client" "$out/client"
cp "${SRCROOT:?}/Config/desktop-pages/"*.json "$out/pages/"
echo "engine bundled: $(du -sh "$out" | cut -f1)"

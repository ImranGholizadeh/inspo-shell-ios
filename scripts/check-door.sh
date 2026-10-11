#!/bin/sh
# Checks whose page the shell answers (Shell/OwnPage.swift) on this Mac,
# with no phone and no simulator: a request is taken only from the main
# frame of a page of the build's own origin; a page of another origin that
# names a scan's every field in keep, over the stand-in reader, is handed
# nothing and starts nothing; an answer is told only to the page that
# asked; and the phone's bridge (Shell/ShellBridge.swift) passes every
# message through that door before it does anything.
# Usage: scripts/check-door.sh (from this repository)
set -eu
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
xcrun swiftc -parse-as-library -module-name IDScannerSurface \
  -emit-module -emit-module-path "$out/IDScannerSurface.swiftmodule" -emit-object -o "$out/surface.o" \
  Packages/IDScannerSurface/Sources/IDScannerSurface/IDScannerSurface.swift
xcrun swiftc -module-name Checks -I "$out" -o "$out/door-check" "$out/surface.o" \
  Shell/NativeLibrary.swift Shell/IDScanner.swift Shell/StandInReader.swift Shell/OwnPage.swift Checks/door/main.swift
"$out/door-check"

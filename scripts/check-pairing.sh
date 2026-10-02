#!/bin/sh
# Checks a first pairing of the Bluetooth ID scanner (Shell/IDScanner.swift)
# on this Mac, with no phone, no simulator and no scanner: the steps in
# order, the nearest scanner picked when the listening window ends, each time
# limit and its reason, stopping, a second pairing while one runs, and the
# stand-in's played pairing (Shell/StandInReader.swift). The scanner only
# records what it was asked, and the check moves the clock.
# Usage: scripts/check-pairing.sh (from this repository)
set -eu
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
xcrun swiftc -parse-as-library -module-name IDScannerSurface \
  -emit-module -emit-module-path "$out/IDScannerSurface.swiftmodule" -emit-object -o "$out/surface.o" \
  Packages/IDScannerSurface/Sources/IDScannerSurface/IDScannerSurface.swift
xcrun swiftc -I "$out" -o "$out/pairing-check" "$out/surface.o" \
  Shell/NativeLibrary.swift Shell/IDScanner.swift Shell/StandInReader.swift Checks/pairing/main.swift
"$out/pairing-check"

#!/bin/sh
# Checks the holder's age the ID scanner's adapter (Shell/IDScanner.swift)
# works out on the phone, on this Mac, with no phone, no simulator and no
# scanner: whole years from the holder's dateOfBirth and the phone's own day,
# one less while the birthday is still to come, a leap day's, a birthday
# today's; no age for a missing or unreadable birth date; the age handed to a
# page only when its endpoint's keep names it; and the stand-in's made-up
# people (Shell/StandInReader.swift) read with their ages.
# Usage: scripts/check-age.sh (from this repository)
set -eu
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
xcrun swiftc -parse-as-library -module-name IDScannerSurface \
  -emit-module -emit-module-path "$out/IDScannerSurface.swiftmodule" -emit-object -o "$out/surface.o" \
  Packages/IDScannerSurface/Sources/IDScannerSurface/IDScannerSurface.swift
xcrun swiftc -module-name Checks -I "$out" -o "$out/age-check" "$out/surface.o" \
  Shell/NativeLibrary.swift Shell/IDScanner.swift Shell/StandInReader.swift Checks/Bench.swift Checks/age/main.swift
"$out/age-check"

#!/bin/sh
# Checks what the Bluetooth ID scanner's adapter (Shell/IDScanner.swift) says
# of a paired scanner that is not connected, on this Mac, with no phone, no
# simulator and no scanner: the state call's answer at once, with paired and
# the reason; the stream's state events when the link drops, when Bluetooth
# goes off, is refused or comes back, and when the scanner is back; the
# reconnect that waits and the one that answers at once; the warnings; and
# the stand-in's scenes (Shell/StandInReader.swift). The scanner only records
# what it was asked, and the check moves the clock.
# Usage: scripts/check-reader.sh (from this repository)
set -eu
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
xcrun swiftc -parse-as-library -module-name IDScannerSurface \
  -emit-module -emit-module-path "$out/IDScannerSurface.swiftmodule" -emit-object -o "$out/surface.o" \
  Packages/IDScannerSurface/Sources/IDScannerSurface/IDScannerSurface.swift
xcrun swiftc -module-name Checks -I "$out" -o "$out/reader-check" "$out/surface.o" \
  Shell/NativeLibrary.swift Shell/IDScanner.swift Shell/StandInReader.swift Checks/Bench.swift Checks/reader/main.swift
"$out/reader-check"

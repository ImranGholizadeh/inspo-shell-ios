#!/bin/sh
# Checks Shell/BanKeys.swift on this Mac, with no phone and no simulator:
# the phone's saved ban list behind native://ban-keys (replace in pages, put,
# lift, match), kept over a restart, and match always answering.
# Usage: scripts/check-ban-keys.sh (from this repository)
set -eu
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
xcrun swiftc -o "$out/ban-keys-check" Shell/NativeLibrary.swift Shell/BanKeys.swift Checks/ban-keys/main.swift
"$out/ban-keys-check"

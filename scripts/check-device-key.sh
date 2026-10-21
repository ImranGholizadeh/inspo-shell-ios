#!/bin/sh
# Checks Shell/DeviceKey.swift on this Mac, with no phone and no simulator:
# the device's key the shell keeps for the page (the first the page tells,
# never replaced, said to the build's own origin only, wiped at a new
# install's first start).
# Usage: scripts/check-device-key.sh (from this repository)
set -eu
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
xcrun swiftc -o "$out/device-key-check" Shell/DeviceKey.swift Shell/OwnPage.swift Checks/device-key/main.swift
"$out/device-key-check"

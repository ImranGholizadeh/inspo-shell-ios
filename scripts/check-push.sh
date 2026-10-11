#!/bin/sh
# Checks the shell's push library (Shell/Push.swift) on this Mac, with no
# phone, no simulator, no Apple and no push service: the permission call
# (asking, and reading without asking), the token call (Apple's token as
# small hex, the environment, the app's id; one asking of Apple for calls
# that wait together; no answer in time), the stream (a tap, a tap kept for
# the first stream to open, a tap kept again when its page goes, a
# notification that arrives with the app on the screen), only the fields an
# endpoint's keep names leaving the shell, and the environment read from a
# provisioning profile. The phone only records what it was asked, and the
# check moves the clock.
# Usage: scripts/check-push.sh (from this repository)
set -eu
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
xcrun swiftc -o "$out/push-check" Shell/NativeLibrary.swift Shell/Push.swift Checks/push/main.swift
"$out/push-check"

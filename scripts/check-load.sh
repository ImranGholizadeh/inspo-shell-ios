#!/bin/sh
# Checks Shell/LoadAgain.swift on this Mac, with no phone, no simulator and
# no network: a page that did not load is loaded again after a wait that
# doubles to its longest, at once when the network is back, and never twice
# for one wait.
# Usage: scripts/check-load.sh (from this repository)
set -eu
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
xcrun swiftc -o "$out/load-check" Shell/LoadAgain.swift Checks/load/main.swift
"$out/load-check"

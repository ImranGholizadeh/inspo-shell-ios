#!/bin/sh
# Checks Shell/ShellActs.swift on this Mac, with no phone and no simulator:
# each shell says what it does as the page reads it (window.inspoShell.acts),
# each bridge sets it on every page, and no shell says an act its bridge has
# no case for.
# Usage: scripts/check-acts.sh (from this repository)
set -eu
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
xcrun swiftc -o "$out/acts-check" Shell/ShellActs.swift Checks/acts/main.swift
"$out/acts-check"

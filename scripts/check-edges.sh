#!/bin/sh
# Checks the script that tells a page a resize when the edges of the screen
# the hardware covers change (Shell/CoveredEdges.swift), on this Mac, with
# no phone and no simulator: the script is run in a JavaScript engine
# against a document that only records, and the check says what the web
# view would say of the mark's size; and that the phone's bridge adds the
# script to every page as it starts.
# Usage: scripts/check-edges.sh (from this repository)
set -eu
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
xcrun swiftc -o "$out/edges-check" Shell/CoveredEdges.swift Checks/edges/main.swift
"$out/edges-check"

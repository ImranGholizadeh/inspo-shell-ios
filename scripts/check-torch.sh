#!/bin/sh
# Checks Shell/Torch.swift on this Mac, with no phone and no simulator: the
# light the page asks for is switched on and off, an unknown mode switches
# nothing, and only a light the shell lit is put out when the page goes.
# Usage: scripts/check-torch.sh (from this repository)
set -eu
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
xcrun swiftc -o "$out/torch-check" Shell/Torch.swift Checks/torch/main.swift
"$out/torch-check"

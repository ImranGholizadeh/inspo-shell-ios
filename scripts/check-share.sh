#!/bin/sh
# Checks Shell/HandOver.swift on this Mac, with no phone and no simulator:
# a share's file is written under its name, shared and removed when the
# sheet closes; a text and a link are shared as given; what may not be
# handed over (a file's name with a folder, a link that is not http or
# https, anything too large) is refused with its reason; each request is
# answered once; the clipboard holds the text it is given.
# Usage: scripts/check-share.sh (from this repository)
set -eu
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
xcrun swiftc -o "$out/share-check" Shell/HandOver.swift Checks/share/main.swift
"$out/share-check"

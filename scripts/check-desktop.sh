#!/bin/sh
# Checks Desktop/Workspace.swift and Desktop/PageLog.swift on this Mac, with
# no window, no engine and no port: the desktop app's words, each launch's
# folder of logs, what a launch does with a workspace that is already up
# (its own earlier launch's is stopped by the stop and started again; one it
# did not start is left until the person says so; never two at once), a
# start that fails, the engines' log followed, and what the page's log
# keeps (its console and what nobody caught; no field, no key).
# Usage: scripts/check-desktop.sh (from this repository)
set -eu
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
xcrun swiftc -o "$out/desktop-check" Desktop/Workspace.swift Desktop/PageLog.swift Checks/desktop/main.swift
"$out/desktop-check"

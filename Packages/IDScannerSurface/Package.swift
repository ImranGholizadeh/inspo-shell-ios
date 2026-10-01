// swift-tools-version:5.9
// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

// The Bluetooth ID scanner's surface (E47): the protocol and plain types
// the shell's adapter (Shell/IDScanner.swift) maps, and a binding conforms
// a vendor's package to. Its own module, so a binding built in a customer's
// workspace can see it.
import PackageDescription

let package = Package(
    name: "IDScannerSurface",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "IDScannerSurface", targets: ["IDScannerSurface"])],
    targets: [.target(name: "IDScannerSurface")]
)

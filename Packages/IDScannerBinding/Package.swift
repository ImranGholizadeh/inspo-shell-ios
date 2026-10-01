// swift-tools-version:5.9
// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

// The binding's place (E47): here, a stand-in that links no scanner. A
// customer's Xcode workspace holds the shell's project beside a package of
// this same name (IDScannerBinding) that depends on IDScannerSurface and the
// vendor's package; Xcode then builds the workspace's package in this one's
// place, and the shell repository never holds the vendor's code.
import PackageDescription

let package = Package(
    name: "IDScannerBinding",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "IDScannerBinding", targets: ["IDScannerBinding"])],
    dependencies: [.package(path: "../IDScannerSurface")],
    targets: [.target(name: "IDScannerBinding", dependencies: ["IDScannerSurface"])]
)

// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

import IDScannerSurface

/// The scanner a build links. This package links none; a customer's
/// workspace replaces it with one whose scanner() returns the vendor's
/// package behind BluetoothIDScanner (Bindings/VendorIDScanner.swift).
public enum IDScannerBinding {
    public static func scanner() -> BluetoothIDScanner? { nil }
}

//
//  Error.swift
//  ble_peripheral
//
//  Created by Rohit Sangwan on 12/12/23.
//

import Foundation
import Foundation
#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#else
#error("Unsupported platform.")
#endif


extension FlutterError: Swift.Error {}

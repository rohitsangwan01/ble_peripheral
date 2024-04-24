import 'dart:async';

import 'package:ble_peripheral/src/ble_peripheral_interface.dart';
import 'package:ble_peripheral/src/generated/ble_peripheral.g.dart';
import 'package:ble_peripheral/src/pigeon/ble_peripheral_pigeon.dart';
import 'package:flutter/foundation.dart';
export 'package:ble_peripheral/src/models/ble_enums.dart';
export 'package:ble_peripheral/src/generated/ble_peripheral.g.dart';

/// [BlePeripheral] is the main class to interact with the BLE peripheral plugin.
class BlePeripheral {
  static BlePeripheralInterface _platform = _defaultPlatform();

  static BlePeripheralInterface _defaultPlatform() {
    if (defaultTargetPlatform == TargetPlatform.linux) {
      // Implement the linux platform interface
    }
    return BlePeripheralPigeon.instance;
  }

  /// Set custom platform specific implementation (e.g. for testing)
  static void setInstance(BlePeripheralInterface instance) =>
      _platform = instance;

  /// Make sure to call this method before calling any other method
  static Future initialize() => _platform.initialize();

  /// check if blePeripheral is supported on the device
  static Future<bool> isSupported() => _platform.isSupported();

  /// To ask for ble permission
  @Deprecated('use permission_handler plugin instead')
  static Future<bool> askBlePermission() => _platform.askBlePermission();

  /// check if blePeripheral is advertising
  static Future<bool?> isAdvertising() => _platform.isAdvertising();

  /// Add a service to the peripheral, and get success result in [setServiceAddedCallback]
  /// Make sure to add next service only after getting success result for previous service
  /// add all services before calling [startAdvertising]
  static Future<void> addService(
    BleService service, {
    Duration? timeout,
  }) {
    return _platform.addService(service, timeout: timeout);
  }

  /// Remove a service from the peripheral
  static Future<void> removeService(String serviceId) =>
      _platform.removeService(serviceId);

  /// Clear all services from the peripheral
  static Future<void> clearServices() => _platform.clearServices();

  /// Get list of services added to the peripheral
  static Future<List<String>> getServices() => _platform.getServices();

  /// To update the value of a characteristic
  static Future<void> updateCharacteristic({
    required String characteristicId,
    required Uint8List value,
    String? deviceId,
  }) {
    return _platform.updateCharacteristic(
        characteristicId: characteristicId, value: value, deviceId: deviceId);
  }

  /// Start advertising with the given services and local name
  /// make sure to add services before calling this method
  static Future<void> startAdvertising({
    required List<String> services,
    String? localName,
    int? timeout,
    ManufacturerData? manufacturerData,
    bool addManufacturerDataInScanResponse = false,
  }) {
    return _platform.startAdvertising(
      services: services,
      localName: localName,
      timeout: timeout,
      manufacturerData: manufacturerData,
      addManufacturerDataInScanResponse: addManufacturerDataInScanResponse,
    );
  }

  /// Stop advertising
  static Future<void> stopAdvertising() => _platform.stopAdvertising();

  /// Get the callback when advertising is started or stopped
  static void setAdvertisingStatusUpdateCallback(
          AdvertisementStatusUpdateCallback callback) =>
      _platform.setAdvertisingStatusUpdateCallback(callback);

  /// Get the callback when bluetooth radio state changes
  static void setBleStateChangeCallback(BleStateCallback callback) =>
      _platform.setBleStateChangeCallback(callback);

  /// Get the callback when bond state changes
  static void setBondStateChangeCallback(BondStateCallback callback) =>
      _platform.setBondStateChangeCallback(callback);

  /// Only available on iOS/Mac/Windows
  static void setCharacteristicSubscriptionChangeCallback(
          CharacteristicSubscriptionChangeCallback callback) =>
      _platform.setCharacteristicSubscriptionChangeCallback(callback);

  /// Only available on Android
  static void setConnectionStateChangeCallback(
          ConnectionStateChangeCallback callback) =>
      _platform.setConnectionStateChangeCallback(callback);

  /// Only available on Android/Windows
  static void setMtuChangeCallback(MtuChangeCallback callback) =>
      _platform.setMtuChangeCallback(callback);

  /// Get the callback when a read request is made
  static void setReadRequestCallback(ReadRequestCallback callback) =>
      _platform.setReadRequestCallback(callback);

  /// Get the callback when a service is added
  static void setServiceAddedCallback(ServiceAddedCallback callback) =>
      _platform.setServiceAddedCallback(callback);

  /// Get the callback when a write request is made
  static void setWriteRequestCallback(WriteRequestCallback callback) =>
      _platform.setWriteRequestCallback(callback);
}

import 'dart:typed_data';

import 'package:flutter_ble_peripheral_slave/flutter_ble_peripheral_slave.dart';

abstract class BlePeripheralInterface {
  Future initialize();

  Future<bool> isSupported();

  Future<bool> askBlePermission();

  Future<bool?> isAdvertising();

  Future<void> addService(BleService service, {Duration? timeout});

  Future<void> removeService(String serviceId) {
    throw UnimplementedError();
  }

  Future<void> clearServices() {
    throw UnimplementedError();
  }

  Future<List<String>> getServices() {
    throw UnimplementedError();
  }

  Future<void> updateCharacteristic({
    required String characteristicId,
    required Uint8List value,
    String? deviceId,
  });

  Future<void> startAdvertising({
    required List<String> services,
    String? localName,
    int? timeout,
    ManufacturerData? manufacturerData,
    bool addManufacturerDataInScanResponse = false,
  });

  Future<void> stopAdvertising();

  /// Callback handlers
  void setAdvertisingStatusUpdateCallback(
      AdvertisementStatusUpdateCallback callback) {
    throw UnimplementedError();
  }

  void setBleStateChangeCallback(BleStateCallback callback) {
    throw UnimplementedError();
  }

  void setBondStateChangeCallback(BondStateCallback callback) {
    throw UnimplementedError();
  }

  void setCharacteristicSubscriptionChangeCallback(
      CharacteristicSubscriptionChangeCallback callback) {
    throw UnimplementedError();
  }

  void setConnectionStateChangeCallback(
      ConnectionStateChangeCallback callback) {
    throw UnimplementedError();
  }

  void setMtuChangeCallback(MtuChangeCallback callback) {
    throw UnimplementedError();
  }

  void setReadRequestCallback(ReadRequestCallback callback) {
    throw UnimplementedError();
  }

  void setServiceAddedCallback(ServiceAddedCallback callback) {
    throw UnimplementedError();
  }

  void setWriteRequestCallback(WriteRequestCallback callback) {
    throw UnimplementedError();
  }
}

typedef AvailableDevicesListener = void Function(
    String deviceId, bool isAvailable);

typedef AdvertisementStatusUpdateCallback = void Function(
    bool advertising, String? error);

typedef BleStateCallback = void Function(bool state);

typedef BondStateCallback = void Function(String deviceId, BondState bondState);

typedef CharacteristicSubscriptionChangeCallback = void Function(
    String deviceId, String characteristicId, bool isSubscribed, String? name);

typedef ConnectionStateChangeCallback = void Function(
    String deviceId, bool connected);

typedef ReadRequestCallback = ReadRequestResult? Function(
    String deviceId, String characteristicId, int offset, Uint8List? value);

typedef ServiceAddedCallback = void Function(String serviceId, String? error);

typedef WriteRequestCallback = WriteRequestResult? Function(
    String deviceId, String characteristicId, int offset, Uint8List? value);

typedef MtuChangeCallback = void Function(String deviceId, int mtu);

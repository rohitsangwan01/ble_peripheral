import 'dart:async';

import 'package:flutter_ble_peripheral_slave/flutter_ble_peripheral_slave.dart';
import 'package:flutter_ble_peripheral_slave/src/pigeon/ble_callback_handler.dart';
import 'package:flutter_ble_peripheral_slave/src/ble_peripheral_interface.dart';
import 'package:flutter/foundation.dart';

class BlePeripheralPigeon extends BlePeripheralInterface {
  BlePeripheralPigeon._();
  static BlePeripheralPigeon? _instance;
  static BlePeripheralPigeon get instance =>
      _instance ??= BlePeripheralPigeon._();

  final _channel = BlePeripheralChannel();
  final _callbackHandler = BleCallbackHandler();

  /// Make sure to call this method before calling any other method
  @override
  Future initialize() async {
    await _channel.initialize();
    BleCallback.setUp(_callbackHandler);
  }

  /// check if blePeripheral is supported on the device
  @override
  Future<bool> isSupported() => _channel.isSupported();

  /// To ask for ble permission
  @override
  @Deprecated('use permission_handler plugin instead')
  Future<bool> askBlePermission() => _channel.askBlePermission();

  /// check if blePeripheral is advertising
  @override
  Future<bool?> isAdvertising() => _channel.isAdvertising();

  /// Add a service to the peripheral, and get success result in [setServiceAddedCallback]
  /// Make sure to add next service only after getting success result for previous service
  /// add all services before calling [startAdvertising]
  @override
  Future<void> addService(BleService service, {Duration? timeout}) async {
    Completer<void> completer = Completer<void>();
    _callbackHandler.serviceResultStreamController.stream
        .where((event) =>
            event.serviceId.toLowerCase() == service.uuid.toLowerCase())
        .first
        .timeout(
      timeout ?? const Duration(seconds: 5),
      onTimeout: () async {
        return (serviceId: service.uuid, error: 'Service addition timed out');
      },
    ).then((value) {
      if (!completer.isCompleted) {
        if (value.error != null) {
          completer.completeError(value.error!);
        } else {
          completer.complete();
        }
      }
    });
    await _channel.addService(service);
    await completer.future;
  }

  /// Remove a service from the peripheral
  @override
  Future<void> removeService(String serviceId) =>
      _channel.removeService(serviceId);

  /// Clear all services from the peripheral
  @override
  Future<void> clearServices() => _channel.clearServices();

  /// Get list of services added to the peripheral
  @override
  Future<List<String>> getServices() => _channel.getServices();

  /// To update the value of a characteristic
  @override
  Future<void> updateCharacteristic({
    required String characteristicId,
    required Uint8List value,
    String? deviceId,
  }) {
    return _channel.updateCharacteristic(characteristicId, value, deviceId);
  }

  /// Start advertising with the given services and local name
  /// make sure to add services before calling this method
  @override
  Future<void> startAdvertising({
    required List<String> services,
    String? localName,
    int? timeout,
    ManufacturerData? manufacturerData,
    bool addManufacturerDataInScanResponse = false,
  }) {
    if (defaultTargetPlatform == TargetPlatform.windows &&
        manufacturerData == null) {
      // Windows crashes on passing null manufacturerData
      manufacturerData = ManufacturerData(
        manufacturerId: 0,
        data: Uint8List(0),
      );
    }
    return _channel.startAdvertising(services, localName, timeout,
        manufacturerData, addManufacturerDataInScanResponse);
  }

  /// Stop advertising
  @override
  Future<void> stopAdvertising() => _channel.stopAdvertising();

  /// Get the callback when advertising is started or stopped
  @override
  void setAdvertisingStatusUpdateCallback(
          AdvertisementStatusUpdateCallback callback) =>
      _callbackHandler.advertingStarted = callback;

  /// Get the callback when bluetooth radio state changes
  @override
  void setBleStateChangeCallback(BleStateCallback callback) =>
      _callbackHandler.bleStateChange = callback;

  /// Get the callback when bond state changes
  @override
  void setBondStateChangeCallback(BondStateCallback callback) =>
      _callbackHandler.bondStateChange = callback;

  /// Only available on iOS/Mac/Windows
  @override
  void setCharacteristicSubscriptionChangeCallback(
          CharacteristicSubscriptionChangeCallback callback) =>
      _callbackHandler.characteristicSubscriptionChange = callback;

  /// Only available on Android
  @override
  void setConnectionStateChangeCallback(
          ConnectionStateChangeCallback callback) =>
      _callbackHandler.connectionStateChange = callback;

  /// Only available on Android/Windows
  @override
  void setMtuChangeCallback(MtuChangeCallback callback) =>
      _callbackHandler.mtuChangeCallback = callback;

  /// Get the callback when a read request is made
  @override
  void setReadRequestCallback(ReadRequestCallback callback) =>
      _callbackHandler.readRequest = callback;

  /// Get the callback when a service is added
  @override
  void setServiceAddedCallback(ServiceAddedCallback callback) =>
      _callbackHandler.serviceAdded = callback;

  /// Get the callback when a write request is made
  @override
  void setWriteRequestCallback(WriteRequestCallback callback) =>
      _callbackHandler.writeRequest = callback;
}

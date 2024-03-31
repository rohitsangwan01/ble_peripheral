import 'dart:typed_data';

import 'package:ble_peripheral/src/ble_callback_handler.dart';
import 'package:ble_peripheral/src/generated/ble_peripheral.g.dart';
export 'package:ble_peripheral/src/models/ble_enums.dart';
export 'package:ble_peripheral/src/generated/ble_peripheral.g.dart';

class BlePeripheral {
  static final _channel = BlePeripheralChannel();
  static final _callbackHandler = BleCallbackHandler();

  /// Make sure to call this method before calling any other method
  static Future initialize() async {
    await _channel.initialize();
    BleCallback.setup(_callbackHandler);
  }

  /// check if blePeripheral is supported on the device
  static Future<bool> isSupported() => _channel.isSupported();

  /// To ask for ble permission
  @Deprecated('use permission_handler plugin instead')
  static Future<bool> askBlePermission() => _channel.askBlePermission();

  /// check if blePeripheral is advertising
  static Future<bool?> isAdvertising() => _channel.isAdvertising();

  /// Add a service to the peripheral, and get success result in [setServiceAddedCallback]
  /// Make sure to add next service only after getting success result for previous service
  /// add all services before calling [startAdvertising]
  static Future<void> addService(
    BleService service, {
    Duration? timeout,
  }) async {
    await _channel.addService(service);
    (String, String?) result = await _callbackHandler
        .serviceResultStreamController.stream
        .where((event) => event.$1.toLowerCase() == service.uuid.toLowerCase())
        .first
        .timeout(
          timeout ?? const Duration(seconds: 5),
          onTimeout: () => (
            service.uuid,
            "Timeout in verifying service addition",
          ),
        );
    if (result.$2 != null) throw Exception(result.$2);
  }

  static Future<void> removeService(String serviceId) =>
      _channel.removeService(serviceId);

  static Future<void> clearServices() => _channel.clearServices();

  static Future<List<String>> getServices() async {
    return List<String>.from(
      (await _channel.getServices()).where((e) => e != null).toList(),
    );
  }

  /// To update the value of a characteristic
  static Future<void> updateCharacteristic({
    required String deviceId,
    required String characteristicId,
    required Uint8List value,
  }) {
    return _channel.updateCharacteristic(deviceId, characteristicId, value);
  }

  /// Start advertising with the given services and local name
  /// make sure to add services before calling this method
  static Future<void> startAdvertising({
    required List<String?> services,
    required String localName,
    int? timeout,
    ManufacturerData? manufacturerData,
    bool addManufacturerDataInScanResponse = false,
  }) {
    return _channel.startAdvertising(services, localName, timeout,
        manufacturerData, addManufacturerDataInScanResponse);
  }

  /// Stop advertising
  static Future<void> stopAdvertising() => _channel.stopAdvertising();

  // Setters for callback handlers

  /// This callback is common for android and Apple, simply tells us when a central device is ready to use
  /// on Android, we gets a device in [setConnectionStateChangeCallback] when a central device is ready to use
  /// on iOS, we gets a device in [setCharacteristicSubscriptionChangeCallback] when a central device is ready to use
  ///
  static void setBleCentralAvailabilityCallback(
          AvailableDevicesListener callback) =>
      _callbackHandler.availableDevicesListener = callback;

  static void setAdvertisingStatusUpdateCallback(
          AdvertisementStatusUpdateCallback callback) =>
      _callbackHandler.advertingStarted = callback;

  static void setBleStateChangeCallback(BleStateCallback callback) =>
      _callbackHandler.bleStateChange = callback;

  static void setBondStateChangeCallback(BondStateCallback callback) =>
      _callbackHandler.bondStateChange = callback;

  /// Only available on iOS/Mac
  static void setCharacteristicSubscriptionChangeCallback(
          CharacteristicSubscriptionChangeCallback callback) =>
      _callbackHandler.characteristicSubscriptionChange = callback;

  /// Only available on Android
  static void setConnectionStateChangeCallback(
          ConnectionStateChangeCallback callback) =>
      _callbackHandler.connectionStateChange = callback;

  /// Only available on Android
  static void setMtuChangeCallback(MtuChangeCallback callback) =>
      _callbackHandler.mtuChangeCallback = callback;

  static void setReadRequestCallback(ReadRequestCallback callback) =>
      _callbackHandler.readRequest = callback;

  static void setServiceAddedCallback(ServiceAddedCallback callback) =>
      _callbackHandler.serviceAdded = callback;

  static void setWriteRequestCallback(WriteRequestCallback callback) =>
      _callbackHandler.writeRequest = callback;
}

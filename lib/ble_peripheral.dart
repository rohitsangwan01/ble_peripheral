import 'dart:typed_data';

import 'package:ble_peripheral/src/ble_peripheral.g.dart';
export 'package:ble_peripheral/src/models.dart';
export 'package:ble_peripheral/src/ble_peripheral.g.dart';

class BlePeripheral {
  final _channel = BlePeripheralChannel();

  Future initialize() async {
    await _channel.initialize();
  }

  Future<bool> isSupported() => _channel.isSupported();

  Future<void> stopAdvertising() => _channel.stopAdvertising();

  Future<void> addServices(List<BleService> services) =>
      _channel.addServices(services);

  Future<void> updateCharacteristic(
          BleCentral central, BleCharacteristic char, Uint8List value) =>
      _channel.updateCharacteristic(central, char, value);

  Future<void> startAdvertising(List<UUID> services, String localName) =>
      _channel.startAdvertising(services, localName);

  void setBleCallback(BleCallback callback) => BleCallback.setup(callback);
}

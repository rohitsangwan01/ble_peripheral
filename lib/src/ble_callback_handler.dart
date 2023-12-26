import 'dart:async';
import 'dart:typed_data';

import 'package:ble_peripheral/ble_peripheral.dart';

class BleCallbackHandler extends BleCallback {
  Function(String? error)? advertingStarted;
  Function(bool state)? bleStateChange;
  Function(String deviceId, int bondState)? bondStateChange;
  Function(String deviceId, String characteristicId, bool isSubscribed)?
      characteristicSubscriptionChange;
  Function(String deviceId, bool connected)? connectionStateChange;
  ReadRequestResult? Function(
      String characteristicId, int offset, Uint8List? value)? readRequest;
  Function(String serviceId, String? error)? serviceAdded;

  Function(String characteristicId, int offset, Uint8List? value)? writeRequest;
  AvailableDevicesListener? availableDevicesListener;
  final serviceResultStreamController =
      StreamController<(String, String?)>.broadcast();

  @override
  void onAdvertisingStarted(String? error) => advertingStarted?.call(error);

  @override
  void onBleStateChange(bool state) => bleStateChange?.call(state);

  @override
  void onBondStateChange(String deviceId, int bondState) =>
      bondStateChange?.call(deviceId, bondState);

  @override
  void onCharacteristicSubscriptionChange(
      String deviceId, String characteristicId, bool isSubscribed) {
    characteristicSubscriptionChange?.call(
        deviceId, characteristicId, isSubscribed);
    availableDevicesListener?.call(deviceId, isSubscribed);
  }

  @override
  void onConnectionStateChange(String deviceId, bool connected) {
    connectionStateChange?.call(deviceId, connected);
    availableDevicesListener?.call(deviceId, connected);
  }

  @override
  ReadRequestResult? onReadRequest(
          String characteristicId, int offset, Uint8List? value) =>
      readRequest?.call(characteristicId, offset, value);

  @override
  void onServiceAdded(String serviceId, String? error) {
    serviceAdded?.call(serviceId, error);
    serviceResultStreamController.add((serviceId, error));
  }

  @override
  void onWriteRequest(String characteristicId, int offset, Uint8List? value) =>
      writeRequest?.call(characteristicId, offset, value);
}

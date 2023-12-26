import 'dart:async';
import 'dart:typed_data';

import 'package:ble_peripheral/ble_peripheral.dart';

class BleCallbackHandler extends BleCallback {
  AdvertisementCallback? advertingStarted;
  BleStateCallback? bleStateChange;
  BondStateCallback? bondStateChange;
  CharacteristicSubscriptionChangeCallback? characteristicSubscriptionChange;
  ConnectionStateChangeCallback? connectionStateChange;
  ReadRequestCallback? readRequest;
  ServiceAddedCallback? serviceAdded;
  WriteRequestCallback? writeRequest;
  AvailableDevicesListener? availableDevicesListener;
  MtuChangeCallback? mtuChangeCallback;

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

  @override
  void onMtuChange(String deviceId, int mtu) =>
      mtuChangeCallback?.call(deviceId, mtu);
}

typedef AvailableDevicesListener = void Function(
    String deviceId, bool isAvailable);
typedef AdvertisementCallback = void Function(String? error);
typedef BleStateCallback = void Function(bool state);
typedef BondStateCallback = void Function(String deviceId, int bondState);
typedef CharacteristicSubscriptionChangeCallback = void Function(
    String deviceId, String characteristicId, bool isSubscribed);
typedef ConnectionStateChangeCallback = void Function(
    String deviceId, bool connected);
typedef ReadRequestCallback = ReadRequestResult? Function(
    String characteristicId, int offset, Uint8List? value);
typedef ServiceAddedCallback = void Function(String serviceId, String? error);
typedef WriteRequestCallback = void Function(
    String characteristicId, int offset, Uint8List? value);
typedef MtuChangeCallback = void Function(String deviceId, int mtu);

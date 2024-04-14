import 'dart:async';
import 'dart:typed_data';

import 'package:ble_peripheral/ble_peripheral.dart';

class BleCallbackHandler extends BleCallback {
  AdvertisementStatusUpdateCallback? advertingStarted;
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
      StreamController<({String serviceId, String? error})>.broadcast();

  @override
  void onAdvertisingStatusUpdate(bool advertising, String? error) =>
      advertingStarted?.call(advertising, error);

  @override
  void onBleStateChange(bool state) => bleStateChange?.call(state);

  @override
  void onBondStateChange(String deviceId, BondState bondState) =>
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
  ReadRequestResult? onReadRequest(String deviceId, String characteristicId,
          int offset, Uint8List? value) =>
      readRequest?.call(deviceId, characteristicId, offset, value);

  @override
  void onServiceAdded(String serviceId, String? error) {
    serviceAdded?.call(serviceId, error);
    serviceResultStreamController.add((serviceId: serviceId, error: error));
  }

  @override
  WriteRequestResult? onWriteRequest(
      String deviceId, String characteristicId, int offset, Uint8List? value) {
    return writeRequest?.call(deviceId, characteristicId, offset, value) ??
        WriteRequestResult();
  }

  @override
  void onMtuChange(String deviceId, int mtu) =>
      mtuChangeCallback?.call(deviceId, mtu);
}

typedef AvailableDevicesListener = void Function(
    String deviceId, bool isAvailable);
typedef AdvertisementStatusUpdateCallback = void Function(
    bool advertising, String? error);
typedef BleStateCallback = void Function(bool state);
typedef BondStateCallback = void Function(String deviceId, BondState bondState);
typedef CharacteristicSubscriptionChangeCallback = void Function(
    String deviceId, String characteristicId, bool isSubscribed);
typedef ConnectionStateChangeCallback = void Function(
    String deviceId, bool connected);
typedef ReadRequestCallback = ReadRequestResult? Function(
    String deviceId, String characteristicId, int offset, Uint8List? value);
typedef ServiceAddedCallback = void Function(String serviceId, String? error);
typedef WriteRequestCallback = WriteRequestResult? Function(
    String deviceId, String characteristicId, int offset, Uint8List? value);
typedef MtuChangeCallback = void Function(String deviceId, int mtu);

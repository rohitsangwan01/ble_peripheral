import 'dart:async';
import 'dart:typed_data';

import 'package:ble_peripheral/ble_peripheral.dart';
import 'package:ble_peripheral/src/ble_peripheral_interface.dart';

/// A class that handles the callbacks from the BLE plugin.
/// This class is used to convert the callbacks to a more readable format.
class BleCallbackHandler extends BleCallback {
  AdvertisementStatusUpdateCallback? advertingStarted;
  BleStateCallback? bleStateChange;
  BondStateCallback? bondStateChange;
  CharacteristicSubscriptionChangeCallback? characteristicSubscriptionChange;
  ConnectionStateChangeCallback? connectionStateChange;
  ReadRequestCallback? readRequest;
  ServiceAddedCallback? serviceAdded;
  WriteRequestCallback? writeRequest;
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
  }

  @override
  void onConnectionStateChange(String deviceId, bool connected) {
    connectionStateChange?.call(deviceId, connected);
  }

  @override
  ReadRequestResult? onReadRequest(
    String deviceId,
    String characteristicId,
    int offset,
    Uint8List? value,
  ) {
    // Windows crash if return value is null
    return readRequest?.call(deviceId, characteristicId, offset, value) ??
        ReadRequestResult(
          value: Uint8List.fromList([0]),
        );
  }

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

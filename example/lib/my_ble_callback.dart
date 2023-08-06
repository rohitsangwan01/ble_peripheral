import 'package:ble_peripheral/ble_peripheral.dart';

import 'package:ble_peripheral_example/home_controller.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class MyBleCallback extends BleCallback {
  HomeController controller = Get.find();

  @override
  void onAdvertisingStarted(String? error) {
    Get.log("advertisingStarted: $error");
    controller.isAdvertising.value = error == null;
  }

  @override
  void onBleStateChange(bool state) => controller.onBleStateChange(state);

  @override
  void onSubscribe(BleCentral bleCentral, BleCharacteristic characteristic) =>
      controller.onDeviceSubscribe(bleCentral, characteristic);

  @override
  void onUnsubscribe(BleCentral bleCentral, BleCharacteristic characteristic) =>
      controller.onDeviceUnsubscribe(bleCentral, characteristic);

  @override
  void onServiceAdded(BleService service, String? error) {
    Get.log("Service added: ${service.uuid.value}");
  }

  @override
  void onWriteRequest(
      BleCharacteristic characteristic, int offset, Uint8List? value) {
    Get.log("characteristic WriteRequires: ${characteristic.uuid.value}");
  }

  @override
  void onCharacteristicSubscriptionChange(
      BleCentral central, BleCharacteristic characteristic, bool isSubscribed) {
    Get.log("characteristic SubscriptionChange: ${characteristic.uuid}");
  }

  @override
  void onConnectionStateChange(BleCentral central, bool connected) =>
      controller.onConnectionStateChange(central, connected);

  @override
  void onBondStateChange(BleCentral central, int bondState) {
    Get.log(
      "onBondStateChange: ${central.uuid.value} : ${BondState.fromInt(bondState)}",
    );
  }

  @override
  ReadRequestResult? onReadRequest(
      BleCharacteristic characteristic, int offset, Uint8List? value) {
    Get.log("characteristic ReadRequest: ${characteristic.uuid.value}");
    return ReadRequestResult(
      value: Uint8List.fromList([]),
    );
  }
}

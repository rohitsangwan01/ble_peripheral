// ignore_for_file: non_constant_identifier_names

import 'dart:convert';

import 'package:ble_peripheral/ble_peripheral.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

class HomeController extends GetxController {
  RxBool isAdvertising = false.obs;
  RxBool isBleOn = false.obs;
  RxList<String> devices = <String>[].obs;

  String get deviceName => switch (defaultTargetPlatform) {
        TargetPlatform.android => "BleDroid",
        TargetPlatform.iOS => "BleIOS",
        TargetPlatform.macOS => "BleMac",
        TargetPlatform.windows => "BleWin",
        _ => "TestDevice"
      };

  var manufacturerData = ManufacturerData(
    manufacturerId: 0x012D,
    data: Uint8List.fromList([
      0x03,
      0x00,
      0x64,
      0x00,
      0x45,
      0x31,
      0x22,
      0xAB,
      0x00,
      0x21,
      0x60,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00
    ]),
  );

  // Battery Service
  String serviceBattery = "0000180F-0000-1000-8000-00805F9B34FB";
  String characteristicBatteryLevel = "00002A19-0000-1000-8000-00805F9B34FB";
  // Test service
  String serviceTest = "0000180A-0000-1000-8000-00805F9B34FB";
  String characteristicTest = "00002A18-0000-1000-8000-00805F9B34FB";

  @override
  void onInit() {
    _initialize();
    // setup callbacks
    BlePeripheral.setBleStateChangeCallback(isBleOn);

    BlePeripheral.setAdvertingStartedCallback((error) {
      isAdvertising.value = error == null;
      Get.log("AdvertingStarted: $error");
    });

    BlePeripheral.setBleCentralAvailabilityCallback((deviceId, isAvailable) {
      Get.log("OnDeviceAvailabilityChange: $deviceId : $isAvailable");
      if (isAvailable) {
        if (!devices.any((element) => element != deviceId)) {
          devices.add(deviceId);
        }
      } else {
        devices.removeWhere((element) => element == deviceId);
      }
    });

    BlePeripheral.setReadRequestCallback(
        (deviceId, characteristicId, offset, value) {
      Get.log("ReadRequest: $deviceId $characteristicId : $offset : $value");
      return ReadRequestResult(value: utf8.encode("Hello World"));
    });

    BlePeripheral.setWriteRequestCallback(
        (deviceId, characteristicId, offset, value) {
      Get.log("WriteRequest: $deviceId $characteristicId : $offset : $value");
      // return WriteRequestResult(status: 144);
      return null;
    });

    super.onInit();
  }

  void _initialize() async {
    try {
      await BlePeripheral.initialize();
    } catch (e) {
      Get.log("InitializationError: $e");
    }
  }

  void startAdvertising() async {
    await BlePeripheral.startAdvertising(
      services: [serviceBattery, serviceTest],
      localName: deviceName,
      manufacturerData: manufacturerData,
      addManufacturerDataInScanResponse: true,
    );
  }

  void addServices() async {
    var notificationControlDescriptor = BleDescriptor(
      uuid: "00002908-0000-1000-8000-00805F9B34FB",
      value: Uint8List.fromList([0, 1]),
      permissions: [
        AttributePermissions.readable.index,
        AttributePermissions.writeable.index
      ],
    );

    await BlePeripheral.addService(
      BleService(
        uuid: serviceBattery,
        primary: true,
        characteristics: [
          BleCharacteristic(
            uuid: characteristicBatteryLevel,
            properties: [
              CharacteristicProperties.read.index,
              CharacteristicProperties.notify.index
            ],
            value: null,
            permissions: [AttributePermissions.readable.index],
          ),
        ],
      ),
    );

    await BlePeripheral.addService(
      BleService(
        uuid: serviceTest,
        primary: true,
        characteristics: [
          BleCharacteristic(
            uuid: characteristicTest,
            properties: [
              CharacteristicProperties.read.index,
              CharacteristicProperties.notify.index,
              CharacteristicProperties.write.index,
            ],
            descriptors: [notificationControlDescriptor],
            value: null,
            permissions: [
              AttributePermissions.readable.index,
              AttributePermissions.writeable.index
            ],
          ),
        ],
      ),
    );
    Get.log("Services added");
  }

  /// Update characteristic value, to all the devices which are subscribed to it
  void updateCharacteristic() async {
    for (var device in devices) {
      try {
        await BlePeripheral.updateCharacteristic(
          deviceId: device,
          characteristicId: characteristicTest,
          value: utf8.encode("Test Data"),
        );
      } catch (e) {
        Get.log("UpdateCharacteristicError: $e");
      }
    }
  }
}

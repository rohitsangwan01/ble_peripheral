// ignore_for_file: non_constant_identifier_names

import 'package:ble_peripheral/ble_peripheral.dart';
import 'package:ble_peripheral_example/my_ble_callback.dart';
import 'package:get/get.dart';

class HomeController extends GetxController {
  final BlePeripheral _blePeripheral = BlePeripheral();
  RxBool isAdvertising = false.obs;
  RxBool isBleOn = false.obs;
  RxList<BleCentral> devices = <BleCentral>[].obs;

  var deviceName = "TestBle";
  UUID serviceBattery = UUID(value: "0000180F-0000-1000-8000-00805F9B34FB");
  UUID characteristicBatteryLevel =
      UUID(value: "00002A19-0000-1000-8000-00805F9B34FB");

  @override
  void onInit() {
    _initialize();
    super.onInit();
  }

  void _initialize() async {
    try {
      await _blePeripheral.initialize();
      _blePeripheral.setBleCallback(MyBleCallback());
    } catch (e) {
      Get.log("InitializationError: $e");
    }
  }

  void start() async {
    await _blePeripheral.addServices([_batteryService]);
    await _blePeripheral.startAdvertising(
      [serviceBattery],
      deviceName,
    );
  }

  void stop() => _blePeripheral.stopAdvertising();

  /// We get this callback on Android
  void onConnectionStateChange(BleCentral bleCentral, bool connected) {
    Get.log("onConnectionStateChange: ${bleCentral.uuid.value} : $connected");
    if (connected) {
      devices.add(bleCentral);
    } else {
      devices.removeWhere(
        (element) => element.uuid.value == bleCentral.uuid.value,
      );
    }
  }

  /// We get these callbacks on ios
  void onDeviceSubscribe(
    BleCentral bleCentral,
    BleCharacteristic characteristic,
  ) {
    var containsDevice =
        devices.any((element) => element.uuid.value == bleCentral.uuid.value);
    if (!containsDevice) devices.add(bleCentral);
    Get.log(
        "Joined: ${bleCentral.uuid.value} for char: ${characteristic.uuid.value}");
  }

  void onDeviceUnsubscribe(
    BleCentral bleCentral,
    BleCharacteristic characteristic,
  ) {
    // devices.removeWhere((element) => element.uuid.value == bleCentral.uuid.value);
    Get.log(
        "Unsubscribed: ${bleCentral.uuid.value} for char: ${characteristic.uuid.value}");
  }

  void onBleStateChange(bool isActive) {
    isBleOn.value = isActive;
    Get.log("onBleStateChange: $isActive");
  }

  BleService get _batteryService {
    return BleService(
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
    );
  }
}

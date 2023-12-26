import 'package:pigeon/pigeon.dart';

// dart run pigeon --input pigeons/ble.dart
@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'ble_peripheral',
    dartOut: 'lib/src/generated/ble_peripheral.g.dart',
    dartOptions: DartOptions(),
    kotlinOut:
        'android/src/main/kotlin/com/rohit/ble_peripheral/BlePeripheral.g.kt',
    swiftOut: 'darwin/Classes/BlePeripheral.g.swift',
    cppOptions: CppOptions(namespace: 'ble_peripheral'),
    kotlinOptions: KotlinOptions(package: 'com.rohit.ble_peripheral'),
    swiftOptions: SwiftOptions(),
    cppHeaderOut: 'windows/BlePeripheral.g.h',
    cppSourceOut: 'windows/BlePeripheral.g.cpp',
  ),
)

/// Models
class BleService {
  String uuid;
  bool primary;
  List<BleCharacteristic?> characteristics;
  BleService(this.uuid, this.primary, this.characteristics);
}

class BleCharacteristic {
  String uuid;
  List<int?> properties;
  List<int?> permissions;
  List<BleDescriptor?>? descriptors;
  Uint8List? value;
  BleCharacteristic(this.uuid, this.value, this.descriptors, this.properties,
      this.permissions);
}

class BleDescriptor {
  String uuid;
  Uint8List? value;
  List<int?>? permissions;
  BleDescriptor(this.uuid, this.value, this.permissions);
}

class ReadRequestResult {
  Uint8List value;
  int? offset;
  ReadRequestResult({required this.value, this.offset});
}

class ManufacturerData {
  int manufacturerId;
  Uint8List data;
  ManufacturerData({required this.manufacturerId, required this.data});
}

/// Flutter -> Native
@HostApi()
abstract class BlePeripheralChannel {
  void initialize();

  bool? isAdvertising();

  bool isSupported();

  void stopAdvertising();

  bool askBlePermission();

  void addService(BleService service);

  void startAdvertising(
    List<String> services,
    String localName,
    int? timeout,
    ManufacturerData? manufacturerData,
    bool addManufacturerDataInScanResponse,
  );

  void updateCharacteristic(
    String devoiceID,
    String characteristicId,
    Uint8List value,
  );
}

/// Native -> Flutter
@FlutterApi()
abstract class BleCallback {
  ReadRequestResult? onReadRequest(
    String characteristicId,
    int offset,
    Uint8List? value,
  );

  void onWriteRequest(
    String characteristicId,
    int offset,
    Uint8List? value,
  );

  void onCharacteristicSubscriptionChange(
    String deviceId,
    String characteristicId,
    bool isSubscribed,
  );

  void onAdvertisingStarted(String? error);

  void onBleStateChange(bool state);

  void onServiceAdded(String serviceId, String? error);

  // Android only
  void onConnectionStateChange(String deviceId, bool connected);

  void onBondStateChange(String deviceId, int bondState);
}

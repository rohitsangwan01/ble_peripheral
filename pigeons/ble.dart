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

/// Enums
enum BondState { bonding, bonded, none }

/// Models
class BleService {
  String uuid;
  bool primary;
  List<BleCharacteristic> characteristics;
  BleService(this.uuid, this.primary, this.characteristics);
}

// Use enums instead of int after fixing: https://github.com/flutter/flutter/issues/133728
class BleCharacteristic {
  String uuid;
  List<int> properties;
  List<int> permissions;
  List<BleDescriptor>? descriptors;
  Uint8List? value;

  BleCharacteristic(
    this.uuid,
    this.value,
    this.descriptors,
    this.properties,
    this.permissions,
  );
}

class BleDescriptor {
  String uuid;
  Uint8List? value;
  List<int>? permissions;
  BleDescriptor(this.uuid, this.value, this.permissions);
}

class ReadRequestResult {
  Uint8List value;
  int? offset;
  int? status;
  ReadRequestResult({required this.value, this.offset});
}

class WriteRequestResult {
  Uint8List? value;
  int? offset;
  int? status;
  WriteRequestResult({this.value, this.offset, this.status});
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

  void removeService(String serviceId);

  void clearServices();

  List<String> getServices();

  void startAdvertising(
    List<String> services,
    String? localName,
    int? timeout,
    ManufacturerData? manufacturerData,
    bool addManufacturerDataInScanResponse,
  );

  void updateCharacteristic(
    String characteristicId,
    Uint8List value,
    String? deviceId,
  );
}

/// Native -> Flutter
@FlutterApi()
abstract class BleCallback {
  ReadRequestResult? onReadRequest(
    String deviceId,
    String characteristicId,
    int offset,
    Uint8List? value,
  );

  WriteRequestResult? onWriteRequest(
    String deviceId,
    String characteristicId,
    int offset,
    Uint8List? value,
  );

  void onCharacteristicSubscriptionChange(
    String deviceId,
    String characteristicId,
    bool isSubscribed,
    String? name,
  );

  void onAdvertisingStatusUpdate(bool advertising, String? error);

  void onBleStateChange(bool state);

  void onServiceAdded(String serviceId, String? error);

  void onMtuChange(String deviceId, int mtu);

  // Android only
  void onConnectionStateChange(String deviceId, bool connected);

  void onBondStateChange(String deviceId, BondState bondState);
}

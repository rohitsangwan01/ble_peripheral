import 'package:pigeon/pigeon.dart';

// dart run pigeon --input pigeons/ble.dart
@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'ble_peripheral',
    dartOut: 'lib/src/ble_peripheral.g.dart',
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
class UUID {
  String value;
  UUID(this.value);
}

class BleDescriptor {
  UUID uuid;
  Uint8List? value;
  List<int?>? permissions;
  BleDescriptor(this.uuid, this.value, this.permissions);
}

class BleCharacteristic {
  UUID uuid;
  List<int?> properties;
  List<int?> permissions;
  List<BleDescriptor?>? descriptors;
  Uint8List? value;

  BleCharacteristic(
    this.uuid,
    this.value,
    this.descriptors,
    this.properties,
    this.permissions,
  );
}

class BleService {
  UUID uuid;
  bool primary;

  List<BleCharacteristic?> characteristics;
  BleService(
    this.uuid,
    this.primary,
    this.characteristics,
  );
}

class BleCentral {
  UUID uuid;
  BleCentral(this.uuid);
}

class ReadRequestResult {
  Uint8List value;
  int? offset;
  ReadRequestResult({required this.value, this.offset});
}

/// Flutter -> Native
@HostApi()
abstract class BlePeripheralChannel {
  void initialize();

  bool isAdvertising();

  bool isSupported();

  void stopAdvertising();

  void addServices(List<BleService> services);

  void startAdvertising(
    List<UUID> services,
    String localName,
      int timeoutMillis,
  );

  void updateCharacteristic(
    BleCentral central,
    BleCharacteristic characteristic,
    Uint8List value,
  );
}

/// Native -> Flutter
@FlutterApi()
abstract class BleCallback {
  ReadRequestResult? onReadRequest(
    BleCharacteristic characteristic,
    int offset,
    Uint8List? value,
  );

  void onWriteRequest(
    BleCharacteristic characteristic,
    int offset,
    Uint8List? value,
  );

  void onCharacteristicSubscriptionChange(
    BleCentral central,
    BleCharacteristic characteristic,
    bool isSubscribed,
  );

  void onSubscribe(BleCentral bleCentral, BleCharacteristic characteristic);

  void onUnsubscribe(BleCentral bleCentral, BleCharacteristic characteristic);

  void onAdvertisingStarted(String? error);

  void onBleStateChange(bool state);

  void onServiceAdded(BleService service, String? error);

  // Android only
  void onConnectionStateChange(BleCentral central, bool connected);

  void onBondStateChange(BleCentral central, int bondState);
}

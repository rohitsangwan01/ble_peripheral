import 'dart:typed_data';

import 'package:ble_peripheral/ble_peripheral.dart';

class BleService {
  String uuid;
  bool primary;
  List<BleCharacteristic?> characteristics;

  BleService({
    required this.uuid,
    required this.primary,
    required this.characteristics,
  });
}

class BleCharacteristic {
  String uuid;
  List<CharacteristicProperties?> properties;
  List<AttributePermissions?> permissions;
  List<BleDescriptor?>? descriptors;

  Uint8List? value;
  BleCharacteristic({
    required this.uuid,
    required this.properties,
    required this.permissions,
    this.descriptors,
    this.value,
  });
}

class BleDescriptor {
  String uuid;
  Uint8List? value;
  List<AttributePermissions?>? permissions;

  BleDescriptor({
    required this.uuid,
    this.value,
    this.permissions,
  });
}

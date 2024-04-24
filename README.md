# Ble Peripheral

[![ble_peripheral version](https://img.shields.io/pub/v/ble_peripheral?label=ble_peripheral)](https://pub.dev/packages/ble_peripheral)

Ble peripheral is a Flutter plugin that allows you to use your device as Bluetooth Low Energy (BLE) peripheral

This is an OS-independent plugin for creating a BLE Generic Attribute Profile (GATT) server to broadcast user-defined services and characteristics. This is particularly useful when prototyping and testing servers on different devices with the goal of ensuring that expected behavior matches across all systems.

## Usage

Make sure to initialize first ( You must have required bluetooth permissions to initialize )

```dart
await BlePeripheral.initialize();
```

Add services before starting advertisement

```dart
String serviceBattery = "0000180F-0000-1000-8000-00805F9B34FB";

await BlePeripheral.addService(
  BleService(
    uuid: serviceBattery,
    primary: true,
    characteristics: [
      BleCharacteristic(
        uuid: "00002A19-0000-1000-8000-00805F9B34FB",
        properties: [
          CharacteristicProperties.read.index,
          CharacteristicProperties.notify.index
        ],
        value: null,
        permissions: [
          AttributePermissions.readable.index
        ],
      ),
    ],
  ),
);

// To get list of added services
await BlePeripheral.getServices();

// To remove any specific services
await BlePeripheral.removeService(String serviceId);

// To remove all added services
await BlePeripheral.clearServices();
```

Start advertising, get result in [setAdvertisingStatusUpdateCallback]

```dart
/// set callback for advertising state
BlePeripheral.setAdvertisingStatusUpdateCallback((bool advertising, String? error) {
  print("AdvertisingStatus: $advertising Error $error")
});

// Start advertising
await BlePeripheral.startAdvertising(
  services: [serviceBattery],
  localName: "TestBle",
);
```

Stop advertising

```dart
await BlePeripheral.stopAdvertising();
```

## Ble communication

This callback is common for android and Apple, simply tells us when a central device is available, on Android, we gets a device in `setConnectionStateChangeCallback` when a central device is ready to use, on iOS we gets a device in `setCharacteristicSubscriptionChangeCallback` when a central device is ready to use

```dart
// Called when central subscribes to a characteristic
BlePeripheral.setCharacteristicSubscriptionChangeCallback(CharacteristicSubscriptionChangeCallback callback);

// Android only, Called when central connected/disconnected
BlePeripheral.setConnectionStateChangeCallback(ConnectionStateChangeCallback callback);
```

To update value of subscribed characteristic, on Apple and Android you can pass deviceId as well, to update characteristic for specific device only, else all devices subscribed to this characteristic will be notified

```dart
BlePeripheral.updateCharacteristic(characteristicId: characteristicTest,value: utf8.encode("Test Data"));
```

Other available callback handlers

```dart
// Called when advertisement started, stopped or failed
BlePeripheral.setAdvertisingStatusUpdateCallback(AdvertisementStatusUpdateCallback callback);

// Called when Bluetooth radio on device turned on/off
BlePeripheral.setBleStateChangeCallback(BleStateCallback callback);

// Called when Central device tries to read a characteristics
BlePeripheral.setReadRequestCallback(ReadRequestCallback callback);

// When central tries to write to a characteristic
BlePeripheral.setWriteRequestCallback(WriteRequestCallback callback);

// Called when service added successfully
BlePeripheral.setServiceAddedCallback(ServiceAddedCallback callback);

// Called when mtu changed, on Apple and Windows, this will be called when a device subscribes to a characteristic
BlePeripheral.setMtuChangeCallback(MtuChangeCallback callback);

// Only available on Android, Called when central paired/unpaired
BlePeripheral.setBondStateChangeCallback(BondStateCallback callback);
```

## Setup

### Android

Add required bluetooth permissions in your AndroidManifest.xml file:

```xml
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
```

Ask permissions using [permission_handler](https://pub.dev/packages/permission_handler) plugin

### IOS/Macos

Add permission in info.plist

```
<key>NSBluetoothAlwaysUsageDescription</key>
<string>For advertise as ble peripheral</string>
```

For `MacOS`, make sure to enable bluetooth from Xcode

### Windows

Should work out of box on Windows

## Note

Feel free to contribute or report any bug!

# Ble Peripheral

[![ble_peripheral version](https://img.shields.io/pub/v/ble_peripheral?label=ble_peripheral)](https://pub.dev/packages/ble_peripheral)

Ble peripheral is a Flutter plugin that allows you to use your device as Bluetooth Low Energy (BLE) peripheral

This is an OS-independent plugin for creating a BLE Generic Attribute Profile (GATT) server to broadcast user-defined services and characteristics. This is particularly useful when prototyping and testing servers on different devices with the goal of ensuring that expected behavior matches across all systems.

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

For MacOS, make sure to enable bluetooth from xcode

### Windows

Requires [Nuget](https://www.nuget.org/downloads) for Winrt api's

## Usage

Make sure to initialize first

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
```

Start advertising, get result in [setAdvertingStartedCallback]

```dart
/// set callback for advertising state
BlePeripheral.setAdvertingStartedCallback((String? error) {
  if(error != null){
    print("AdvertisingFailed: $error")
  }else{
    print("AdvertingStarted");
  }
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
// Common for Android/Apple
BlePeripheral.setBleCentralAvailabilityCallback((String deviceId,bool isAvailable) {
  Get.log("OnDeviceAvailabilityChange: $deviceId : $isAvailable");
});

// Android only, Called when central connected
BlePeripheral.setConnectionStateChangeCallback(ConnectionStateChangeCallback callback);

// Apple only, Called when central subscribes to a characteristic
BlePeripheral.setCharacteristicSubscriptionChangeCallback(CharacteristicSubscriptionChangeCallback callback);
```

Other available callback handlers

```dart
// Called when advertisement started/failed
BlePeripheral.setAdvertingStartedCallback(AdvertisementCallback callback);

// Called when Bluetooth radio on device turned on/off
BlePeripheral.setBleStateChangeCallback(BleStateCallback callback);

// Called when Central device tries to read a characteristics
BlePeripheral.setReadRequestCallback(ReadRequestCallback callback);

// When central tries to write to a characteristic
BlePeripheral.setWriteRequestCallback(WriteRequestCallback callback);

// Called when service added successfully
BlePeripheral.setServiceAddedCallback(ServiceAddedCallback callback);

// Only available on Android, Called when mtu changed
BlePeripheral.setMtuChangeCallback(MtuChangeCallback callback);

// Only available on Android, Called when central paired/unpaired
BlePeripheral.setBondStateChangeCallback(BondStateCallback callback);
```

## TODO

Complete windows implementation

## Note

Still under development, api's might change, this is just the initial version, feel free to contribute or report any bug!

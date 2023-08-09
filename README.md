# Ble Peripheral

Ble peripheral is a Flutter plugin that allows you to use your device as Bluetooth Low Energy (BLE) peripheral

This is an OS-independent plugin for creating a BLE Generic Attribute Profile (GATT) server to broadcast user-defined services and characteristics. This is particularly useful when prototyping and testing servers on different devices with the goal of ensuring that expected behavior matches across all systems.

## Setup

### Android

Add the following permissions to your AndroidManifest.xml file:

```xml
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
```

### IOS/Macos

Add permission in info.plist

```plist
<key>NSBluetoothAlwaysUsageDescription</key>
<string>For advertise as ble mouse</string>
```

For macos, also enable bluetooth permission from xcode

### Windows

Requires [Nuget](https://www.nuget.org/downloads) for Winrt api's

## Usage

Make sure to initialize first

```dart
final BlePeripheral blePeripheral = BlePeripheral();
await blePeripheral.initialize();
```

Add services

```dart
List<BleService> services = [];
await blePeripheral.addServices(services);
```

Start advertising

```dart
blePeripheral.startAdvertising(services,"TestDevice");
```

Stop advertising

```dart
blePeripheral.stopAdvertising();
```

## Ble communication

Create a class which extends `BleCallback`

```dart
class PeripheralCallbackHandler extends BleCallback {
  @override
  void onAdvertisingStarted(String? error) {
    print("advertisingStarted: $error");
  }

  @override
  void onBleStateChange(bool state) {
    print("BleState: $state");
  };

  @override
  void onServiceAdded(BleService service, String? error) {
    print("Service added: ${service.uuid.value}");
  }

  @override
  void onWriteRequest(BleCharacteristic characteristic, int offset, Uint8List? value) {
    print("characteristic WriteRequires: ${characteristic.uuid.value}");
  }

  @override
  ReadRequestResult? onReadRequest(BleCharacteristic characteristic, int offset, Uint8List? value) {
    print("characteristic ReadRequest: ${characteristic.uuid.value}");
    // Reply a response to readRequest, return null to respond as failure
    return ReadRequestResult(
      value: Uint8List.fromList([]),
      offset: 0,
    );
  }

 
  @override
  void onCharacteristicSubscriptionChange(BleCentral central, BleCharacteristic characteristic, bool isSubscribed) {
    print("characteristic SubscriptionChange: ${characteristic.uuid.value}");
  }
  

  /// IOS/MacOS only  
  @override
  void onSubscribe(BleCentral bleCentral, BleCharacteristic characteristic){
     /// called on apple, when central subscribe to characteristic
  }
      
  /// IOS/MacOS only 
  @override
  void onUnsubscribe(BleCentral bleCentral, BleCharacteristic characteristic) {
    /// called on apple, when central unSubscribe from characteristic
  }


  /// Android only 
  @override
  void onConnectionStateChange(BleCentral central, bool connected) {
    /// called on android when central successfully connected
  }

  /// Android only 
  @override
  void onBondStateChange(BleCentral central, int bondState) {
    /// called on android when central successfully paired
    print("onBondStateChange: ${central.uuid.value} : ${BondState.fromInt(bondState)}");
  }
}
```

Setup this class to receive updates

```dart
blePeripheral.setBleCallback(PeripheralCallbackHandler());
```

## TODO

Complete windows implementation

## Note

Still under development, api's might change, this is just the initial version, feel free to contribute or report any bug!
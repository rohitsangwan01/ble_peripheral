/// Simple Heartbeat BLE Peripheral Example
///
/// This is a minimal example showing how to:
/// 1. Request Bluetooth permissions
/// 2. Initialize BLE peripheral
/// 3. Add a service with notify characteristic
/// 4. Send periodic heartbeat messages
/// 5. Track connected devices
///
/// Based on Device Simulator heartbeat implementation.

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter_ble_peripheral_slave/flutter_ble_peripheral_slave.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  print("=== Simple BLE Heartbeat Example ===\n");

  final heartbeatDevice = SimpleHeartbeatDevice();

  // Request permissions first
  final hasPermissions = await heartbeatDevice.requestPermissions();
  if (!hasPermissions) {
    print("\n✗ Required Bluetooth permissions not granted!");
    print("Please grant the necessary permissions and try again.");
    return;
  }

  // Initialize and start
  await heartbeatDevice.initialize();
  await heartbeatDevice.startAdvertising();

  print("\nDevice is advertising. Connect with a BLE central device...");
  print("Press Ctrl+C to exit.\n");

  // Keep running
  await Future.delayed(Duration(hours: 1));
}

class SimpleHeartbeatDevice {
  // UUIDs - Replace with your own
  static const String serviceUuid = "0000FF00-0000-1000-8000-00805F9B34FB";
  static const String heartbeatCharUuid =
      "0000FF06-0000-1000-8000-00805F9B34FB";

  // State
  bool isBleOn = false;
  bool isAdvertising = false;
  Set<String> _subscribers = {};
  Timer? _heartbeatTimer;
  int _battery = 100;

  /// Request Bluetooth permissions
  Future<bool> requestPermissions() async {
    print("Requesting Bluetooth permissions...");

    if (Platform.isAndroid) {
      // Android 12+ (API 31+) requires these permissions
      final Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
      ].request();

      // Check if all permissions are granted
      final allGranted = statuses.values.every(
        (status) => status.isGranted,
      );

      if (!allGranted) {
        print("✗ Some Bluetooth permissions were denied:");
        statuses.forEach((permission, status) {
          print("   ${permission.toString()}: ${status.toString()}");
        });
        return false;
      }

      print("✓ All Bluetooth permissions granted");
      return true;
    } else if (Platform.isIOS) {
      // iOS handles permissions automatically when accessing Bluetooth
      // But we can still request them explicitly
      final status = await Permission.bluetooth.request();

      if (!status.isGranted) {
        print("✗ Bluetooth permission denied: $status");
        return false;
      }

      print("✓ Bluetooth permission granted");
      return true;
    }

    // For other platforms, assume permissions are handled
    print("✓ Bluetooth permissions (platform default)");
    return true;
  }

  /// Initialize BLE
  Future<void> initialize() async {
    print("1. Setting up callbacks...");
    _setupCallbacks();

    print("2. Initializing BLE...");
    await BlePeripheral.initialize();

    print("3. Waiting for BLE to power on...");
    await _waitForBle();

    print("4. Adding service...");
    await _addService();

    print("✓ Initialization complete!\n");
  }

  void _setupCallbacks() {
    // Monitor BLE state
    BlePeripheral.setBleStateChangeCallback((isOn) {
      isBleOn = isOn;
      print("   BLE is ${isOn ? 'ON' : 'OFF'}");
    });

    // Monitor advertising
    BlePeripheral.setAdvertisingStatusUpdateCallback((advertising, error) {
      isAdvertising = advertising;
      if (error != null) {
        print("   ✗ Advertising error: $error");
      } else {
        print(
            "   ${advertising ? '✓' : '○'} Advertising ${advertising ? 'started' : 'stopped'}");
      }
    });

    // Handle subscriptions
    BlePeripheral.setCharacteristicSubscriptionChangeCallback((
      deviceId,
      charId,
      isSubscribed,
      name,
    ) {
      final displayName =
          name?.isNotEmpty == true ? name! : deviceId.substring(0, 8);

      if (isSubscribed) {
        _subscribers.add(deviceId);
        print("   ✓ Device connected: $displayName");

        // Start heartbeat when first device subscribes
        if (_heartbeatTimer == null) {
          _startHeartbeat();
        }
      } else {
        _subscribers.remove(deviceId);
        print("   ○ Device disconnected: $displayName");

        // Stop heartbeat when no more subscribers
        if (_subscribers.isEmpty) {
          _heartbeatTimer?.cancel();
          _heartbeatTimer = null;
          print("   Heartbeat stopped (no subscribers)");
        }
      }
    });
  }

  Future<void> _waitForBle() async {
    final start = DateTime.now();
    while (!isBleOn && DateTime.now().difference(start).inSeconds < 5) {
      await Future.delayed(Duration(milliseconds: 100));
    }
  }

  Future<void> _addService() async {
    await BlePeripheral.addService(
      BleService(
        uuid: serviceUuid,
        primary: true,
        characteristics: [
          BleCharacteristic(
            uuid: heartbeatCharUuid,
            properties: [
              CharacteristicProperties.read.index,
              CharacteristicProperties.notify.index,
            ],
            descriptors: [], // System handles CCCD
            value: null,
            permissions: [AttributePermissions.readable.index],
          ),
        ],
      ),
    );
  }

  Future<void> startAdvertising() async {
    if (Platform.isIOS) {
      await BlePeripheral.startAdvertising(
        services: [serviceUuid],
        localName: "HeartbeatDevice",
      );
    } else {
      await BlePeripheral.startAdvertising(
        services: [serviceUuid],
        localName: "HeartbeatDevice",
        manufacturerData: ManufacturerData(
          manufacturerId: 0x012D,
          data: Uint8List.fromList([0x01, 0x02, 0x03]),
        ),
      );
    }
  }

  /// Send heartbeat every 5 seconds
  /// Format: [0xC2, battery%, isMoving, isCharging, timeValid]
  void _startHeartbeat() {
    print("\n   ▶ Starting heartbeat (every 5 seconds)...\n");

    _battery = 100;
    _heartbeatTimer = Timer.periodic(Duration(seconds: 5), (timer) async {
      if (_subscribers.isEmpty) return;

      // Simulate battery drain
      _battery -= 1;
      if (_battery < 0) _battery = 100;

      // Build heartbeat packet
      final heartbeat = Uint8List.fromList([
        0xC2, // Command byte (OUT_HB)
        _battery, // Battery percentage
        0x00, // isMoving (0 = not moving)
        0x01, // isCharging (1 = charging)
        0x01, // timeValid (1 = valid)
      ]);

      // Send to all subscribers
      for (final deviceId in _subscribers) {
        try {
          await BlePeripheral.updateCharacteristic(
            characteristicId: heartbeatCharUuid,
            value: heartbeat,
            deviceId: deviceId,
          );
        } catch (e) {
          print("   ✗ Error sending to device: $e");
        }
      }

      print(
          "   ♥ Heartbeat sent | Battery: $_battery% | Subscribers: ${_subscribers.length}");
    });
  }
}

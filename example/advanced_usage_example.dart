/// Advanced BLE Peripheral Usage Example
///
/// This example demonstrates advanced patterns for using the ble_peripheral package,
/// inspired by the Device Simulator implementation.
///
/// Key Features Demonstrated:
/// - Bluetooth permission handling
/// - Multi-characteristic BLE service setup
/// - Periodic data transmission (heartbeat pattern)
/// - Subscription tracking per device
/// - Handling multiple connected devices
/// - Write request handling with protocol parsing
/// - Proper timer management and cleanup
/// - iOS and Android compatibility patterns

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter_ble_peripheral_slave/flutter_ble_peripheral_slave.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Example BLE device controller demonstrating advanced usage patterns
class ExampleBleDeviceController {
  // BLE state tracking
  bool isAdvertising = false;
  bool isBleOn = false;

  // Connected devices
  Set<String> connectedDevices = {};

  // Device configuration
  final String deviceName = "MyDevice";
  final int manufacturerId = 0x012D; // Your company ID

  // Service and Characteristic UUIDs (use your own)
  static const String serviceUuid = "0000FF00-0000-1000-8000-00805F9B34FB";
  static const String notifyCharUuid = "0000FF01-0000-1000-8000-00805F9B34FB";
  static const String writeCharUuid = "0000FF02-0000-1000-8000-00805F9B34FB";
  static const String heartbeatCharUuid =
      "0000FF03-0000-1000-8000-00805F9B34FB";

  // Timers for periodic operations
  Timer? _heartbeatTimer;
  Timer? _dataTimer;

  // Track subscribers per characteristic
  Set<String> _notifySubscribers = {};
  Set<String> _heartbeatSubscribers = {};

  // Example state data
  int _batteryLevel = 100;
  bool _isMoving = false;
  bool _isCharging = true;

  /// Request Bluetooth permissions
  /// Returns true if all required permissions are granted
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

  /// Initialize the BLE peripheral
  Future<void> initialize() async {
    print("Initializing BLE Peripheral...");

    // Step 1: Setup callbacks BEFORE initialization
    _setupCallbacks();

    // Step 2: Initialize BLE
    try {
      await BlePeripheral.initialize();
      print("✓ BLE Peripheral initialized successfully");
    } catch (e) {
      print("✗ Initialization error: $e");
      rethrow;
    }

    // Step 3: Wait for BLE to be powered on
    await _waitForBleReady();

    // Step 4: Add services
    await _addServices();

    print("✓ Setup complete - ready to advertise");
  }

  /// Setup all BLE callbacks
  void _setupCallbacks() {
    // BLE state changes (on/off)
    BlePeripheral.setBleStateChangeCallback((bool isOn) {
      isBleOn = isOn;
      print("BLE State Changed: ${isOn ? 'ON' : 'OFF'}");
    });

    // Advertising status
    BlePeripheral.setAdvertisingStatusUpdateCallback(
        (bool advertising, String? error) {
      isAdvertising = advertising;
      if (error != null) {
        print("Advertising error: $error");
      } else {
        print("Advertising: ${advertising ? 'Started' : 'Stopped'}");
      }
    });

    // Subscription changes (notify/indicate characteristics)
    BlePeripheral.setCharacteristicSubscriptionChangeCallback((
      String deviceId,
      String characteristicId,
      bool isSubscribed,
      String? deviceName,
    ) {
      print(
          "Subscription Change: Device=$deviceId, Char=$characteristicId, Subscribed=$isSubscribed");

      final displayName =
          deviceName?.isNotEmpty == true ? deviceName! : deviceId;

      if (isSubscribed) {
        // Add device to connected list
        connectedDevices.add(displayName);

        // Track subscribers for specific characteristics
        if (characteristicId.toLowerCase() == notifyCharUuid.toLowerCase()) {
          _notifySubscribers.add(deviceId);
          if (_dataTimer == null) {
            _startDataTransmission();
          }
        }

        if (characteristicId.toLowerCase() == heartbeatCharUuid.toLowerCase()) {
          _heartbeatSubscribers.add(deviceId);
          if (_heartbeatTimer == null) {
            _startHeartbeat();
          }
        }
      } else {
        // Remove device from subscribers
        if (characteristicId.toLowerCase() == notifyCharUuid.toLowerCase()) {
          _notifySubscribers.remove(deviceId);
          if (_notifySubscribers.isEmpty) {
            _dataTimer?.cancel();
            _dataTimer = null;
          }
        }

        if (characteristicId.toLowerCase() == heartbeatCharUuid.toLowerCase()) {
          _heartbeatSubscribers.remove(deviceId);
          if (_heartbeatSubscribers.isEmpty) {
            _heartbeatTimer?.cancel();
            _heartbeatTimer = null;
          }
        }

        // Remove from connected devices if no more subscriptions
        connectedDevices.remove(displayName);
      }
    });

    // Read requests
    BlePeripheral.setReadRequestCallback((
      String deviceId,
      String characteristicId,
      int offset,
      Uint8List? value,
    ) {
      print(
          "Read Request: Device=$deviceId, Char=$characteristicId, Offset=$offset");

      // Return appropriate data based on characteristic
      if (characteristicId.toLowerCase() == notifyCharUuid.toLowerCase()) {
        return ReadRequestResult(value: Uint8List.fromList([0x01, 0x02, 0x03]));
      }

      return ReadRequestResult(value: Uint8List.fromList([0x00]));
    });

    // Write requests
    BlePeripheral.setWriteRequestCallback((
      String deviceId,
      String characteristicId,
      int offset,
      Uint8List? value,
    ) {
      print(
          "Write Request: Device=$deviceId, Char=$characteristicId, Data=$value");

      if (value == null || value.isEmpty) return null;

      // Example: Handle different command protocols
      if (characteristicId.toLowerCase() == writeCharUuid.toLowerCase()) {
        _handleWriteCommand(deviceId, value);
      }

      // Return null for success, or WriteRequestResult with error status
      return null;
    });
  }

  /// Wait for BLE to be ready (powered on)
  Future<void> _waitForBleReady() async {
    final timeout = Duration(seconds: 5);
    final startTime = DateTime.now();

    while (!isBleOn) {
      if (DateTime.now().difference(startTime) > timeout) {
        print("Warning: BLE state timeout - proceeding anyway");
        break;
      }
      await Future.delayed(Duration(milliseconds: 100));
    }

    if (isBleOn) {
      print("✓ BLE is powered on and ready");
    }
  }

  /// Add BLE services and characteristics
  Future<void> _addServices() async {
    try {
      await BlePeripheral.addService(
        BleService(
          uuid: serviceUuid,
          primary: true,
          characteristics: [
            // Notify characteristic - for sending data to clients
            BleCharacteristic(
              uuid: notifyCharUuid,
              properties: [
                CharacteristicProperties.read.index,
                CharacteristicProperties.notify.index,
              ],
              descriptors: [], // System handles CCCD automatically
              value: null,
              permissions: [
                AttributePermissions.readable.index,
              ],
            ),

            // Write characteristic - for receiving commands from clients
            BleCharacteristic(
              uuid: writeCharUuid,
              properties: [
                CharacteristicProperties.write.index,
                CharacteristicProperties.writeWithoutResponse.index,
              ],
              descriptors: [],
              value: null,
              permissions: [
                AttributePermissions.writeable.index,
              ],
            ),

            // Heartbeat characteristic - for periodic status updates
            BleCharacteristic(
              uuid: heartbeatCharUuid,
              properties: [
                CharacteristicProperties.read.index,
                CharacteristicProperties.notify.index,
              ],
              descriptors: [],
              value: null,
              permissions: [
                AttributePermissions.readable.index,
              ],
            ),
          ],
        ),
      );

      print("✓ BLE service added successfully");
    } catch (e) {
      print("✗ Error adding service: $e");
      rethrow;
    }
  }

  /// Start advertising
  Future<void> startAdvertising() async {
    print("Starting advertising...");

    // Platform-specific advertising
    if (Platform.isIOS) {
      // iOS: Manufacturer data not visible, use service UUID and local name
      await BlePeripheral.startAdvertising(
        services: [serviceUuid],
        localName: deviceName,
        addManufacturerDataInScanResponse: false,
      );
    } else {
      // Android: Can include manufacturer data
      await BlePeripheral.startAdvertising(
        services: [serviceUuid],
        localName: deviceName,
        manufacturerData: ManufacturerData(
          manufacturerId: manufacturerId,
          data: Uint8List.fromList([0x01, 0x02, 0x03]),
        ),
        addManufacturerDataInScanResponse: true,
      );
    }
  }

  /// Stop advertising
  Future<void> stopAdvertising() async {
    print("Stopping advertising...");
    await BlePeripheral.stopAdvertising();
  }

  /// Start sending heartbeat messages every 5 seconds
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _batteryLevel = 100;

    print("Starting heartbeat transmission...");

    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_heartbeatSubscribers.isEmpty) return;

      // Simulate battery drain
      _batteryLevel -= 1;
      if (_batteryLevel < 0) _batteryLevel = 100;

      // Build heartbeat packet
      // Format: [CommandByte, BatteryLevel, IsMoving, IsCharging, TimeValid]
      final heartbeat = Uint8List.fromList([
        0xC2, // Command byte
        _batteryLevel, // Battery percentage (0-100, or 0xFF if not available)
        _isMoving ? 0x01 : 0x00, // Movement status
        _isCharging ? 0x01 : 0x00, // Charging status
        0x01, // Time validity (0=invalid, 1=valid)
      ]);

      // Send to all subscribed devices
      for (final deviceId in _heartbeatSubscribers) {
        try {
          await BlePeripheral.updateCharacteristic(
            characteristicId: heartbeatCharUuid,
            value: heartbeat,
            deviceId: deviceId,
          );
          print("Heartbeat sent to $deviceId: Battery=$_batteryLevel%");
        } catch (e) {
          print("Error sending heartbeat to $deviceId: $e");
        }
      }
    });
  }

  /// Start sending periodic data (example: sensor readings)
  void _startDataTransmission() {
    _dataTimer?.cancel();

    print("Starting data transmission...");

    _dataTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_notifySubscribers.isEmpty) return;

      // Example: Send timestamp or sensor data
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final data = Uint8List(8);
      final byteData = ByteData.view(data.buffer);
      byteData.setInt64(0, timestamp, Endian.little);

      // Send to all subscribed devices
      for (final deviceId in _notifySubscribers) {
        try {
          await BlePeripheral.updateCharacteristic(
            characteristicId: notifyCharUuid,
            value: data,
            deviceId: deviceId,
          );
        } catch (e) {
          print("Error sending data to $deviceId: $e");
        }
      }
    });
  }

  /// Handle incoming write commands
  void _handleWriteCommand(String deviceId, Uint8List data) {
    if (data.isEmpty) return;

    final commandByte = data[0];

    switch (commandByte) {
      case 0xA1: // Example: Request device info
        _sendDeviceInfo(deviceId);
        break;

      case 0xA2: // Example: Set configuration
        if (data.length >= 2) {
          final config = data[1];
          print("Configuration set to: 0x${config.toRadixString(16)}");
        }
        break;

      case 0xA3: // Example: Request firmware version
        _sendFirmwareVersion(deviceId);
        break;

      case 0xB1: // Example: Control command
        if (data.length >= 2) {
          _isMoving = data[1] == 0x01;
          print("Movement state changed: $_isMoving");
        }
        break;

      default:
        print("Unknown command: 0x${commandByte.toRadixString(16)}");
    }
  }

  /// Send device information to specific device
  Future<void> _sendDeviceInfo(String deviceId) async {
    // Example device info packet
    final info = Uint8List.fromList([
      0xA1, // Response command byte
      0x01, // Hardware version
      0x02, // Software version
      0x03, // Protocol version
    ]);

    try {
      await BlePeripheral.updateCharacteristic(
        characteristicId: notifyCharUuid,
        value: info,
        deviceId: deviceId,
      );
      print("Device info sent to $deviceId");
    } catch (e) {
      print("Error sending device info: $e");
    }
  }

  /// Send firmware version to specific device
  Future<void> _sendFirmwareVersion(String deviceId) async {
    final version = Uint8List.fromList([
      0xA3, // Response command byte
      0x01, // Major version
      0x02, // Minor version
      0x03, // Patch version
    ]);

    try {
      await BlePeripheral.updateCharacteristic(
        characteristicId: notifyCharUuid,
        value: version,
        deviceId: deviceId,
      );
      print("Firmware version sent to $deviceId");
    } catch (e) {
      print("Error sending firmware version: $e");
    }
  }

  /// Send custom data to all subscribed devices
  Future<void> sendCustomData(String characteristicUuid, List<int> data) async {
    final subscribers =
        characteristicUuid.toLowerCase() == notifyCharUuid.toLowerCase()
            ? _notifySubscribers
            : _heartbeatSubscribers;

    if (subscribers.isEmpty) {
      print("No subscribers for characteristic $characteristicUuid");
      return;
    }

    final uint8Data = Uint8List.fromList(data);

    for (final deviceId in subscribers) {
      try {
        await BlePeripheral.updateCharacteristic(
          characteristicId: characteristicUuid,
          value: uint8Data,
          deviceId: deviceId,
        );
        print("Custom data sent to $deviceId");
      } catch (e) {
        print("Error sending custom data to $deviceId: $e");
      }
    }
  }

  /// Cleanup and dispose resources
  void dispose() {
    print("Disposing BLE controller...");

    // Cancel all timers
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    _dataTimer?.cancel();
    _dataTimer = null;

    // Stop advertising
    stopAdvertising();

    // Clear subscribers
    _notifySubscribers.clear();
    _heartbeatSubscribers.clear();
    connectedDevices.clear();

    print("✓ Cleanup complete");
  }
}

/// Example Flutter app demonstrating usage
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Peripheral Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const BlePeripheralExamplePage(),
    );
  }
}

class BlePeripheralExamplePage extends StatefulWidget {
  const BlePeripheralExamplePage({Key? key}) : super(key: key);

  @override
  State<BlePeripheralExamplePage> createState() =>
      _BlePeripheralExamplePageState();
}

class _BlePeripheralExamplePageState extends State<BlePeripheralExamplePage> {
  final ExampleBleDeviceController _controller = ExampleBleDeviceController();
  bool _isInitialized = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeBle();
  }

  Future<void> _initializeBle() async {
    try {
      // Request permissions first
      final hasPermissions = await _controller.requestPermissions();
      if (!hasPermissions) {
        setState(() {
          _errorMessage =
              "Bluetooth permissions not granted. Please grant permissions in settings.";
        });
        return;
      }

      // Then initialize BLE
      await _controller.initialize();
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      setState(() {
        _errorMessage = "Failed to initialize BLE: $e";
      });
      print("Failed to initialize BLE: $e");
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Peripheral Example'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Show error message if any
            if (_errorMessage != null)
              Card(
                color: Colors.red[100],
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.error, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_errorMessage != null) const SizedBox(height: 16),
            Text(
              'BLE Status',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            _buildStatusCard(),
            const SizedBox(height: 24),
            _buildControlButtons(),
            const SizedBox(height: 24),
            Text(
              'Connected Devices',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            _buildDevicesList(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildStatusRow('Initialized', _isInitialized),
            _buildStatusRow('BLE On', _controller.isBleOn),
            _buildStatusRow('Advertising', _controller.isAdvertising),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, bool value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Icon(
            value ? Icons.check_circle : Icons.cancel,
            color: value ? Colors.green : Colors.grey,
          ),
        ],
      ),
    );
  }

  Widget _buildControlButtons() {
    return Column(
      children: [
        ElevatedButton(
          onPressed: _isInitialized && !_controller.isAdvertising
              ? () async {
                  await _controller.startAdvertising();
                  setState(() {});
                }
              : null,
          child: const Text('Start Advertising'),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: _isInitialized && _controller.isAdvertising
              ? () async {
                  await _controller.stopAdvertising();
                  setState(() {});
                }
              : null,
          child: const Text('Stop Advertising'),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: _isInitialized && _controller.connectedDevices.isNotEmpty
              ? () async {
                  // Send example custom data
                  await _controller.sendCustomData(
                    ExampleBleDeviceController.notifyCharUuid,
                    [0xFF, 0xAA, 0x55, 0x00],
                  );
                }
              : null,
          child: const Text('Send Custom Data'),
        ),
      ],
    );
  }

  Widget _buildDevicesList() {
    if (_controller.connectedDevices.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'No devices connected',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return Card(
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _controller.connectedDevices.length,
        itemBuilder: (context, index) {
          final device = _controller.connectedDevices.elementAt(index);
          return ListTile(
            leading: const Icon(Icons.bluetooth_connected),
            title: Text(device),
          );
        },
      ),
    );
  }
}

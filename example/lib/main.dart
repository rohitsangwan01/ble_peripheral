/// BLE Peripheral Examples Menu
///
/// Choose between:
/// 1. Simple Heartbeat Example - Basic BLE peripheral with heartbeat notifications
/// 2. Advanced Usage Example - Full-featured BLE peripheral with multiple characteristics

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_ble_peripheral_slave/flutter_ble_peripheral_slave.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Peripheral Examples',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const ExampleMenuPage(),
    );
  }
}

/// Main menu page to select which example to run
class ExampleMenuPage extends StatelessWidget {
  const ExampleMenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Peripheral Examples'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.bluetooth,
                size: 60,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Choose an Example',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Simple Example Button
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SimpleHeartbeatExamplePage(),
                    ),
                  );
                },
                icon: const Icon(Icons.favorite, size: 28),
                label: const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Simple Heartbeat',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Basic BLE peripheral with heartbeat',
                        style: TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.all(16),
                ),
              ),

              const SizedBox(height: 12),

              // Advanced Example Button
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AdvancedUsageExamplePage(),
                    ),
                  );
                },
                icon: const Icon(Icons.settings_applications, size: 28),
                label: const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Advanced Usage',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Full-featured with multiple characteristics',
                        style: TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.all(16),
                ),
              ),

              const SizedBox(height: 16),

              // Info card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'These examples demonstrate how to use your device as a BLE peripheral. Connect using nRF Connect or similar BLE scanner apps.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12),
                      ),
                      if (Platform.isMacOS || Platform.isIOS) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8.0),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.orange.shade700,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Note: iOS devices cannot discover peripherals on macOS/iOS due to Apple privacy filters. Use Android for testing.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.orange.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// SIMPLE HEARTBEAT EXAMPLE
// ============================================================================

class SimpleHeartbeatExamplePage extends StatefulWidget {
  const SimpleHeartbeatExamplePage({super.key});

  @override
  State<SimpleHeartbeatExamplePage> createState() =>
      _SimpleHeartbeatExamplePageState();
}

class _SimpleHeartbeatExamplePageState
    extends State<SimpleHeartbeatExamplePage> {
  final heartbeatDevice = SimpleHeartbeatDevice();
  bool isInitialized = false;
  bool isAdvertising = false;
  String statusMessage = 'Not initialized';
  List<String> logs = [];

  @override
  void initState() {
    super.initState();
    _initializeBle();
  }

  void _addLog(String message) {
    setState(() {
      logs.insert(
          0, '${DateTime.now().toString().substring(11, 19)}: $message');
      if (logs.length > 20) logs.removeLast();
    });
  }

  Future<void> _initializeBle() async {
    try {
      // Request permissions first
      _addLog('Requesting Bluetooth permissions...');
      final hasPermissions = await heartbeatDevice.requestPermissions();
      if (!hasPermissions) {
        setState(() {
          statusMessage = 'Bluetooth permissions not granted';
        });
        _addLog('Permissions denied. Please grant permissions in settings.');
        return;
      }
      _addLog('Permissions granted');

      // Then initialize BLE
      await heartbeatDevice.initialize();
      setState(() {
        isInitialized = true;
        statusMessage = 'Initialized successfully';
      });
      _addLog('BLE Peripheral initialized');
    } catch (e) {
      setState(() {
        statusMessage = 'Failed to initialize: $e';
      });
      _addLog('Error: $e');
    }
  }

  Future<void> _startAdvertising() async {
    if (!isInitialized) {
      _addLog('Please initialize first');
      return;
    }

    try {
      await heartbeatDevice.startAdvertising();
      setState(() {
        isAdvertising = true;
        statusMessage = 'Advertising started';
      });
      _addLog('Started advertising');
    } catch (e) {
      _addLog('Failed to start advertising: $e');
    }
  }

  Future<void> _stopAdvertising() async {
    try {
      await BlePeripheral.stopAdvertising();
      setState(() {
        isAdvertising = false;
        statusMessage = 'Advertising stopped';
      });
      _addLog('Stopped advertising');
      heartbeatDevice.cleanup();
    } catch (e) {
      _addLog('Failed to stop advertising: $e');
    }
  }

  @override
  void dispose() {
    heartbeatDevice.cleanup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Simple Heartbeat Example'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Status',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(statusMessage),
                    const SizedBox(height: 8),
                    Text(
                      'Connected Devices: ${heartbeatDevice.connectedDevices.length}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isAdvertising ? null : _startAdvertising,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start Advertising'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isAdvertising ? _stopAdvertising : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop Advertising'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Activity Log',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Card(
                child: logs.isEmpty
                    ? const Center(
                        child: Text('No activity yet'),
                      )
                    : ListView.builder(
                        itemCount: logs.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                              vertical: 4.0,
                            ),
                            child: Text(
                              logs[index],
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Simple heartbeat BLE peripheral device
class SimpleHeartbeatDevice {
  // Service and Characteristic UUIDs
  static const String serviceUuid =
      "0000180D-0000-1000-8000-00805F9B34FB"; // Heart Rate Service
  static const String characteristicUuid =
      "00002A37-0000-1000-8000-00805F9B34FB"; // Heart Rate Measurement

  // Track connected devices and their subscriptions
  final Set<String> connectedDevices = {};
  Timer? heartbeatTimer;
  int heartbeatCounter = 0;

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

  Future<void> initialize() async {
    await BlePeripheral.initialize();

    // Set up callbacks
    BlePeripheral.setBleStateChangeCallback((isOn) {
      print("BLE State Changed: ${isOn ? 'ON' : 'OFF'}");
    });

    BlePeripheral.setAdvertisingStatusUpdateCallback((advertising, error) {
      if (error != null) {
        print("Advertising Error: $error");
      } else {
        print("Advertising: ${advertising ? 'Started' : 'Stopped'}");
      }
    });

    BlePeripheral.setCharacteristicSubscriptionChangeCallback((
      String deviceId,
      String characteristic,
      bool isSubscribed,
      String? deviceName,
    ) {
      print("Device $deviceId (${deviceName ?? 'Unknown'}) "
          "${isSubscribed ? 'subscribed to' : 'unsubscribed from'} "
          "$characteristic");

      if (isSubscribed) {
        connectedDevices.add(deviceId);
        if (heartbeatTimer == null) {
          _startHeartbeat();
        }
      } else {
        connectedDevices.remove(deviceId);
        if (connectedDevices.isEmpty) {
          _stopHeartbeat();
        }
      }
    });
  }

  Future<void> startAdvertising() async {
    // Add the heart rate service
    await BlePeripheral.addService(
      BleService(
        uuid: serviceUuid,
        primary: true,
        characteristics: [
          BleCharacteristic(
            uuid: characteristicUuid,
            properties: [
              CharacteristicProperties.read.index,
              CharacteristicProperties.notify.index,
            ],
            value: null,
            permissions: [AttributePermissions.readable.index],
          ),
        ],
      ),
    );

    // Start advertising
    if (Platform.isAndroid) {
      await BlePeripheral.startAdvertising(
        services: [serviceUuid],
        localName: "HeartRate Monitor",
      );
    } else {
      await BlePeripheral.startAdvertising(
        services: [serviceUuid],
        localName: "HeartRate Monitor",
        manufacturerData: ManufacturerData(
          manufacturerId: 1234,
          data: Uint8List.fromList([0x01, 0x02]),
        ),
      );
    }
  }

  void _startHeartbeat() {
    print("Starting heartbeat timer");
    heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (connectedDevices.isNotEmpty) {
        heartbeatCounter++;
        // Simulate heart rate between 60-100 bpm
        int heartRate = 60 + (heartbeatCounter % 40);

        // Heart Rate Measurement format: flags byte + heart rate value
        Uint8List heartRateData = Uint8List.fromList([
          0x00, // Flags: Heart Rate Value Format is UINT8
          heartRate, // Heart rate value
        ]);

        try {
          await BlePeripheral.updateCharacteristic(
            characteristicId: characteristicUuid,
            value: heartRateData,
            deviceId: null, // null sends to all connected devices
          );
          print(
              "Sent heartbeat $heartbeatCounter: ${heartRate}bpm to ${connectedDevices.length} device(s)");
        } catch (e) {
          print("Error sending heartbeat: $e");
        }
      }
    });
  }

  void _stopHeartbeat() {
    print("Stopping heartbeat timer");
    heartbeatTimer?.cancel();
    heartbeatTimer = null;
    heartbeatCounter = 0;
  }

  void cleanup() {
    _stopHeartbeat();
    connectedDevices.clear();
  }
}

// ============================================================================
// ADVANCED USAGE EXAMPLE
// ============================================================================

class AdvancedUsageExamplePage extends StatefulWidget {
  const AdvancedUsageExamplePage({super.key});

  @override
  State<AdvancedUsageExamplePage> createState() =>
      _AdvancedUsageExamplePageState();
}

class _AdvancedUsageExamplePageState extends State<AdvancedUsageExamplePage> {
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
        title: const Text('Advanced Usage Example'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
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

/// Example BLE device controller demonstrating advanced usage patterns
class ExampleBleDeviceController {
  // BLE state tracking
  bool isAdvertising = false;
  bool isBleOn = false;

  // Connected devices
  Set<String> connectedDevices = {};

  // Device configuration
  final String deviceName = "MyDevice";
  final int manufacturerId = 0x012D;

  // Service and Characteristic UUIDs
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

  /// Initialize the BLE peripheral
  Future<void> initialize() async {
    print("Initializing BLE Peripheral...");
    _setupCallbacks();

    try {
      await BlePeripheral.initialize();
      print("✓ BLE Peripheral initialized successfully");
    } catch (e) {
      print("✗ Initialization error: $e");
      rethrow;
    }

    await _waitForBleReady();
    await _addServices();
    print("✓ Setup complete - ready to advertise");
  }

  /// Setup all BLE callbacks
  void _setupCallbacks() {
    BlePeripheral.setBleStateChangeCallback((bool isOn) {
      isBleOn = isOn;
      print("BLE State Changed: ${isOn ? 'ON' : 'OFF'}");
    });

    BlePeripheral.setAdvertisingStatusUpdateCallback(
        (bool advertising, String? error) {
      isAdvertising = advertising;
      if (error != null) {
        print("Advertising error: $error");
      } else {
        print("Advertising: ${advertising ? 'Started' : 'Stopped'}");
      }
    });

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
        connectedDevices.add(displayName);

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

        connectedDevices.remove(displayName);
      }
    });
  }

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

  Future<void> _addServices() async {
    try {
      await BlePeripheral.addService(
        BleService(
          uuid: serviceUuid,
          primary: true,
          characteristics: [
            BleCharacteristic(
              uuid: notifyCharUuid,
              properties: [
                CharacteristicProperties.read.index,
                CharacteristicProperties.notify.index,
              ],
              descriptors: [],
              value: null,
              permissions: [AttributePermissions.readable.index],
            ),
            BleCharacteristic(
              uuid: writeCharUuid,
              properties: [
                CharacteristicProperties.write.index,
                CharacteristicProperties.writeWithoutResponse.index,
              ],
              descriptors: [],
              value: null,
              permissions: [AttributePermissions.writeable.index],
            ),
            BleCharacteristic(
              uuid: heartbeatCharUuid,
              properties: [
                CharacteristicProperties.read.index,
                CharacteristicProperties.notify.index,
              ],
              descriptors: [],
              value: null,
              permissions: [AttributePermissions.readable.index],
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

  Future<void> startAdvertising() async {
    print("Starting advertising...");

    if (Platform.isIOS) {
      await BlePeripheral.startAdvertising(
        services: [serviceUuid],
        localName: deviceName,
        addManufacturerDataInScanResponse: false,
      );
    } else {
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

  Future<void> stopAdvertising() async {
    print("Stopping advertising...");
    await BlePeripheral.stopAdvertising();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _batteryLevel = 100;
    print("Starting heartbeat transmission...");

    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_heartbeatSubscribers.isEmpty) return;

      _batteryLevel -= 1;
      if (_batteryLevel < 0) _batteryLevel = 100;

      final heartbeat = Uint8List.fromList([
        0xC2,
        _batteryLevel,
        0x00,
        0x01,
        0x01,
      ]);

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

  void _startDataTransmission() {
    _dataTimer?.cancel();
    print("Starting data transmission...");

    _dataTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_notifySubscribers.isEmpty) return;

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final data = Uint8List(8);
      final byteData = ByteData.view(data.buffer);
      byteData.setInt64(0, timestamp, Endian.little);

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

  void dispose() {
    print("Disposing BLE controller...");
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _dataTimer?.cancel();
    _dataTimer = null;
    stopAdvertising();
    _notifySubscribers.clear();
    _heartbeatSubscribers.clear();
    connectedDevices.clear();
    print("✓ Cleanup complete");
  }
}

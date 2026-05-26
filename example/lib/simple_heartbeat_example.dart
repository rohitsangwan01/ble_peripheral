// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables

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

import 'package:flutter/material.dart';
import 'package:flutter_ble_peripheral_slave/flutter_ble_peripheral_slave.dart';
import 'package:permission_handler/permission_handler.dart';

class SimpleHeartbeatExamplePage extends StatefulWidget {
  const SimpleHeartbeatExamplePage({super.key});

  @override
  State<SimpleHeartbeatExamplePage> createState() =>
      _SimpleHeartbeatExamplePageState();
}

class _SimpleHeartbeatExamplePageState
    extends State<SimpleHeartbeatExamplePage> {
  // UUIDs - Replace with your own
  static const String serviceUuid = "0000FF00-0000-1000-8000-00805F9B34FB";
  static const String heartbeatCharUuid =
      "0000FF06-0000-1000-8000-00805F9B34FB";

  // State
  bool isBleOn = false;
  bool isAdvertising = false;
  bool isInitializing = false;
  final Set<String> _subscribers = {};
  Timer? _heartbeatTimer;
  int _battery = 100;

  final List<String> _logs = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _startPeripheral();
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _stopAdvertising();
    super.dispose();
  }

  Future<void> _startPeripheral() async {
    if (isInitializing) return;

    setState(() {
      isInitializing = true;
      _logs.clear();
    });

    _log("Initializing BLE Peripheral...");

    // Request permissions first
    final hasPermissions = await _requestPermissions();
    if (!hasPermissions) {
      _log("✗ Required Bluetooth permissions not granted!");
      setState(() => isInitializing = false);
      return;
    }

    // Setup callbacks
    _setupCallbacks();

    // Initialize BLE
    try {
      await BlePeripheral.initialize();
      _log("✓ BLE Peripheral initialized successfully");

      // Wait for BLE to turn on (with timeout)
      // On Windows, the initial state might take a moment
      int retries = 0;
      while (!isBleOn && retries < 20) {
        await Future.delayed(Duration(milliseconds: 100));
        retries++;
      }

      if (!isBleOn) {
        _log("Warning: BLE state timeout - proceeding anyway");
      }

      // Add service
      await _addService();

      // Start advertising automatically
      await _startAdvertising();
    } catch (e) {
      _log("Failed to initialize BLE: $e");
    } finally {
      if (mounted) {
        setState(() => isInitializing = false);
      }
    }
  }

  Future<bool> _requestPermissions() async {
    _log("Requesting Bluetooth permissions...");

    if (Platform.isAndroid) {
      // Android 12+ (API 31+) requires these permissions
      final Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
      ].request();

      final allGranted = statuses.values.every((status) => status.isGranted);

      if (!allGranted) {
        _log("✗ Some Bluetooth permissions were denied");
        return false;
      }
      _log("✓ All Bluetooth permissions granted");
      return true;
    } else {
      // iOS/Windows/MacOS/Linux
      final status = await Permission.bluetooth.request();
      if (status.isPermanentlyDenied) {
        _log("✗ Bluetooth permission permanently denied");
        return false;
      }
      _log("✓ Bluetooth permissions (platform default)");
      return true;
    }
  }

  void _setupCallbacks() {
    BlePeripheral.setBleStateChangeCallback((isOn) {
      if (mounted) {
        setState(() => isBleOn = isOn);
        _log("BLE State Changed: ${isOn ? 'ON' : 'OFF'}");
      }
    });

    BlePeripheral.setAdvertisingStatusUpdateCallback((advertising, error) {
      if (mounted) {
        setState(() => isAdvertising = advertising);
        if (error != null) {
          _log("✗ Advertising error: $error");
        } else {
          _log("Advertising State: ${advertising ? 'Started' : 'Stopped'}");
        }
      }
    });

    BlePeripheral.setCharacteristicSubscriptionChangeCallback(
        (deviceId, charId, isSubscribed, name) {
      final displayName =
          name?.isNotEmpty == true ? name! : deviceId.substring(0, 8);

      if (mounted) {
        setState(() {
          if (isSubscribed) {
            _subscribers.add(deviceId);
            _log("New subscriber: $displayName");
            if (_heartbeatTimer == null) _startHeartbeat();
          } else {
            _subscribers.remove(deviceId);
            _log("Subscriber disconnected: $displayName");
            if (_subscribers.isEmpty) {
              _heartbeatTimer?.cancel();
              _heartbeatTimer = null;
              _log("Heartbeat stopped");
            }
          }
        });
      }
    });

    BlePeripheral.setServiceAddedCallback((serviceId, error) {
      if (error != null) {
        _log("✗ Error adding service: $error");
      } else {
        _log("✓ Service added: $serviceId");
      }
    });
  }

  Future<void> _addService() async {
    try {
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
              descriptors: [],
              value: null,
              permissions: [AttributePermissions.readable.index],
            ),
          ],
        ),
      );
    } catch (e) {
      _log("Error calling addService: $e");
    }
  }

  Future<void> _startAdvertising() async {
    try {
      await BlePeripheral.startAdvertising(
        services: [serviceUuid],
        localName: "Flutter Heartbeat",
      );
    } catch (e) {
      _log("Error starting advertising: $e");
    }
  }

  Future<void> _stopAdvertising() async {
    try {
      await BlePeripheral.stopAdvertising();
    } catch (e) {
      _log("Error stopping advertising: $e");
    }
  }

  void _startHeartbeat() {
    _log("Starting heartbeat notifications...");
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_subscribers.isEmpty) {
        timer.cancel();
        return;
      }

      // Simulate battery drain/charge
      _battery = (_battery - 1) % 100;
      if (_battery < 0) _battery = 100;

      final data = Uint8List.fromList([_battery]);

      BlePeripheral.updateCharacteristic(
        characteristicId: heartbeatCharUuid,
        value: data,
      ).catchError((e) {
        _log("Failed to send heartbeat: $e");
      });
    });
  }

  void _log(String message) {
    print(message);
    if (mounted) {
      setState(() {
        _logs.add("${DateTime.now().hour}:${DateTime.now().minute}: $message");
      });
      Future.delayed(Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Simple Heartbeat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: isInitializing ? null : _startPeripheral,
            tooltip: 'Restart Peripheral',
          ),
        ],
      ),
      body: Column(
        children: [
          // Status Card
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('BLE Status:',
                          style: Theme.of(context).textTheme.titleMedium),
                      Chip(
                        label: Text(isBleOn ? 'ON' : 'OFF'),
                        backgroundColor:
                            isBleOn ? Colors.green[100] : Colors.red[100],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Advertising:',
                          style: Theme.of(context).textTheme.titleMedium),
                      Switch(
                        value: isAdvertising,
                        onChanged: isBleOn
                            ? (val) =>
                                val ? _startAdvertising() : _stopAdvertising()
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Subscribers:',
                          style: Theme.of(context).textTheme.titleMedium),
                      Text('${_subscribers.length}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18)),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Logs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.terminal, size: 20),
                const SizedBox(width: 8),
                Text('Logs', style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  return Text(
                    _logs[index],
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontFamily: 'Courier',
                      fontSize: 12,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

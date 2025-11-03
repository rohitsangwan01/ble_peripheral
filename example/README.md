# BLE Peripheral Examples

This directory contains example code demonstrating advanced usage patterns of the `flutter_ble_peripheral_slave` package.

## ⚠️ Important: iOS/macOS Discovery Limitation

**Known Issue**: iOS devices cannot discover BLE peripherals advertised by macOS or other iOS devices. This is an Apple platform limitation, not a bug in this package.

### Why This Happens

- **Apple Privacy Filters**: iOS automatically filters out BLE advertisements from other Apple devices to reduce interference from Continuity features (Handoff, AirDrop, Universal Clipboard, etc.)
- **CoreBluetooth Restriction**: This is a deliberate CoreBluetooth framework limitation for privacy and performance
- **Android Works Fine**: Android devices don't have these Apple-specific filters and can discover macOS/iOS peripherals normally

### Testing Recommendations

✅ **For Development/Testing:**

- Use an **Android device** to test peripherals running on macOS/iOS
- Use **nRF Connect** (Android) or similar BLE scanner apps
- Test iOS peripheral → Android central (works)
- Test macOS peripheral → Android central (works)
- Test Android peripheral → iOS central (works)

❌ **Won't Work:**

- iOS device → macOS peripheral
- iOS device → iOS peripheral
- macOS → macOS peripheral (in most cases)

✅ **For Production:**

- Deploy your peripheral on **non-Apple hardware** (Raspberry Pi, ESP32, Android, etc.)
- iOS/macOS central apps can then discover and connect to these peripherals normally

## Examples

### 1. Simple Heartbeat Example (`simple_heartbeat_example.dart`)

A minimal, focused example perfect for getting started quickly.

**What it demonstrates:**

- Basic BLE peripheral initialization
- Adding a notify characteristic
- Sending periodic heartbeat messages every 5 seconds
- Tracking connected devices
- Clean subscription management

**Heartbeat Format:**

```
Byte 0: 0xC2 (Command - OUT_HB)
Byte 1: Battery percentage (0-100, or 0xFF if not available)
Byte 2: isMoving (0 = stationary, 1 = moving)
Byte 3: isCharging (0 = not charging, 1 = charging)
Byte 4: timeValid (0 = invalid, 1 = valid)
```

**Run it:**

```dart
dart simple_heartbeat_example.dart
```

### 2. Advanced Usage Example (`advanced_usage_example.dart`)

A comprehensive example showing production-ready patterns.

**What it demonstrates:**

- Multiple characteristics (notify, write, heartbeat)
- Per-device subscription tracking
- Command protocol handling
- Multiple periodic timers
- Request/response patterns
- Platform-specific considerations (iOS vs Android)
- Proper cleanup and resource management
- Full Flutter UI integration

**Key Patterns:**

#### Multi-Device Subscription Tracking

```dart
Set<String> _notifySubscribers = {};
Set<String> _heartbeatSubscribers = {};

// Track which devices are subscribed to which characteristics
if (characteristicId == notifyCharUuid) {
  _notifySubscribers.add(deviceId);
}
```

#### Targeted vs Broadcast Messages

```dart
// Send to specific device
await BlePeripheral.updateCharacteristic(
  characteristicId: uuid,
  value: data,
  deviceId: specificDeviceId,
);

// Broadcast to all subscribers
for (final deviceId in _subscribers) {
  await BlePeripheral.updateCharacteristic(
    characteristicId: uuid,
    value: data,
    deviceId: deviceId,
  );
}
```

#### Command Protocol Handling

```dart
void _handleWriteCommand(String deviceId, Uint8List data) {
  final commandByte = data[0];

  switch (commandByte) {
    case 0xA1:
      _sendDeviceInfo(deviceId);
      break;
    case 0xA2:
      _handleConfig(data[1]);
      break;
    // ... more commands
  }
}
```

#### Timer Management

```dart
// Start timer only when needed
if (_subscribers.isEmpty) return;
if (_timer == null) {
  _timer = Timer.periodic(duration, callback);
}

// Stop timer when not needed
if (_subscribers.isEmpty) {
  _timer?.cancel();
  _timer = null;
}
```

## Common Patterns from Device Simulator

### 1. Initialization Flow

```dart
// Always follow this order:
1. Setup callbacks BEFORE initialization
2. Initialize BLE
3. Wait for BLE to power on
4. Add services
5. Start advertising
```

### 2. iOS vs Android Considerations

**iOS:**

- Manufacturer data is NOT visible to scanners
- Use full 128-bit UUIDs for better compatibility
- Local name is primary identification method
- Don't manually add CCCD descriptors

**Android:**

- Manufacturer data works fine
- Can use 16-bit or 128-bit UUIDs
- More flexible advertising options

```dart
if (Platform.isIOS) {
  await BlePeripheral.startAdvertising(
    services: [uuid],
    localName: deviceName,
    // No manufacturer data
  );
} else {
  await BlePeripheral.startAdvertising(
    services: [uuid],
    localName: deviceName,
    manufacturerData: manufacturerData,
  );
}
```

### 3. Characteristic Configuration

For notify characteristics, let the system handle CCCD:

```dart
BleCharacteristic(
  uuid: uuid,
  properties: [
    CharacteristicProperties.read.index,
    CharacteristicProperties.notify.index,
  ],
  descriptors: [], // Empty - system adds CCCD automatically
  permissions: [AttributePermissions.readable.index],
)
```

### 4. Proper Cleanup

Always clean up resources:

```dart
void dispose() {
  _timer1?.cancel();
  _timer2?.cancel();
  _subscribers.clear();
  stopAdvertising();
}
```

## Testing

### Using nRF Connect (Recommended)

1. Install nRF Connect app (iOS/Android)
2. Run your example
3. Scan for "HeartbeatDevice" or your device name
4. Connect and enable notifications
5. Observe periodic heartbeat data

### Using Command Line (Linux only)

```bash
# Scan for devices
bluetoothctl scan on

# Connect
bluetoothctl connect <MAC_ADDRESS>
```

## Protocol Design Tips

### Binary Protocol

Use structured byte arrays for efficiency:

```dart
final packet = Uint8List.fromList([
  commandByte,
  param1,
  param2,
  // ...
]);
```

### Command/Response Pattern

- Byte 0: Command/Response identifier
- Remaining bytes: Command-specific data
- Use same command byte for response (request 0xA1 → response 0xA1)

### Error Handling

```dart
try {
  await BlePeripheral.updateCharacteristic(...);
} catch (e) {
  // Device might have disconnected
  // Consider removing from subscriber list
}
```

## Performance Considerations

1. **Timer Frequency**: Don't send data too frequently

   - Heartbeat: 5 seconds (conservative)
   - Sensor data: 1 second (moderate)
   - High-frequency: 100ms (only if needed)

2. **Data Size**: Keep packets small

   - MTU is typically 20-512 bytes
   - Smaller packets = better reliability

3. **Subscriber Checks**: Always check if subscribers exist
   ```dart
   if (_subscribers.isEmpty) return;
   ```

## Common Issues

### "Invalid Parameters" Error (iOS)

- **Cause**: Manually adding CCCD descriptor
- **Solution**: Use empty `descriptors: []` list

### Advertising Not Visible (iOS)

- **Cause**: Using manufacturer data on iOS
- **Solution**: Remove manufacturer data on iOS, rely on service UUID

### Data Not Sending

- **Cause**: No subscribers or characteristic not configured for notify
- **Solution**: Check subscription callback and characteristic properties

### Timer Keeps Running After Disconnect

- **Cause**: Not checking subscriber count
- **Solution**: Check if subscribers list is empty

## Additional Resources

- [BLE Peripheral Package Documentation](../README.md)
- [Bluetooth SIG Specifications](https://www.bluetooth.com/specifications/)
- [nRF Connect App](https://www.nordicsemi.com/Products/Development-tools/nrf-connect-for-mobile)

## License

These examples are provided as-is for educational purposes.

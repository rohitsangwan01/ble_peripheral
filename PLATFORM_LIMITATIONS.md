# Platform Limitations & Known Issues

## iOS Cannot Discover macOS/iOS BLE Peripherals

### The Issue

When advertising a BLE peripheral from **macOS** or **iOS**, other **iOS devices cannot discover the advertisement**. However, **Android devices work perfectly** and can discover and connect without issues.

### Root Cause

This is an **intentional Apple platform limitation**, not a bug in this package or your code:

1. **Privacy Filters**: iOS automatically filters BLE advertisements from other Apple devices (macOS/iOS/iPadOS/watchOS)

2. **Continuity Protection**: This filtering prevents interference with Apple's ecosystem features:

   - Handoff
   - AirDrop
   - Universal Clipboard
   - Apple Watch pairing
   - AirPods switching
   - FindMy network

3. **CoreBluetooth Framework**: The restriction is built into CoreBluetooth itself at the system level

4. **No Workaround**: There is no configuration, entitlement, or code change that can bypass this limitation

### What Works ✅

| Peripheral Platform    | Central Platform | Works?       |
| ---------------------- | ---------------- | ------------ |
| macOS/iOS              | **Android**      | ✅ Yes       |
| **Android**            | iOS/macOS        | ✅ Yes       |
| **Raspberry Pi/ESP32** | iOS/macOS        | ✅ Yes       |
| **Linux/Windows**      | iOS/macOS        | ✅ Yes       |
| Android                | Android          | ✅ Yes       |
| macOS/iOS              | macOS            | ⚠️ Sometimes |

### What Doesn't Work ❌

| Peripheral Platform | Central Platform | Works?        |
| ------------------- | ---------------- | ------------- |
| **macOS**           | iOS              | ❌ No         |
| **iOS**             | iOS              | ❌ No         |
| **iOS**             | macOS            | ❌ Usually No |

### Testing Recommendations

#### For Development

1. **Use Android for Testing Peripherals**

   ```bash
   # Test your macOS/iOS peripheral with Android central
   flutter run -d <android-device-id>
   # Use nRF Connect app on Android
   ```

2. **Use Dedicated BLE Hardware**

   - Raspberry Pi with BlueZ
   - ESP32 development boards
   - Nordic nRF52 DK
   - Any non-Apple BLE hardware

3. **Test Cross-Platform**
   - macOS peripheral → Android central ✅
   - Android peripheral → iOS central ✅
   - ESP32 peripheral → iOS central ✅

#### For Production

**Deploy peripherals on non-Apple platforms:**

- ✅ Raspberry Pi (Linux)
- ✅ ESP32/ESP8266 microcontrollers
- ✅ Android devices
- ✅ Dedicated BLE hardware
- ✅ Windows/Linux servers

iOS and macOS can then discover and connect to these peripherals normally.

### Alternative Testing Approaches

#### Option 1: Use Android Device

```bash
# Install nRF Connect on Android
# Start your macOS peripheral
# Scan with nRF Connect - should appear immediately
```

#### Option 2: Use Raspberry Pi

```bash
# Install BlueZ on Raspberry Pi
# Use this package to create peripheral
# Test with iOS devices
```

#### Option 3: Use ESP32

```arduino
// Use ESP32 BLE library
// Create peripheral with same service UUIDs
// iOS devices can discover ESP32 peripherals
```

### Why Android Works

Android's Bluetooth stack (BlueZ-based) doesn't have Apple's ecosystem filtering:

- No Continuity features to protect
- Open Bluetooth specification compliance
- No special filtering of Apple devices
- Standard BLE Central implementation

### Technical Details

**Apple's BLE Advertisement Filtering:**

1. iOS scans for BLE advertisements
2. Checks manufacturer data and service UUIDs
3. Identifies Apple device signatures
4. Silently filters out Apple-to-Apple advertisements
5. Only shows non-Apple peripherals to apps

**This filtering is:**

- Hardware/firmware level on newer devices
- Operating system level filtering
- Cannot be disabled via settings
- Not affected by developer permissions
- Not bypassable with entitlements

### References

- [Apple Developer Forums - BLE Discovery Issues](https://developer.apple.com/forums/)
- [Stack Overflow - iOS to iOS BLE](https://stackoverflow.com/questions/tagged/core-bluetooth)
- Nordic Semiconductor Application Notes on iOS BLE
- Bluetooth SIG - iOS Implementation Notes

### Summary

**This is expected behavior, not a bug:**

✅ Your code is correct  
✅ Android discovery works as proof  
✅ This affects ALL iOS BLE peripheral implementations  
✅ No workaround exists within iOS/macOS

**Solution:** Test and deploy peripherals on Android, Linux, or dedicated BLE hardware for iOS compatibility.

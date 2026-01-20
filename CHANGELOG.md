## 2.4.8

- Fixed Windows silent crash by adding try-catch blocks around characteristic subscription logic

## 2.4.7

- Fixed Windows build configuration error (CMake target name mismatch)
- Improved Bluetooth radio initialization on Windows to correctly select active adapter
- Updated Windows plugin structure to match Flutter plugin requirements

## 2.4.6

- Added Bluetooth permission handling in all examples using `permission_handler` package
- Added `requestPermissions()` method to example implementations for Android 12+ and iOS
- Updated example app with proper permission flow before BLE initialization
- Added user-friendly error messages when permissions are denied
- Updated simple heartbeat example with permission requests
- Updated advanced usage example with permission requests
- Added permission dependency to example pubspec.yaml

## 2.4.5

- Fixed dartdoc ambiguous reexport warnings by hiding internal Pigeon utilities
- Improved pub.dev scoring compliance

## 2.4.4

- Fixed documentation generation issues
- Improved package metadata for pub.dev

## 2.4.3

- Fixed podspec file naming to match package name (`flutter_ble_peripheral_slave.podspec`)
- Updated podspec metadata with correct version and repository information
- Added complete Flutter example app with Material Design UI
- Fixed iOS/Android project structure for example app
- Updated all package imports and references

## 2.4.2

- Forked and republished as `flutter_ble_peripheral_slave`
- Repository moved to https://github.com/FaroukBoussarsar/ble_peripheral

## 2.4.0

- BreakingChange: `onCharacteristicSubscriptionChange` also send `String? name`
- Fix Windows crash on getting read requests
- Bump Pigeon Version

## 2.3.3

- Update Gradle to 8.3 [#20](https://github.com/rohitsangwan01/ble_peripheral/pull/20)

## 2.3.2

- Fix local device name issue on Android [#12](https://github.com/rohitsangwan01/ble_peripheral/pull/12)

## 2.3.1

- Fix android crash on state changes before initialization

## 2.3.0

- Breaking Change: Removed setBleCentralAvailabilityCallback ( because all platforms supports characteristics subscription change now )
- Add setCharacteristicSubscriptionChangeCallback support on Android
- localName is optional in StartAdvertisement method now
- Add setInstance for testing or Mock implementation
- Add BlePeripheralInterface for setting your own implementation
- Remove Linux dependency to fix crash on linux

## 2.2.3

- Fix windows crash on stopping advertisement sometimes
- Add windows capability to write static characteristic and descriptor value
- Fix windows crash sometimes on clearing services
- Improve windows advertising status

## 2.2.2

- Fix windows crash if readResponse was null

## 2.2.1

- Fix windows crash if no manufacturer data was provided

## 2.2.0

- Add windows support

## 2.1.0

- Add `notifyEncryptionRequired` and `indicateEncryptionRequired` in CharacteristicProperties
- Fix `isAdvertising` result on Android
- Add `removeService`, `clearServices`, `getServices`
- BreakingChange: `onBondStateChange` will return `BondState` enum instead of integer
- BreakingChange: `setAdvertingStartedCallback` changed to `setAdvertisingStatusUpdateCallback`

## 2.0.0

- Fix onReadRequest handler on android
- BreakingChange: added deviceId in onReadRequest and onWriteRequest callbacks

## 1.0.0

- Refactored Apis
- Fix android permission issues
- Update callback handlers issue
- Add onMtuChange callback
- Fix AddServices
- Update Readme
- Some more bug fixes

## 0.0.1

- Initial version

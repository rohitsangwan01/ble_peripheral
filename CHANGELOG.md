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

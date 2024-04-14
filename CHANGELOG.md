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

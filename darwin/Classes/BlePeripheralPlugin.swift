#if os(iOS)
    import Flutter
#elseif os(macOS)
    import Cocoa
    import FlutterMacOS
#endif
import CoreBluetooth
import Foundation

public class BlePeripheralPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        var messenger: FlutterBinaryMessenger? = nil
        #if os(iOS)
            messenger = registrar.messenger()
        #elseif os(macOS)
            messenger = registrar.messenger
        #endif
        let bleCallback = BleCallback(binaryMessenger: messenger!)
        let api = BlePeripheralDarwin(bleCallback: bleCallback)
        BlePeripheralChannelSetup.setUp(binaryMessenger: messenger!, api: api)
    }
}

private class BlePeripheralDarwin: NSObject, BlePeripheralChannel, CBPeripheralManagerDelegate {
    var bleCallback: BleCallback
    lazy var peripheralManager: CBPeripheralManager = .init(delegate: self, queue: nil, options: nil)
    var cbCentrals = [CBCentral]()

    init(bleCallback: BleCallback) {
        self.bleCallback = bleCallback
        super.init()
    }

    func initialize() throws {
        print("Initialize called")
        print("isAdvertising \(peripheralManager.isAdvertising)")
    }

    func isSupported() throws -> Bool {
        print("isSupportedCalled")
        // TODO: implement this
        return true
    }

    func isAdvertising() throws -> Bool? {
        return peripheralManager.isAdvertising
    }

    func askBlePermission() throws -> Bool {
        #if os(iOS)
            if #available(iOS 13.1, *) { return CBPeripheralManager.authorization == .allowedAlways }
            if #available(iOS 13.0, *) { return CBPeripheralManager.authorizationStatus() == .authorized }
            return true
        #elseif os(macOS)
            //  Handle for macos
            return true
        #endif
    }

    func addService(service: BleService) throws {
        peripheralManager.add(service.toCBService())
    }

    func startAdvertising(services: [String], localName: String, timeout _: Int64?, manufacturerData: ManufacturerData?, addManufacturerDataInScanResponse _: Bool) throws {
        let cbServices = services.map { uuidString in
            CBUUID(string: uuidString)
        }

        var advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: cbServices,
            CBAdvertisementDataLocalNameKey: localName,
        ]
//        if let manufacturerData = manufacturerData {
//            var manufData = Data()
//            manufData.append(contentsOf: withUnsafeBytes(of: manufacturerData.manufacturerId) { Data($0) })
//            manufData.append(manufacturerData.data.data)
//            advertisementData[CBAdvertisementDataManufacturerDataKey] = manufData
//        }
        print("AdvertisementData: \(advertisementData)")
        peripheralManager.startAdvertising(advertisementData)
    }

    func stopAdvertising() throws {
        peripheralManager.stopAdvertising()
    }

    func updateCentralList(central: CBCentral) {
        let containsDevice = cbCentrals.contains { $0.identifier == central.identifier }
        if !containsDevice { cbCentrals.append(central) }
    }

    func updateCharacteristic(devoiceID: String, characteristicId: String, value: FlutterStandardTypedData) throws {
        let centralDevice: CBCentral? = cbCentrals.first(where: { device in
            devoiceID == device.identifier.uuidString
        })
        let char: CBMutableCharacteristic? = characteristicId.findCharacteristic()
        if centralDevice == nil {
            throw CustomError.notFound("\(devoiceID) device not found")
        } else if char == nil {
            throw CustomError.notFound("\(devoiceID) characteristic not found")
        } else {
            peripheralManager.updateValue(value.toData(), for: char!, onSubscribedCentrals: [centralDevice!])
        }
    }

    internal func updateChar(_ inputReport: [Int8], _ characteristic: CBMutableCharacteristic, device: CBCentral) {
        let data = Data(bytes: inputReport, count: inputReport.count)
        peripheralManager.updateValue(data, for: characteristic, onSubscribedCentrals: [device])
    }

    /// Swift callbacks
    internal nonisolated func peripheralManagerDidStartAdvertising(_: CBPeripheralManager, error: Error?) {
        bleCallback.onAdvertisingStarted(error: error?.localizedDescription, completion: { _ in })
    }

    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        print("BluetoothState: \(peripheral.state)")
        bleCallback.onBleStateChange(state: peripheral.state == .poweredOn, completion: { _ in })
    }

    internal nonisolated func peripheralManager(_: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        bleCallback.onServiceAdded(serviceId: service.uuid.uuidString, error: error?.localizedDescription, completion: { _ in })
    }

    internal nonisolated func peripheralManager(_: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        updateCentralList(central: central)
        bleCallback.onCharacteristicSubscriptionChange(deviceId: central.identifier.uuidString, characteristicId: characteristic.uuid.uuidString, isSubscribed: true) { _ in }
    }

    internal nonisolated func peripheralManager(_: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        bleCallback.onCharacteristicSubscriptionChange(deviceId: central.identifier.uuidString, characteristicId: characteristic.uuid.uuidString, isSubscribed: false) { _ in }
    }

    internal nonisolated func peripheralManager(_: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        bleCallback.onReadRequest(
            deviceId: request.central.identifier.uuidString,
            characteristicId: request.characteristic.uuid.uuidString,
            offset: Int64(request.offset),
            value: request.value?.toFlutterBytes()
        ) { readReq in
            do {
                let result = try readReq.get()
                let data = result?.value.toData()
                if data == nil {
                    self.peripheralManager.respond(to: request, withResult: .requestNotSupported)
                } else {
                    request.value = data
                    self.peripheralManager.respond(to: request, withResult: .success)
                }
            } catch {
                self.peripheralManager.respond(to: request, withResult: .requestNotSupported)
            }
        }
    }

    internal nonisolated func peripheralManager(_: CBPeripheralManager, didReceiveWrite request: [CBATTRequest]) {
        request.forEach { req in
            bleCallback.onWriteRequest(
                deviceId: req.central.identifier.uuidString,
                characteristicId: req.characteristic.uuid.uuidString,
                offset: Int64(req.offset),
                value: req.value?.toFlutterBytes()
            ) { writeResult in
                do {
                    let response = try writeResult.get()
                    let status = response?.status?.toCBATTErrorCode() ?? .success
                    self.peripheralManager.respond(to: req, withResult: status)
                } catch {
                    self.peripheralManager.respond(to: req, withResult: .requestNotSupported)
                }
            }
        }
    }
}

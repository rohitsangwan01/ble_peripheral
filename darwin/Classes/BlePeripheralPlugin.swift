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
    var subscribedCentrals = [CBCentral: [CBCharacteristic]]()
    private var charUpdateQueue: [CharacteristicUpdate] = []
    private var isCharUpdateProcessing = false

    init(bleCallback: BleCallback) {
        self.bleCallback = bleCallback
        super.init()
    }

    func initialize() throws {
        // To trigger the peripheralManagerDidUpdateState callback
        let _ = peripheralManager.isAdvertising
    }

    func isSupported() throws -> Bool {
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

    func removeService(serviceId: String) throws {
        if let service = serviceId.findService() {
            peripheralManager.remove(service)
            servicesList.removeAll { $0.uuid.uuidString.lowercased() == service.uuid.uuidString.lowercased() }
        }
    }

    func clearServices() throws {
        peripheralManager.removeAllServices()
        servicesList.removeAll()
    }

    func getServices() throws -> [String] {
        return servicesList.map { service in
            service.uuid.uuidString
        }
    }

    func getSubscribedClients() throws -> [SubscribedClient] {
        var result = [SubscribedClient]()
        for (central, characteristics) in subscribedCentrals {
            result.append(SubscribedClient(deviceId: central.identifier.uuidString, subscribedCharacteristics: characteristics.map { $0.uuid.uuidString }))
        }
        return result
    }

    func startAdvertising(services: [String], localName: String?, timeout _: Int64?, manufacturerData _: ManufacturerData?, addManufacturerDataInScanResponse _: Bool) throws {
        let cbServices = services.map { uuidString in
            CBUUID(string: uuidString)
        }
        var advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: cbServices,
        ]
        if localName != nil {
            advertisementData[CBAdvertisementDataLocalNameKey] = localName
        }
        // if let manufacturerData = manufacturerData {
        //     var manufData = Data()
        //     manufData.append(contentsOf: withUnsafeBytes(of: manufacturerData.manufacturerId) { Data($0) })
        //     manufData.append(manufacturerData.data.data)
        //     advertisementData[CBAdvertisementDataManufacturerDataKey] = manufData
        // }
        // print("AdvertisementData: \(advertisementData)")
        peripheralManager.startAdvertising(advertisementData)
    }

    func stopAdvertising() throws {
        peripheralManager.stopAdvertising()
        bleCallback.onAdvertisingStatusUpdate(advertising: false, error: nil, completion: { _ in })
    }

    func updateCharacteristic(characteristicId: String, value: FlutterStandardTypedData, deviceId: String?) throws {
        guard let char: CBMutableCharacteristic = characteristicId.findCharacteristic() else {
            throw PigeonError(code: "NotFound", message: "\(characteristicId) characteristic not found", details: nil)
        }

        let central: CBCentral? = deviceId.flatMap { id in
            subscribedCentrals.keys.first { $0.identifier.uuidString == id }
        }

        if deviceId != nil && central == nil {
            throw PigeonError(code: "NotFound", message: "\(deviceId!) device not found", details: nil)
        }

        charUpdateQueue.append(CharacteristicUpdate(characteristic: char, data: value.toData(), central: central))
        processCharUpdateQueue()
    }

    private func processCharUpdateQueue() {
        guard !isCharUpdateProcessing, !charUpdateQueue.isEmpty else { return }
        isCharUpdateProcessing = true
        while !charUpdateQueue.isEmpty {
            let charUpdate = charUpdateQueue[0]
            let success = peripheralManager.updateValue(
                charUpdate.data,
                for: charUpdate.characteristic,
                onSubscribedCentrals: charUpdate.central.map { [$0] }
            )
            if success {
                charUpdateQueue.removeFirst()
            } else {
                // print("Failed to update characteristic value for \(charUpdate.characteristic.uuid).")
                // If `updateValue` fails, stop processing and wait for `peripheralManagerIsReady`
                break
            }
        }
        isCharUpdateProcessing = false
    }

    func peripheralManagerIsReady(toUpdateSubscribers _: CBPeripheralManager) {
        // print("Ready to update char")
        processCharUpdateQueue()
    }

    /// Swift callbacks
    internal nonisolated func peripheralManagerDidStartAdvertising(_: CBPeripheralManager, error: Error?) {
        bleCallback.onAdvertisingStatusUpdate(advertising: error == nil, error: error?.localizedDescription, completion: { _ in })
    }

    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        // print("BluetoothState: \(peripheral.state)")
        bleCallback.onBleStateChange(state: peripheral.state == .poweredOn, completion: { _ in })
    }

    internal nonisolated func peripheralManager(_: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        bleCallback.onServiceAdded(serviceId: service.uuid.uuidString, error: error?.localizedDescription, completion: { _ in })
    }

    internal nonisolated func peripheralManager(_: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        if subscribedCentrals[central] == nil {
            subscribedCentrals[central] = [characteristic]
        } else if subscribedCentrals[central]?.contains(characteristic) != true {
            subscribedCentrals[central]?.append(characteristic)
        }

        bleCallback.onCharacteristicSubscriptionChange(
            deviceId: central.identifier.uuidString,
            characteristicId: characteristic.uuid.uuidString,
            isSubscribed: true, name: nil
        ) { _ in }
        // Update MTU for this device
        bleCallback.onMtuChange(deviceId: central.identifier.uuidString, mtu: Int64(central.maximumUpdateValueLength)) { _ in }
    }

    internal nonisolated func peripheralManager(_: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        if let index = subscribedCentrals[central]?.firstIndex(of: characteristic) {
            subscribedCentrals[central]?.remove(at: index)
        }
        // if no more characteristics are subscribed by this central, remove it from the list
        if subscribedCentrals[central]?.isEmpty == true {
            subscribedCentrals.removeValue(forKey: central)
        }

        bleCallback.onCharacteristicSubscriptionChange(
            deviceId: central.identifier.uuidString,
            characteristicId: characteristic.uuid.uuidString,
            isSubscribed: false, name: nil
        ) { _ in }
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

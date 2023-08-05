import Flutter
import UIKit
import CoreBluetooth

public class BlePeripheralPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
      let bleCallback: BleCallback = BleCallback(binaryMessenger: registrar.messenger())
    let api = PigeonApiImplementation(bleCallback: bleCallback)
    BlePeripheralChannelSetup.setUp(binaryMessenger: registrar.messenger(), api: api)
  }
}

private class PigeonApiImplementation: NSObject, BlePeripheralChannel, CBPeripheralManagerDelegate {
    var  bleCallback: BleCallback
    lazy var peripheralManager: CBPeripheralManager  = CBPeripheralManager(delegate: self, queue: nil, options: nil)
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
        let isSupported = true
        if #available(iOS 13.0, *) {
            let status: CBManagerAuthorization =  peripheralManager.authorization
            print("BleAuthStatus: \(status.rawValue)")
        }
        return isSupported
    }
    
    func isAdvertising() throws -> Bool {
        return peripheralManager.isAdvertising
    }
    
    func addServices(services: [BleService]) throws {
        services.forEach { service in
            self.peripheralManager.add(service.toCBService())
        }
    }
    
    func startAdvertising(services: [UUID], localName: String) throws {
        let cbServices = services.map { uuidString in
            CBUUID(string: uuidString.value)
        }
        self.peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: cbServices,
            CBAdvertisementDataLocalNameKey: localName
        ])
    }
    
    func stopAdvertising() throws {
        self.peripheralManager.stopAdvertising()
    }
    
    func updateCentralList(central: CBCentral){
        let containsDevice = cbCentrals.contains { $0.identifier == central.identifier }
        if(!containsDevice){ cbCentrals.append(central) }
    }
    
  
    func updateCharacteristic(central: BleCentral, characteristic: BleCharacteristic,value: FlutterStandardTypedData) throws {
        let centralDevice: CBCentral? = cbCentrals.first(where: { device in
            central.uuid.value == device.identifier.uuidString
        })
        let char: CBMutableCharacteristic? = characteristic.find()
        if(centralDevice == nil ){
            throw CustomError.notFound("\(central.uuid.value) device not found")
        }else if(char == nil){
            throw CustomError.notFound("\(characteristic.uuid.value) characteristic not found")
        } else{
            peripheralManager.updateValue(value.toData(), for: char!, onSubscribedCentrals: [centralDevice!])
        }
    }

    
    internal func updateChar(_ inputReport: [Int8],_ characteristic: CBMutableCharacteristic, device: CBCentral) {
        let data = Data(bytes: inputReport, count: inputReport.count)
        peripheralManager.updateValue(data, for: characteristic, onSubscribedCentrals: [device])
    }
    
    /// Swift callbacks
    nonisolated internal func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        bleCallback.onAdvertisingStarted(error: error?.localizedDescription, completion: {})
    }
    
    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        bleCallback.onBleStateChange(state: peripheral.state == .poweredOn, completion: {})
    }
    
    nonisolated internal func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        bleCallback.onServiceAdded(service: service.toBleService(), error: error?.localizedDescription, completion: {})
    }
    
    
    nonisolated internal func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        updateCentralList(central: central)
        bleCallback.onSubscribe(bleCentral: central.toBleCenral(),characteristic: characteristic.toBleCharacteristic()) {}
    }
    
    nonisolated  internal  func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        bleCallback.onUnsubscribe(bleCentral: central.toBleCenral(),characteristic: characteristic.toBleCharacteristic()) {}
    }
    
    nonisolated internal func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        bleCallback.onReadRequest(
            characteristic: request.characteristic.toBleCharacteristic(),
            offset: Int64(request.offset),
            value: request.value?.toFlutterBytes()
        ) { readReq in
            let data = readReq?.value.toData()
            if(data == nil){
                self.peripheralManager.respond(to: request, withResult: .requestNotSupported)
            }else{
                request.value = data!
                self.peripheralManager.respond(to: request, withResult: .success)
            }
           
        }
    }
    
    nonisolated  internal func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite request: [CBATTRequest]) {
        request.forEach { req in
            bleCallback.onWriteRequest(
                characteristic: req.characteristic.toBleCharacteristic(),
                offset: Int64(req.offset),
                value: req.value?.toFlutterBytes()){}
        }
    }
}


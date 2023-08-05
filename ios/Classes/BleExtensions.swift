//
//  BleExtensions.swift
//  ble_peripheral
//
//  Created by Rohit Sangwan on 29/07/23.
//

import Foundation
import CoreBluetooth
import Flutter


enum CustomError: Error {
    case notFound(String)
}

/// local list of characteristic
var characteristicsList = [CBMutableCharacteristic]()


extension CBService{
    func toBleService() -> BleService{
        return BleService(
            uuid: self.uuid.toUUID(),
            primary: self.isPrimary,
            characteristics: self.characteristics?.map({ char in
            char.toBleCharacteristic()
        }) ?? [] )
    }
}

extension BleService{
    func toCBService() -> CBMutableService{
        let service =  CBMutableService(
            type: CBUUID(string: self.uuid.value),
            primary: self.primary
        )
        let chars = self.characteristics.compactMap { bleChar in
            return bleChar?.toCBChar()
        }
        if(!chars.isEmpty){
            service.characteristics = chars
        }
        return service
    }
}

extension BleDescriptor{
    func toCBMutableDescriptor() -> CBMutableDescriptor{
        return CBMutableDescriptor(type:CBUUID(string: self.uuid.value), value: self.value?.toData())
    }
}

extension CBCharacteristic {
    func toBleCharacteristic() -> BleCharacteristic{
        return BleCharacteristic(
            uuid: self.uuid.toUUID(),
            properties: [Int64(self.properties.rawValue)],
            permissions: [],
            descriptors: nil,
            value: self.value?.toFlutterBytes()
        )
    }
}

extension BleCharacteristic {
    func toCBChar() -> CBMutableCharacteristic{
        let properties : [CBCharacteristicProperties] = self.properties.compactMap { int64 in
            return int64?.toCBCharacteristicProperties()
        }
        let permissions : [CBAttributePermissions] = self.permissions.compactMap { int64 in
            return int64?.toCBAttributePermissions()
        }
        
        let combinedProperties = properties.reduce(CBCharacteristicProperties()) { $0.union($1) }
        let combinedPermissions = permissions.reduce(CBAttributePermissions()) { $0.union($1) }
        
        let char =  CBMutableCharacteristic(
            type: CBUUID(string: self.uuid.value),
            properties: combinedProperties,
            value: self.value?.toData(),
            permissions: combinedPermissions
        )
        char.descriptors = self.descriptors?.compactMap({ desc in
            return desc?.toCBMutableDescriptor()
        })
        // Add local refrence of this characteristic
        let containsChar = characteristicsList.contains { $0.uuid.uuidString == char.uuid.uuidString }
        if(!containsChar){ characteristicsList.append(char) }
        return char
    }
    
    func find() -> CBMutableCharacteristic?{
        return characteristicsList.first { ch in
            ch.uuid.uuidString == self.uuid.value
        }
    }
}

extension Int64{
    
    func toCBCharacteristicProperties() -> CBCharacteristicProperties? {
        switch(self){
          case 0:
            return CBCharacteristicProperties.broadcast
        case 1:
          return CBCharacteristicProperties.read
        case 2:
          return CBCharacteristicProperties.writeWithoutResponse
        case 3:
          return CBCharacteristicProperties.write
        case 4:
          return CBCharacteristicProperties.notify
        case 5:
          return CBCharacteristicProperties.indicate
        default:
            return  nil
        }
    }
    
    
    func toCBAttributePermissions() -> CBAttributePermissions? {
        switch(self){
            case 0:
                return CBAttributePermissions.readable
            case 1:
              return CBAttributePermissions.writeable
            case 2:
              return CBAttributePermissions.readEncryptionRequired
            case 3:
              return CBAttributePermissions.writeEncryptionRequired
              default:
                return  nil
        }
    }
}


extension CBCentral{
    func toBleCenral() -> BleCentral{
        return BleCentral(uuid: UUID(value: self.identifier.uuidString))
    }
}

extension CBUUID{
    func toUUID() -> UUID{
        return UUID(value: self.uuidString)
    }
}

extension FlutterStandardTypedData{
    func toData() -> Data{
        return Data(self.data)
    }
}

extension Data{
    func toInt64() -> [Int64] {
        return self.map { Int64(Int($0)) }
    }
    
    func toFlutterBytes() -> FlutterStandardTypedData{
        return FlutterStandardTypedData(bytes: self)
    }
}



extension [Int64?]{
    func toData() -> Data{
        let finalArray = self.compactMap { data in
            return data
        }
        return Data(bytes: finalArray, count: finalArray.count)
    }
}

//
//  BleExtensions.swift
//  ble_peripheral
//
//  Created by Rohit Sangwan on 29/07/23.
//

#if os(iOS)
    import Flutter
#elseif os(macOS)
    import FlutterMacOS
#else
    #error("Unsupported platform.")
#endif
import CoreBluetooth
import Foundation

enum CustomError: Error {
    case notFound(String)
}

/// local list of characteristic
var characteristicsList = [CBMutableCharacteristic]()
var servicesList = [CBMutableService]()

extension BleService {
    func toCBService() -> CBMutableService {
        let service = CBMutableService(
            type: CBUUID(string: uuid),
            primary: primary
        )
        let chars = characteristics.compactMap { bleChar in
            bleChar.toCBChar()
        }
        if !chars.isEmpty {
            service.characteristics = chars
        }
        // Add local reference of this service
        servicesList.removeAll { $0.uuid.uuidString.lowercased() == service.uuid.uuidString.lowercased() }
        servicesList.append(service)
        return service
    }
}

extension BleDescriptor {
    func toCBMutableDescriptor() -> CBMutableDescriptor {
        return CBMutableDescriptor(
            type: CBUUID(string: uuid),
            value: value?.toData()
        )
    }
}

extension BleCharacteristic {
    func toCBChar() -> CBMutableCharacteristic {
        let properties: [CBCharacteristicProperties] = self.properties.compactMap { int64 in
            int64.toCBCharacteristicProperties()
        }
        let permissions: [CBAttributePermissions] = self.permissions.compactMap { int64 in
            int64.toCBAttributePermissions()
        }

        let combinedProperties = properties.reduce(CBCharacteristicProperties()) { $0.union($1) }
        let combinedPermissions = permissions.reduce(CBAttributePermissions()) { $0.union($1) }

        let char = CBMutableCharacteristic(
            type: CBUUID(string: uuid),
            properties: combinedProperties,
            value: value?.toData(),
            permissions: combinedPermissions
        )
        char.descriptors = descriptors?.compactMap { desc in
            desc.toCBMutableDescriptor()
        }
        // Add local reference of this characteristic
        characteristicsList.removeAll { $0.uuid.uuidString.lowercased() == char.uuid.uuidString.lowercased() }
        characteristicsList.append(char)
        return char
    }
}

extension String {
    func findCharacteristic() -> CBMutableCharacteristic? {
        return characteristicsList.first { ch in
            ch.uuid.uuidString.lowercased() == self.lowercased()
        }
    }

    func findService() -> CBMutableService? {
        return servicesList.first { ch in
            ch.uuid.uuidString.lowercased() == self.lowercased()
        }
    }
}

extension Int64 {
    func toCBCharacteristicProperties() -> CBCharacteristicProperties? {
        switch self {
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
        case 6:
            return CBCharacteristicProperties.authenticatedSignedWrites
        case 7:
            return CBCharacteristicProperties.extendedProperties
        case 8:
            return CBCharacteristicProperties.notifyEncryptionRequired
        case 9:
            return CBCharacteristicProperties.indicateEncryptionRequired
        default:
            return nil
        }
    }

    func toCBAttributePermissions() -> CBAttributePermissions? {
        switch self {
        case 0:
            return CBAttributePermissions.readable
        case 1:
            return CBAttributePermissions.writeable
        case 2:
            return CBAttributePermissions.readEncryptionRequired
        case 3:
            return CBAttributePermissions.writeEncryptionRequired
        default:
            return nil
        }
    }

    func toCBATTErrorCode() -> CBATTError.Code {
        switch self {
        case 0:
            return CBATTError.success
        case 1:
            return CBATTError.invalidHandle
        case 2:
            return CBATTError.readNotPermitted
        case 3:
            return CBATTError.writeNotPermitted
        case 4:
            return CBATTError.invalidPdu
        case 5:
            return CBATTError.insufficientAuthentication
        case 6:
            return CBATTError.requestNotSupported
        case 7:
            return CBATTError.invalidOffset
        case 8:
            return CBATTError.insufficientAuthorization
        case 9:
            return CBATTError.prepareQueueFull
        case 10:
            return CBATTError.attributeNotFound
        case 11:
            return CBATTError.attributeNotLong
        case 12:
            return CBATTError.insufficientEncryptionKeySize
        case 13:
            return CBATTError.invalidAttributeValueLength
        case 14:
            return CBATTError.unlikelyError
        case 15:
            return CBATTError.insufficientEncryption
        case 16:
            return CBATTError.unsupportedGroupType
        case 17:
            return CBATTError.insufficientResources
        default:
            return CBATTError.success
        }
    }
}

extension FlutterStandardTypedData {
    func toData() -> Data {
        return Data(data)
    }
}

extension Data {
    func toInt64() -> [Int64] {
        return map { Int64(Int($0)) }
    }

    func toFlutterBytes() -> FlutterStandardTypedData {
        return FlutterStandardTypedData(bytes: self)
    }
}

extension [Int64?] {
    func toData() -> Data {
        let finalArray = self.compactMap { data in
            data
        }
        return Data(bytes: finalArray, count: finalArray.count)
    }
}

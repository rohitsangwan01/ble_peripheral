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

extension CBService {
    func toBleService() -> BleService {
        return BleService(
            uuid: uuid.toUUID(),
            primary: isPrimary,
            characteristics: characteristics?.map { char in
                char.toBleCharacteristic()
            } ?? []
        )
    }
}

extension BleService {
    func toCBService() -> CBMutableService {
        let service = CBMutableService(
            type: CBUUID(string: uuid.value),
            primary: primary
        )
        let chars = characteristics.compactMap { bleChar in
            bleChar?.toCBChar()
        }
        if !chars.isEmpty {
            service.characteristics = chars
        }
        return service
    }
}

extension BleDescriptor {
    func toCBMutableDescriptor() -> CBMutableDescriptor {
        return CBMutableDescriptor(type: CBUUID(string: uuid.value), value: value?.toData())
    }
}

extension CBCharacteristic {
    func toBleCharacteristic() -> BleCharacteristic {
        return BleCharacteristic(
            uuid: uuid.toUUID(),
            properties: [Int64(properties.rawValue)],
            permissions: [],
            descriptors: nil,
            value: value?.toFlutterBytes()
        )
    }
}

extension BleCharacteristic {
    func toCBChar() -> CBMutableCharacteristic {
        let properties: [CBCharacteristicProperties] = self.properties.compactMap { int64 in
            int64?.toCBCharacteristicProperties()
        }
        let permissions: [CBAttributePermissions] = self.permissions.compactMap { int64 in
            int64?.toCBAttributePermissions()
        }

        let combinedProperties = properties.reduce(CBCharacteristicProperties()) { $0.union($1) }
        let combinedPermissions = permissions.reduce(CBAttributePermissions()) { $0.union($1) }

        let char = CBMutableCharacteristic(
            type: CBUUID(string: uuid.value),
            properties: combinedProperties,
            value: value?.toData(),
            permissions: combinedPermissions
        )
        char.descriptors = descriptors?.compactMap { desc in
            desc?.toCBMutableDescriptor()
        }
        // Add local refrence of this characteristic
        let containsChar = characteristicsList.contains { $0.uuid.uuidString == char.uuid.uuidString }
        if !containsChar { characteristicsList.append(char) }
        return char
    }

    func find() -> CBMutableCharacteristic? {
        return characteristicsList.first { ch in
            ch.uuid.uuidString == self.uuid.value
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
}

extension CBCentral {
    func toBleCenral() -> BleCentral {
        return BleCentral(uuid: UUID(value: identifier.uuidString))
    }
}

extension CBUUID {
    func toUUID() -> UUID {
        return UUID(value: uuidString)
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

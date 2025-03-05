package com.rohit.ble_peripheral

import android.app.Activity
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattService
import android.content.pm.PackageManager
import android.util.Log
import java.lang.Exception
import java.util.Collections
import java.util.UUID

private val bluetoothGattCharacteristics: MutableMap<String, BluetoothGattCharacteristic> =
    HashMap()
private val descriptorValueReadMap: MutableMap<String, ByteArray> =
    HashMap()
const val descriptorCCUUID = "00002902-0000-1000-8000-00805f9b34fb"


fun Activity.havePermission(permissions: Array<String>): Boolean {
    var allPermissionProvided = true
    for (perm in permissions) {
        val checkVal = checkCallingOrSelfPermission(perm)
        if (checkVal != PackageManager.PERMISSION_GRANTED) {
            allPermissionProvided = false
            break;
        }
    }
    return allPermissionProvided
}


/// From Flutter -> Native
fun BleService.toGattService(): BluetoothGattService {
    val service = BluetoothGattService(
        UUID.fromString(uuid),
        if (primary) BluetoothGattService.SERVICE_TYPE_PRIMARY else BluetoothGattService.SERVICE_TYPE_SECONDARY
    )
    characteristics.forEach {
        it.toGattCharacteristic().let { characteristic ->
            service.addCharacteristic(characteristic)
        }
    }
    return service
}

fun BleCharacteristic.toGattCharacteristic(): BluetoothGattCharacteristic {
    val char = BluetoothGattCharacteristic(
        UUID.fromString(uuid),
        properties.toPropertiesList(),
        permissions.toPermissionsList()
    )
    value?.let {
        char.value = it
    }
    descriptors?.forEach {
        it.toGattDescriptor().let { descriptor ->
            char.addDescriptor(descriptor)
        }
    }

    addCCDescriptorIfRequired(this, char)

    if (bluetoothGattCharacteristics[uuid] == null) {
        bluetoothGattCharacteristics[uuid] = char
    }
    return char
}

fun addCCDescriptorIfRequired(
    bleCharacteristic: BleCharacteristic,
    char: BluetoothGattCharacteristic,
) {
    val haveNotifyOrIndicateProperty =
        char.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0 ||
                char.properties and BluetoothGattCharacteristic.PROPERTY_INDICATE != 0
    if (!haveNotifyOrIndicateProperty) return

    var cccdDescriptorAlreadyAdded = false
    for (descriptor in bleCharacteristic.descriptors ?: Collections.emptyList()) {
        if (descriptor.uuid.lowercase() == descriptorCCUUID.lowercase()) {
            cccdDescriptorAlreadyAdded = true
            break
        }
    }

    if (cccdDescriptorAlreadyAdded) return

    val cccdDescriptor = BluetoothGattDescriptor(
        UUID.fromString(descriptorCCUUID),
        BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE
    )
    cccdDescriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
    char.addDescriptor(cccdDescriptor)
    Log.d("BlePeripheral", "Added CCCD for ${char.uuid}")
}

fun BluetoothGattDescriptor.getCacheValue(): ByteArray? {
    return descriptorValueReadMap[uuid.toString().lowercase()]
}

fun ByteArray.toIntArray(): List<Int> {
    val data: MutableList<Int> = mutableListOf()
    for (i in this.indices) {
        data.add(this[i].toInt())
    }
    return data
}

fun BleDescriptor.toGattDescriptor(): BluetoothGattDescriptor {
    val defaultPermission =
        BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE
    val permission = permissions?.toPermissionsList() ?: defaultPermission
    val descriptor = BluetoothGattDescriptor(
        UUID.fromString(uuid),
        permission
    )
    value?.let {
        descriptor.value = it
        descriptorValueReadMap[uuid.lowercase()] = it
    }
    return descriptor
}

fun String.findCharacteristic(): BluetoothGattCharacteristic? {
    return bluetoothGattCharacteristics[this]
}

fun String.findService(): BluetoothGattService? {
    for (char in bluetoothGattCharacteristics.values) {
        if (char.service?.uuid.toString() == this) {
            return char.service
        }
    }
    return null
}

fun List<CharacteristicProperties>.toPropertiesList(): Int {
    return this.map { it }.fold(0) { acc, i -> acc or i.toProperties() }.toInt()
}

fun List<AttributePermissions>.toPermissionsList(): Int {
    return this.map { it }.fold(0) { acc, i -> acc or i.toPermission() }.toInt()
}

fun CharacteristicProperties.toProperties(): Int {
    return when (this) {
        CharacteristicProperties.BROADCAST -> BluetoothGattCharacteristic.PROPERTY_BROADCAST
        CharacteristicProperties.READ -> BluetoothGattCharacteristic.PROPERTY_READ
        CharacteristicProperties.WRITE_WITHOUT_RESPONSE -> BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE
        CharacteristicProperties.WRITE -> BluetoothGattCharacteristic.PROPERTY_WRITE
        CharacteristicProperties.NOTIFY -> BluetoothGattCharacteristic.PROPERTY_NOTIFY
        CharacteristicProperties.INDICATE -> BluetoothGattCharacteristic.PROPERTY_INDICATE
        CharacteristicProperties.AUTHENTICATED_SIGNED_WRITES -> BluetoothGattCharacteristic.PROPERTY_SIGNED_WRITE
        CharacteristicProperties.EXTENDED_PROPERTIES -> BluetoothGattCharacteristic.PROPERTY_EXTENDED_PROPS
        CharacteristicProperties.NOTIFY_ENCRYPTION_REQUIRED -> BluetoothGattCharacteristic.PROPERTY_NOTIFY //  NotifyEncryptionRequired
        CharacteristicProperties.INDICATE_ENCRYPTION_REQUIRED -> BluetoothGattCharacteristic.PROPERTY_INDICATE //   IndicateEncryptionRequired
    }
}

fun AttributePermissions.toPermission(): Int {
    return when (this) {
        AttributePermissions.READABLE -> BluetoothGattCharacteristic.PERMISSION_READ
        AttributePermissions.WRITEABLE -> BluetoothGattCharacteristic.PERMISSION_WRITE
        AttributePermissions.READ_ENCRYPTION_REQUIRED -> BluetoothGattCharacteristic.PERMISSION_READ_ENCRYPTED
        AttributePermissions.WRITE_ENCRYPTION_REQUIRED -> BluetoothGattCharacteristic.PERMISSION_WRITE_ENCRYPTED
    }
}

fun Int.toBondState(): BondState {
    return when (this) {
        BluetoothDevice.BOND_BONDING -> BondState.BONDING
        BluetoothDevice.BOND_BONDED -> BondState.BONDED
        BluetoothDevice.BOND_NONE -> BondState.NONE
        else -> BondState.NONE
    }
}
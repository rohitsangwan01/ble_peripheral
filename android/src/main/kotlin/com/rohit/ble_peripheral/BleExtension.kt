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
val subscribedCharDevicesMap: MutableMap<String, MutableList<String>> = HashMap()
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
        it?.toGattCharacteristic()?.let { characteristic ->
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
        it?.toGattDescriptor()?.let { descriptor ->
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
    var haveNotifyOrIndicateProperty =
        char.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0 ||
                char.properties and BluetoothGattCharacteristic.PROPERTY_INDICATE != 0
    if (!haveNotifyOrIndicateProperty) return

    var cccdDescriptorAlreadyAdded = false
    for (descriptor in bleCharacteristic.descriptors ?: Collections.emptyList()) {
        if (descriptor?.uuid?.lowercase() == descriptorCCUUID.lowercase()) {
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

fun List<Long?>.toPropertiesList(): Int {
    return this.toValidList().fold(0) { acc, i -> acc or i.toProperties() }.toInt()
}

fun List<Long?>.toPermissionsList(): Int {
    return this.toValidList().fold(0) { acc, i -> acc or i.toPermission() }.toInt()
}

fun List<Long?>.toValidList(): List<Int> {
    val data: MutableList<Int> = mutableListOf()
    val totalSize = this.size - 1
    for (i in 0..totalSize) {
        val value: Int? = this[i] as Int?
        value?.let { data.add(it) }
    }
    return data
}

fun Int.toProperties(): Int {
    return when (this) {
        0 -> BluetoothGattCharacteristic.PROPERTY_BROADCAST
        1 -> BluetoothGattCharacteristic.PROPERTY_READ
        2 -> BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE
        3 -> BluetoothGattCharacteristic.PROPERTY_WRITE
        4 -> BluetoothGattCharacteristic.PROPERTY_NOTIFY
        5 -> BluetoothGattCharacteristic.PROPERTY_INDICATE
        6 -> BluetoothGattCharacteristic.PROPERTY_SIGNED_WRITE
        7 -> BluetoothGattCharacteristic.PROPERTY_EXTENDED_PROPS
        8 -> BluetoothGattCharacteristic.PROPERTY_NOTIFY //  NotifyEncryptionRequired
        9 -> BluetoothGattCharacteristic.PROPERTY_INDICATE //   IndicateEncryptionRequired
        else -> 0
    }
}

fun Int.toPermission(): Int {
    return when (this) {
        0 -> BluetoothGattCharacteristic.PERMISSION_READ
        1 -> BluetoothGattCharacteristic.PERMISSION_WRITE
        2 -> BluetoothGattCharacteristic.PERMISSION_READ_ENCRYPTED
        3 -> BluetoothGattCharacteristic.PERMISSION_WRITE_ENCRYPTED
        else -> 0
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
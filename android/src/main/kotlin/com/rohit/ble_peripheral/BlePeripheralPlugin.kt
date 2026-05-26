package com.rohit.ble_peripheral

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.ParcelUuid
import android.util.Log
import androidx.core.app.ActivityCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import java.util.Collections
import android.content.Context.RECEIVER_EXPORTED

private const val TAG = "BlePeripheralPlugin"

@SuppressLint("MissingPermission")
class BlePeripheralPlugin : FlutterPlugin, BlePeripheralChannel, ActivityAware {
    // PluginRegistry.ActivityResultListener {
    private val requestCodeBluetoothPermission = 0xa1c
    private var bleCallback: BleCallback? = null
    private val requestCodeBluetoothEnablePermission = 0xb1e
    private var applicationContext: Context? = null
    private var activity: Activity? = null
    private var bluetoothManager: BluetoothManager? = null
    private var handler: Handler? = null
    private var bluetoothLeAdvertiser: BluetoothLeAdvertiser? = null
    private var gattServer: BluetoothGattServer? = null
    private val bluetoothDevicesMap: MutableMap<String, BluetoothDevice> = HashMap()
    private val emptyBytes = byteArrayOf()
    private val listOfDevicesWaitingForBond = mutableListOf<String>()
    private var isAdvertising: Boolean? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        BlePeripheralChannel.setUp(flutterPluginBinding.binaryMessenger, this)
        bleCallback = BleCallback(flutterPluginBinding.binaryMessenger)
        applicationContext = flutterPluginBinding.applicationContext
    }

    override fun initialize() {
        // if (!validatePermission()) throw Exception("Bluetooth Permission not granted")
        if (applicationContext == null) {
            throw Exception("Application context is null")
        }
        applicationContext?.let {
            handler = Handler(it.mainLooper)
            bluetoothManager =
                it.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
            val bluetoothAdapter = bluetoothManager?.adapter
                ?: throw UnsupportedOperationException("Bluetooth is not available.")
            bluetoothLeAdvertiser = bluetoothAdapter.bluetoothLeAdvertiser
            if (bluetoothLeAdvertiser == null) throw UnsupportedOperationException("Bluetooth LE Advertising not supported on this device.")
            gattServer = bluetoothManager?.openGattServer(it, gattServerCallback)
            if (gattServer == null) throw UnsupportedOperationException("gattServer is null, check Bluetooth is ON.")
            bleCallback?.onBleStateChange(isBluetoothEnabled()) {}
        }
    }


    override fun isAdvertising(): Boolean? {
        return isAdvertising
    }

    override fun isSupported(): Boolean {
        val bluetoothAdapter = bluetoothManager?.adapter ?: return false
        // if (!bluetoothAdapter.isEnabled) throw UnsupportedOperationException("Bluetooth is disabled.")
        if (!bluetoothAdapter.isMultipleAdvertisementSupported) throw UnsupportedOperationException(
            "Bluetooth LE Advertising not supported on this device."
        )
        return true
    }

    override fun addService(service: BleService) {
        gattServer?.addService(service.toGattService())
    }

    override fun removeService(serviceId: String) {
        serviceId.findService()?.let {
            gattServer?.removeService(it)
        }
    }

    override fun clearServices() {
        gattServer?.clearServices()
    }

    override fun getServices(): List<String> {
        return gattServer?.services?.map {
            it.uuid.toString()
        } ?: emptyList()
    }

    override fun startAdvertising(
        services: List<String>,
        localName: String?,
        timeout: Long?,
        manufacturerData: ManufacturerData?,
        addManufacturerDataInScanResponse: Boolean,
    ) {
        if (!isBluetoothEnabled()) {
            enableBluetooth()
            throw Exception("Bluetooth is not enabled")
        }

        handler?.post { // set up advertising setting
            localName?.let { bluetoothManager?.adapter?.name = it }
            val advertiseSettings = AdvertiseSettings.Builder()
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                .setConnectable(true)
                .setTimeout(timeout?.toInt() ?: 0)
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .build()

            val advertiseDataBuilder = AdvertiseData.Builder()
                .setIncludeTxPowerLevel(false)
                .setIncludeDeviceName(localName != null)

            val scanResponseBuilder = AdvertiseData.Builder()
                .setIncludeTxPowerLevel(false)
                .setIncludeDeviceName(localName != null)

            manufacturerData?.let {
                if (addManufacturerDataInScanResponse) {
                    scanResponseBuilder.addManufacturerData(
                        it.manufacturerId.toInt(),
                        it.data
                    )
                } else {
                    advertiseDataBuilder.addManufacturerData(
                        it.manufacturerId.toInt(),
                        it.data
                    )
                }
            }

            services.forEach {
                advertiseDataBuilder.addServiceUuid(ParcelUuid.fromString(it))
            }

            bluetoothLeAdvertiser?.startAdvertising(
                advertiseSettings,
                advertiseDataBuilder.build(),
                scanResponseBuilder.build(),
                advertiseCallback
            )
        }
    }

    override fun stopAdvertising() {
        handler?.post {
            try {
                bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback)
                isAdvertising = false
                bleCallback?.onAdvertisingStatusUpdate(false, null) {}
            } catch (ignored: IllegalStateException) {
                throw Exception("Bluetooth Adapter is not turned ON")
            }
        }
    }

    override fun updateCharacteristic(
        characteristicId: String,
        value: ByteArray,
        deviceId: String?,
    ) {
        val char =
            characteristicId.findCharacteristic() ?: throw Exception("Characteristic not found")
        char.value = value

        val MAX_NOTIFICATION_RETRIES = 3
        val RETRY_DELAY_MILLIS = 1000L

        if (deviceId != null) {
            val device = bluetoothDevicesMap[deviceId] ?: throw Exception("Device not found")
            handler?.post {
                // Attempt to send notification with retries
                var success = false
                var retries = 0

                while (!success && retries < MAX_NOTIFICATION_RETRIES) {
                    val res = gattServer?.notifyCharacteristicChanged(
                        device,
                        char,
                        false  // Changed to false - this might help with some client implementations
                    )

                    if (res == true) {
                        success = true
                        Log.d(TAG, "Notification sent successfully to device ${device.address} on attempt $retries")
                    } else {
                        retries++
                        Log.e(TAG, "Notification attempt $retries failed for device ${device.address}. Retrying in $RETRY_DELAY_MILLIS ms")
                        Thread.sleep(RETRY_DELAY_MILLIS)
                    }
                }

                if (!success) {
                    Log.e(TAG, "Notification failed after $MAX_NOTIFICATION_RETRIES attempts for device ${device.address}")
                }
            }
        } else {
            bluetoothDevicesMap.forEach { (address, device) ->
                handler?.post {
                    // Attempt to send notification with retries
                    var success = false
                    var retries = 0

                    while (!success && retries < MAX_NOTIFICATION_RETRIES) {
                        val res = gattServer?.notifyCharacteristicChanged(
                            device,
                            char,
                            false  // Changed to false
                        )

                        if (res == true) {
                            success = true
                            Log.d(TAG, "Notification sent successfully to device $address on attempt $retries")
                        } else {
                            retries++
                            Log.e(TAG, "Notification attempt $retries failed for device $address. Retrying in $RETRY_DELAY_MILLIS ms")
                            Thread.sleep(RETRY_DELAY_MILLIS)
                        }
                    }

                    if (!success) {
                        Log.e(TAG, "Notification failed after $MAX_NOTIFICATION_RETRIES attempts for device $address")
                    }
                }
            }
        }
    }


    private fun isBluetoothEnabled(): Boolean {
        val bluetoothAdapter: BluetoothAdapter? = bluetoothManager?.adapter
        return bluetoothAdapter?.isEnabled ?: false
    }

    private fun enableBluetooth() {
        activity?.startActivityForResult(
            Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE),
            requestCodeBluetoothEnablePermission
        )
    }

    private fun onConnectionUpdate(device: BluetoothDevice, status: Int, newState: Int) {
        Log.e(TAG, "onConnectionStateChange: $status -> $newState")
        handler?.post {
            bleCallback?.onConnectionStateChange(
                device.address,
                newState == BluetoothProfile.STATE_CONNECTED,
            ) {}
        }
        // Send char unsubscribe event on disconnect
        if (newState == BluetoothProfile.STATE_DISCONNECTED) {
            cleanConnection(device)
        }
    }

    private fun cleanConnection(device: BluetoothDevice) {
        val deviceAddress = device.address

        // Notify char unsubscribe event on disconnect
        val subscribedCharUUID: MutableList<String> =
            subscribedCharDevicesMap[deviceAddress] ?: mutableListOf()
        subscribedCharUUID.forEach { charUUID ->
            handler?.post {
                bleCallback?.onCharacteristicSubscriptionChange(
                    deviceAddress,
                    charUUID,
                    false,
                    device.name
                ) {}
            }
        }
        subscribedCharDevicesMap.remove(deviceAddress)
    }

    private val advertiseCallback: AdvertiseCallback = object : AdvertiseCallback() {
        override fun onStartFailure(errorCode: Int) {
            super.onStartFailure(errorCode)
            handler?.post {
                val errorMessage: String = when (errorCode) {
                    ADVERTISE_FAILED_ALREADY_STARTED -> "Already started"
                    ADVERTISE_FAILED_DATA_TOO_LARGE -> "Data too large"
                    ADVERTISE_FAILED_FEATURE_UNSUPPORTED -> "Feature unsupported"
                    ADVERTISE_FAILED_INTERNAL_ERROR -> "Internal error"
                    ADVERTISE_FAILED_TOO_MANY_ADVERTISERS -> "Too many advertisers"
                    else -> "Failed to start advertising: $errorCode"
                }
                bleCallback?.onAdvertisingStatusUpdate(false, errorMessage) {}
            }
        }

        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            super.onStartSuccess(settingsInEffect)
            isAdvertising = true
            handler?.post {
                bleCallback?.onAdvertisingStatusUpdate(true, null) {}
            }
        }
    }


    private val gattServerCallback: BluetoothGattServerCallback =
        object : BluetoothGattServerCallback() {
            override fun onConnectionStateChange(
                device: BluetoothDevice,
                status: Int,
                newState: Int,
            ) {
                super.onConnectionStateChange(device, status, newState)
                when (newState) {
                    BluetoothProfile.STATE_CONNECTED -> {
                        if (device.bondState == BluetoothDevice.BOND_NONE) {
                            // Wait for bonding
                            listOfDevicesWaitingForBond.add(device.address)
                            //device.createBond()
                        } else if (device.bondState == BluetoothDevice.BOND_BONDED) {
                            handler?.post {
                                gattServer?.connect(device, true)
                            }
                            synchronized(bluetoothDevicesMap) {
                                bluetoothDevicesMap.put(
                                    device.address,
                                    device
                                )
                            }
                        }
                           handler?.post {
                                gattServer?.connect(device, true)
                            }
                            synchronized(bluetoothDevicesMap) {
                                bluetoothDevicesMap.put(
                                    device.address,
                                    device
                                )
                            }
                        onConnectionUpdate(device, status, newState)
                    }

                    BluetoothProfile.STATE_DISCONNECTED -> {
                        val deviceAddress = device.address
                        synchronized(bluetoothDevicesMap) { bluetoothDevicesMap.remove(deviceAddress) }
                        onConnectionUpdate(device, status, newState)
                    }

                    else -> {}
                }
            }

            override fun onMtuChanged(device: BluetoothDevice?, mtu: Int) {
                super.onMtuChanged(device, mtu)
                device?.address?.let {
                    handler?.post {
                        bleCallback?.onMtuChange(it, mtu.toLong()) {}
                    }
                }
            }

            override fun onCharacteristicReadRequest(
                device: BluetoothDevice,
                requestId: Int,
                offset: Int,
                characteristic: BluetoothGattCharacteristic,
            ) {
                super.onCharacteristicReadRequest(device, requestId, offset, characteristic)
                if (gattServer == null) return
                handler?.post {
                    bleCallback?.onReadRequest(
                        deviceIdArg = device.address,
                        characteristicIdArg = characteristic.uuid.toString(),
                        offsetArg = offset.toLong(),
                        valueArg = characteristic.value,
                    ) { it: Result<ReadRequestResult?> ->
                        val readRequestResult: ReadRequestResult? = it.getOrNull()
                        if (readRequestResult == null) {
                            gattServer?.sendResponse(
                                device,
                                requestId,
                                BluetoothGatt.GATT_FAILURE,
                                0,
                                ByteArray(0)
                            )
                        } else {
                            gattServer?.sendResponse(
                                device,
                                requestId,
                                BluetoothGatt.GATT_SUCCESS,
                                readRequestResult.offset?.toInt() ?: 0,
                                readRequestResult.value
                            )
                        }
                    }
                }
            }

            override fun onCharacteristicWriteRequest(
                device: BluetoothDevice,
                requestId: Int,
                characteristic: BluetoothGattCharacteristic,
                preparedWrite: Boolean,
                responseNeeded: Boolean,
                offset: Int,
                value: ByteArray,
            ) {
                super.onCharacteristicWriteRequest(
                    device,
                    requestId,
                    characteristic,
                    preparedWrite,
                    responseNeeded,
                    offset,
                    value
                )
                handler?.post {
                    bleCallback?.onWriteRequest(
                        deviceIdArg = device.address,
                        characteristicIdArg = characteristic.uuid.toString(),
                        offsetArg = offset.toLong(),
                        valueArg = value,
                    ) {
                        val writeResult: WriteRequestResult? = it.getOrNull()
                        gattServer?.sendResponse(
                            device,
                            requestId,
                            writeResult?.status?.toInt() ?: BluetoothGatt.GATT_SUCCESS,
                            writeResult?.offset?.toInt() ?: 0,
                            writeResult?.value ?: emptyBytes
                        )
                    }
                }
            }

            override fun onServiceAdded(status: Int, service: BluetoothGattService) {
                super.onServiceAdded(status, service)
                var error: String? = null
                if (status != 0) {
                    error = "Adding Service failed.."
                }
                handler?.post {
                    bleCallback?.onServiceAdded(service.uuid.toString(), error) {}
                }
            }

            override fun onDescriptorReadRequest(
                device: BluetoothDevice,
                requestId: Int,
                offset: Int,
                descriptor: BluetoothGattDescriptor,
            ) {
                super.onDescriptorReadRequest(device, requestId, offset, descriptor)
                Log.e(TAG, "onDescriptorReadRequest: -> ${descriptor.uuid}")
                handler?.post {
                    val value: ByteArray? = descriptor.getCacheValue()
                    if (value != null) {
                        gattServer?.sendResponse(
                            device,
                            requestId,
                            BluetoothGatt.GATT_SUCCESS,
                            0,
                            value
                        )
                    } else {
                        gattServer?.sendResponse(
                            device,
                            requestId,
                            BluetoothGatt.GATT_FAILURE,
                            0,
                            emptyBytes
                        )
                    }
                }
            }

            override fun onDescriptorWriteRequest(
                device: BluetoothDevice?,
                requestId: Int,
                descriptor: BluetoothGattDescriptor,
                preparedWrite: Boolean,
                responseNeeded: Boolean,
                offset: Int,
                value: ByteArray?,
            ) {
                super.onDescriptorWriteRequest(
                    device,
                    requestId,
                    descriptor,
                    preparedWrite,
                    responseNeeded,
                    offset,
                    value
                )
                Log.d(
                    TAG,
                    "onDescriptorWriteRequest: ${value?.toIntArray()} -> ${descriptor.uuid} | Char UUID: ${descriptor.characteristic.uuid}"
                )
                descriptor.setValue(value)
                if (descriptor.uuid.toString().lowercase() == descriptorCCUUID) {
                    val isSubscribed =
                        BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE.contentEquals(value)
                                || BluetoothGattDescriptor.ENABLE_INDICATION_VALUE.contentEquals(
                            value
                        )
                    val characteristicId = descriptor.characteristic.uuid.toString()
                    device?.address?.let {
                        handler?.post {
                            bleCallback?.onCharacteristicSubscriptionChange(
                                it,
                                characteristicId,
                                isSubscribed,
                                device.name
                            ) {}
                        }

                        // Update subscribed char list
                        val charList: MutableList<String> =
                            subscribedCharDevicesMap[it] ?: mutableListOf()
                        if (isSubscribed) {
                            charList.add(characteristicId)
                        } else if (charList.contains(characteristicId)) {
                            charList.remove(characteristicId)
                        }
                        subscribedCharDevicesMap[it] = charList
                    }

                }
                if (responseNeeded) {
                    gattServer?.sendResponse(
                        device,
                        requestId,
                        BluetoothGatt.GATT_SUCCESS,
                        offset,
                        value ?: emptyBytes
                    )
                }
            }

            override fun onNotificationSent(device: BluetoothDevice?, status: Int) {
                super.onNotificationSent(device, status)
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    Log.e(
                        TAG,
                        "onNotificationSentFailed:${device?.address} ${device?.name}, Status: $status"
                    )
                }
            }
        }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        val intentFilter = IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)
        intentFilter.addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity?.registerReceiver(broadcastReceiver, intentFilter, RECEIVER_EXPORTED)
        } else {
            activity?.registerReceiver(broadcastReceiver, intentFilter)
        }
    }

    override fun onDetachedFromActivity() {
        activity?.unregisterReceiver(broadcastReceiver)
        activity = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        bleCallback = null
    }

    override fun onDetachedFromActivityForConfigChanges() {}
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {}


    private val broadcastReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val action = intent.action
            if (action == BluetoothAdapter.ACTION_STATE_CHANGED) {
                if (!intent.hasExtra(BluetoothAdapter.EXTRA_STATE)) return

                when (intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)) {
                    BluetoothAdapter.STATE_OFF -> {
                        handler?.post {
                            bleCallback?.onBleStateChange(false) {}
                        }
                    }

                    BluetoothAdapter.STATE_ON -> {
                        handler?.post {
                            bleCallback?.onBleStateChange(true) {}
                        }
                    }

                    else -> {}
                }
            } else if (action == BluetoothDevice.ACTION_BOND_STATE_CHANGED) {
                if (!intent.hasExtra(BluetoothDevice.EXTRA_BOND_STATE) || !intent.hasExtra(
                        BluetoothDevice.EXTRA_DEVICE
                    )
                ) return

                val state =
                    intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.ERROR)
                val device: BluetoothDevice? =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(
                            BluetoothDevice.EXTRA_DEVICE,
                            BluetoothDevice::class.java
                        )
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                    }

                handler?.post {
                    bleCallback?.onBondStateChange(
                        device?.address ?: "",
                        state.toBondState(),
                    ) {}
                }

                // if waiting for connection and device is bonded
                val waitingForConnection = listOfDevicesWaitingForBond.contains(device?.address)
                if ( device != null && waitingForConnection) {
                    listOfDevicesWaitingForBond.remove(device.address)
                    handler?.post {
                        gattServer?.connect(device, true)
                    }
                }
            }
        }
    }

    /// TODO: verify required permissions
    override fun askBlePermission(): Boolean {
        val permissionsList = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(
                Manifest.permission.BLUETOOTH_ADMIN,
                Manifest.permission.BLUETOOTH,
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT,
                Manifest.permission.BLUETOOTH_ADVERTISE,
            )
        } else {
            arrayOf(
                Manifest.permission.BLUETOOTH_ADMIN,
                Manifest.permission.BLUETOOTH,
            )
        }
        val havePermission = activity?.havePermission(permissionsList) ?: false
        if (havePermission) return true
        activity?.let {
            ActivityCompat.requestPermissions(
                it,
                permissionsList,
                requestCodeBluetoothPermission
            )
        }
        return false
    }

//    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
//        if (requestCode == requestCodeBluetoothPermission) {
//            Log.d(TAG, "onActivityResultForBlePermission: ${resultCode == Activity.RESULT_OK}")
//        } else if (requestCode == requestCodeBluetoothEnablePermission) {
//            Log.d(TAG, "onActivityResultForBleEnable: ${resultCode == Activity.RESULT_OK}")
//        }
//        return false
//    }
}

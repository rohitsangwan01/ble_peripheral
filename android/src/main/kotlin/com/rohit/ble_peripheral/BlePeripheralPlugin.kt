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
import io.flutter.plugin.common.PluginRegistry
import java.util.Collections

private const val TAG = "BlePeripheralPlugin"

@SuppressLint("MissingPermission")
class BlePeripheralPlugin : FlutterPlugin, BlePeripheralChannel, ActivityAware {
    // PluginRegistry.ActivityResultListener {
    private val requestCodeBluetoothPermission = 0xa1c
    var bleCallback: BleCallback? = null
    private val requestCodeBluetoothEnablePermission = 0xb1e
    private lateinit var applicationContext: Context
    private lateinit var activity: Activity
    private lateinit var handler: Handler
    private lateinit var bluetoothManager: BluetoothManager
    private var bluetoothLeAdvertiser: BluetoothLeAdvertiser? = null
    private var gattServer: BluetoothGattServer? = null
    private val bluetoothDevicesMap: MutableMap<String, BluetoothDevice> = HashMap()
    private val emptyBytes = byteArrayOf()
    private val listOfDevicesWaitingForBond = mutableListOf<String>()
    private var isAdvertising: Boolean? = null

    private val devices: Set<BluetoothDevice>
        get() {
            val deviceSet: MutableSet<BluetoothDevice> = HashSet()
            synchronized(bluetoothDevicesMap) { deviceSet.addAll(bluetoothDevicesMap.values) }
            return Collections.unmodifiableSet(deviceSet)
        }


    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        BlePeripheralChannel.setUp(flutterPluginBinding.binaryMessenger, this)
        bleCallback = BleCallback(flutterPluginBinding.binaryMessenger)
        applicationContext = flutterPluginBinding.applicationContext
    }


    override fun initialize() {
        // if (!validatePermission()) throw Exception("Bluetooth Permission not granted")
        handler = Handler(applicationContext.mainLooper)
        bluetoothManager =
            applicationContext.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val bluetoothAdapter = bluetoothManager.adapter
            ?: throw UnsupportedOperationException("Bluetooth is not available.")
        bluetoothLeAdvertiser = bluetoothAdapter.bluetoothLeAdvertiser
        if (bluetoothLeAdvertiser == null) throw UnsupportedOperationException("Bluetooth LE Advertising not supported on this device.")
        gattServer = bluetoothManager.openGattServer(applicationContext, gattServerCallback)
        if (gattServer == null) throw UnsupportedOperationException("gattServer is null, check Bluetooth is ON.")
        bleCallback?.onBleStateChange(isBluetoothEnabled()) {}
    }


    override fun isAdvertising(): Boolean? {
        return isAdvertising
    }

    override fun isSupported(): Boolean {
        val bluetoothAdapter = bluetoothManager.adapter
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
        localName: String,
        timeout: Long?,
        manufacturerData: ManufacturerData?,
        addManufacturerDataInScanResponse: Boolean,
    ) {
        if (!isBluetoothEnabled()) {
            enableBluetooth()
            throw Exception("Bluetooth is not enabled")
        }

        handler.post { // set up advertising setting
            bluetoothManager.adapter.name = localName
            val advertiseSettings = AdvertiseSettings.Builder()
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                .setConnectable(true)
                .setTimeout(timeout?.toInt() ?: 0)
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .build()

            val advertiseDataBuilder = AdvertiseData.Builder()
                .setIncludeTxPowerLevel(false)
                .setIncludeDeviceName(true)

            val scanResponseBuilder = AdvertiseData.Builder()
                .setIncludeTxPowerLevel(false)
                .setIncludeDeviceName(true)

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
        handler.post {
            try {
                bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback)
                isAdvertising = false
                bleCallback?.onAdvertisingStatusUpdate(false, null) {}
                if (gattServer != null) {
                    val devices: Set<BluetoothDevice> = devices
                    for (device in devices) {
                        gattServer?.cancelConnection(device)
                    }
//                    gattServer?.close()
//                    gattServer = null
                }
            } catch (ignored: IllegalStateException) {
                throw Exception("Bluetooth Adapter is not turned ON")
            }
        }
    }

    override fun updateCharacteristic(
        devoiceID: String,
        characteristicId: String,
        value: ByteArray,
    ) {
        val device = bluetoothDevicesMap[devoiceID] ?: throw Exception("Device not found")
        val char =
            characteristicId.findCharacteristic() ?: throw Exception("Characteristic not found")
        handler.post {
            char.value = value
            gattServer?.notifyCharacteristicChanged(
                device,
                char,
                true
            )
        }
    }


    private fun isBluetoothEnabled(): Boolean {
        val bluetoothAdapter: BluetoothAdapter? = bluetoothManager.adapter
        return bluetoothAdapter?.isEnabled ?: false
    }

    private fun enableBluetooth() {
        activity.startActivityForResult(
            Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE),
            requestCodeBluetoothEnablePermission
        )
    }

    private fun onConnectionUpdate(device: BluetoothDevice, status: Int, newState: Int) {
        Log.e(TAG, "onConnectionStateChange: $status -> $newState")
        handler.post {
            bleCallback?.onConnectionStateChange(
                device.address,
                newState == BluetoothProfile.STATE_CONNECTED,
            ) {}
        }
    }

    private val advertiseCallback: AdvertiseCallback = object : AdvertiseCallback() {
        override fun onStartFailure(errorCode: Int) {
            super.onStartFailure(errorCode)
            handler.post {
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
            handler.post {
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
                            device.createBond()
                        } else if (device.bondState == BluetoothDevice.BOND_BONDED) {
                            handler.post {
                                gattServer?.connect(device, true)
                            }
                            synchronized(bluetoothDevicesMap) {
                                bluetoothDevicesMap.put(
                                    device.address,
                                    device
                                )
                            }
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
                    handler.post {
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
                handler.post {
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
                handler.post {
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
                handler.post {
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
                handler.post {
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
                gattServer?.sendResponse(
                    device,
                    requestId,
                    BluetoothGatt.GATT_SUCCESS,
                    0,
                    emptyBytes
                )
            }
        }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        val intentFilter = IntentFilter()
        intentFilter.addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
        intentFilter.addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
        activity.registerReceiver(broadcastReceiver, intentFilter)
    }

    override fun onDetachedFromActivity() {
        activity.unregisterReceiver(broadcastReceiver)
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
                when (intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)) {
                    BluetoothAdapter.STATE_OFF -> {
                        handler.post {
                            bleCallback?.onBleStateChange(false) {}
                        }
                    }

                    BluetoothAdapter.STATE_ON -> {
                        handler.post {
                            bleCallback?.onBleStateChange(true) {}
                        }
                    }

                    else -> {}
                }
            } else if (action == BluetoothDevice.ACTION_BOND_STATE_CHANGED) {
                val state =
                    intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.ERROR)
                val device: BluetoothDevice? =
                    intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)

                handler.post {
                    bleCallback?.onBondStateChange(
                        device?.address ?: "",
                        state.toBondState(),
                    ) {}
                }

                // if waiting for connection and device is bonded
                val waitingForConnection = listOfDevicesWaitingForBond.contains(device?.address)
                if (state == BluetoothDevice.BOND_BONDED && device != null && waitingForConnection) {
                    listOfDevicesWaitingForBond.remove(device.address)
                    handler.post {
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
        val havePermission = activity.havePermission(permissionsList)
        if (havePermission) return true
        ActivityCompat.requestPermissions(
            activity,
            permissionsList,
            requestCodeBluetoothPermission
        )
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

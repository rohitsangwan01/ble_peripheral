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
import java.util.Queue
import java.util.concurrent.LinkedBlockingQueue


private val TAG = BlePeripheralPlugin::class.java.simpleName

@SuppressLint("MissingPermission")
class BlePeripheralPlugin : FlutterPlugin, BlePeripheralChannel, ActivityAware,
    PluginRegistry.ActivityResultListener {
    var bleCallback: BleCallback? = null
    private val requestCodeBluetoothEnablePermission = 0xb1e
    private val requestCodeBluetoothPermission = 0xa1c
    private lateinit var applicationContext: Context
    private lateinit var activity: Activity
    private var handler: Handler? = null
    private lateinit var bluetoothManager: BluetoothManager
    private var bluetoothLeAdvertiser: BluetoothLeAdvertiser? = null
    private var gattServer: BluetoothGattServer? = null
    private val bluetoothDevicesMap: MutableMap<String, BluetoothDevice> = HashMap()
    private val servicesToAdd: Queue<BluetoothGattService?> = LinkedBlockingQueue()
    private val emptyBytes = byteArrayOf()
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
        if (!validatePermission()) throw Exception("Bluetooth Permission not granted")
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

    //TODO: Implement the following methods
    override fun isAdvertising(): Boolean {
        return true
    }

    override fun isSupported(): Boolean {
        val bluetoothAdapter = bluetoothManager.adapter
        if (!bluetoothAdapter.isEnabled) throw UnsupportedOperationException("Bluetooth is disabled.")
        if (!bluetoothAdapter.isMultipleAdvertisementSupported) throw UnsupportedOperationException(
            "Bluetooth LE Advertising not supported on this device."
        )
        return true
    }

    override fun addServices(services: List<BleService>) {
        // To make sure that we are safe from race condition
        val totalServices = services.size - 1
        for (i in 0..totalServices) {
            servicesToAdd.add(services[i].toGattService())
        }
        addService(services.last().toGattService())
    }

    override fun startAdvertising(services: List<UUID>, localName: String) {
        if (!isBluetoothEnabled()) {
            enableBluetooth()
            throw Exception("Bluetooth is not enabled")
        }
        while (servicesToAdd.peek() != null) {
            Log.e(TAG, "Waiting for service to be added")
        }
        handler?.post { // set up advertising setting
            bluetoothManager.adapter.name = localName
            val advertiseSettings = AdvertiseSettings.Builder()
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                .setConnectable(true)
                .setTimeout(0)
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .build()
            val advertiseDataBuilder = AdvertiseData.Builder()
                .setIncludeTxPowerLevel(false)
                .setIncludeDeviceName(true)
            services.forEach {
                advertiseDataBuilder.addServiceUuid(ParcelUuid.fromString(it.value))
            }
            bluetoothLeAdvertiser?.startAdvertising(
                advertiseSettings,
                advertiseDataBuilder.build(),
                advertiseCallback
            )
        }
    }

    override fun stopAdvertising() {
        handler?.post {
            try {
                bluetoothLeAdvertiser!!.stopAdvertising(advertiseCallback)
                if (gattServer != null) {
                    val devices: Set<BluetoothDevice> = devices
                    for (device in devices) {
                        gattServer!!.cancelConnection(device)
                    }
//                    gattServer!!.close()
//                    gattServer = null
                }
            } catch (ignored: IllegalStateException) {
                throw Exception("Bluetooth Adapter is not turned ON")
            }
        }
    }

    override fun updateCharacteristic(
        central: BleCentral,
        characteristic: BleCharacteristic,
        value: ByteArray
    ) {
        val device = bluetoothDevicesMap[central.uuid.value] ?: throw Exception("Device not found")
        val char = characteristic.find() ?: throw Exception("Characteristic not found")
        //Log.e("Test", "updateCharacteristic: ${char.uuid} -> ${value.contentToString()}")
        handler?.post {
            char.value = value
            gattServer?.notifyCharacteristicChanged(
                device,
                char,
                true
            )
        }
    }

    private fun validatePermission(): Boolean {
        val permissionsList = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(
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

    private fun addService(service: BluetoothGattService?) {
        assert(gattServer != null)
        var serviceAdded = false
        while (!serviceAdded) {
            try {
                serviceAdded = gattServer!!.addService(service)
            } catch (e: Exception) {
                Log.d(TAG, "Adding Service failed", e)
            }
        }
        service?.let {
            handler?.post {
                bleCallback?.onServiceAdded(it.toBleService(), null) {}
            }
        }
        Log.d(TAG, "Service: " + service!!.uuid + " added.")
    }

    private fun onConnectionUpdate(device: BluetoothDevice, status: Int, newState: Int) {
        Log.e(TAG, "onConnectionStateChange: $status -> $newState")
        handler?.post {
            bleCallback?.onConnectionStateChange(
                BleCentral(uuid = UUID(value = device.address)),
                newState == BluetoothProfile.STATE_CONNECTED,
            ) {}
        }
    }

    private val advertiseCallback: AdvertiseCallback = object : AdvertiseCallback() {
        override fun onStartFailure(errorCode: Int) {
            super.onStartFailure(errorCode)
            bleCallback?.onAdvertisingStarted("Failed to start advertising: $errorCode") {}
        }

        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            super.onStartSuccess(settingsInEffect)
            bleCallback?.onAdvertisingStarted(null) {}
        }
    }

    private val gattServerCallback: BluetoothGattServerCallback =
        object : BluetoothGattServerCallback() {
            override fun onConnectionStateChange(
                device: BluetoothDevice,
                status: Int,
                newState: Int
            ) {
                super.onConnectionStateChange(device, status, newState)
                when (newState) {
                    BluetoothProfile.STATE_CONNECTED -> {
                        if (device.bondState == BluetoothDevice.BOND_NONE) {
                            applicationContext.registerReceiver(object : BroadcastReceiver() {
                                override fun onReceive(context: Context, intent: Intent) {
                                    val action = intent.action
                                    if (BluetoothDevice.ACTION_BOND_STATE_CHANGED == action) {
                                        val state = intent.getIntExtra(
                                            BluetoothDevice.EXTRA_BOND_STATE,
                                            BluetoothDevice.ERROR
                                        )
                                        if (state == BluetoothDevice.BOND_BONDED) {
                                            // successfully bonded
                                            context.unregisterReceiver(this)
                                            handler?.post {
                                                gattServer?.connect(device, true)
                                            }
                                        }
                                    }
                                }
                            }, IntentFilter(BluetoothDevice.ACTION_BOND_STATE_CHANGED))
                            // create bond
                            try {
                                device.setPairingConfirmation(true)
                            } catch (e: SecurityException) {
                                Log.d(TAG, e.message, e)
                            }
                            device.createBond()
                        } else if (device.bondState == BluetoothDevice.BOND_BONDED) {
                            handler?.post {
                                if (gattServer != null) {
                                    Log.d(TAG, "Connecting to device: " + device.address)
                                    gattServer!!.connect(device, true)
                                }
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

                        // try reconnect immediately
                        handler?.post {
                            if (gattServer != null) {
                                // gattServer.cancelConnection(device);
                                gattServer!!.connect(device, true)
                            }
                        }
                        synchronized(bluetoothDevicesMap) { bluetoothDevicesMap.remove(deviceAddress) }
                        onConnectionUpdate(device, status, newState)
                    }

                    else -> {}
                }
            }

            override fun onCharacteristicReadRequest(
                device: BluetoothDevice,
                requestId: Int,
                offset: Int,
                characteristic: BluetoothGattCharacteristic
            ) {
                super.onCharacteristicReadRequest(device, requestId, offset, characteristic)
                if (gattServer == null) return
                handler?.post {
                    bleCallback?.onReadRequest(
                        characteristicArg = characteristic.toBleCharacteristic(),
                        offsetArg = offset.toLong(),
                        valueArg = characteristic.value,
                    ) { it: ReadRequestResult? ->
                        if (it == null) {
                            gattServer!!.sendResponse(
                                device,
                                requestId,
                                BluetoothGatt.GATT_FAILURE,
                                0,
                                ByteArray(0)
                            )
                        } else {
                            gattServer!!.sendResponse(
                                device,
                                requestId,
                                BluetoothGatt.GATT_SUCCESS,
                                it.offset?.toInt() ?: 0,
                                it.value
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
                value: ByteArray
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
                bleCallback?.onWriteRequest(
                    characteristicArg = characteristic.toBleCharacteristic(),
                    offsetArg = offset.toLong(),
                    valueArg = characteristic.value,
                ) {
                    gattServer!!.sendResponse(
                        device,
                        requestId,
                        BluetoothGatt.GATT_SUCCESS,
                        0,
                        emptyBytes
                    )
                }
            }

            override fun onServiceAdded(status: Int, service: BluetoothGattService) {
                super.onServiceAdded(status, service)
                if (status != 0) Log.d(TAG, "onServiceAdded Adding Service failed..")
                if (servicesToAdd.peek() != null) {
                    addService(servicesToAdd.remove())
                }
            }

            override fun onDescriptorReadRequest(
                device: BluetoothDevice,
                requestId: Int,
                offset: Int,
                descriptor: BluetoothGattDescriptor
            ) {
                super.onDescriptorReadRequest(device, requestId, offset, descriptor)
                handler?.post {
                    val value: ByteArray? = descriptor.getCacheValue()
                    Log.e(
                        "Test",
                        "onDescriptorReadRequest requestId: "
                                + requestId + ", offset: "
                                + offset + ", descriptor: "
                                + descriptor.uuid + ", Value: $value"
                    )
                    if (value != null) {
                        gattServer!!.sendResponse(
                            device,
                            requestId,
                            BluetoothGatt.GATT_SUCCESS,
                            0,
                            value
                        )
                    } else {
                        gattServer!!.sendResponse(
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
                value: ByteArray?
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
                Log.e(TAG, "onDescriptorWriteRequest, uuid: " + descriptor.uuid)
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
                        bleCallback?.onBleStateChange(false) {}
                    }

                    BluetoothAdapter.STATE_ON -> {
                        bleCallback?.onBleStateChange(true) {}
                    }

                    else -> {}
                }
            } else if (action == BluetoothDevice.ACTION_BOND_STATE_CHANGED) {
                val state =
                    intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.ERROR)
                val device: BluetoothDevice? =
                    intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                handler?.post {
                    bleCallback?.onBondStateChange(
                        BleCentral(uuid = UUID(value = device?.address ?: "")),
                        state.toBondState(),
                    ) {}
                }
            }
        }
    }


    // TODO: start bluetooth on enable
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == requestCodeBluetoothPermission) {
            Log.d(TAG, "onActivityResultForBlePermission: ${resultCode == Activity.RESULT_OK}")
        } else if (requestCode == requestCodeBluetoothEnablePermission) {
            Log.d(TAG, "onActivityResultForBleEnable: ${resultCode == Activity.RESULT_OK}")
        }
        return false
    }
}

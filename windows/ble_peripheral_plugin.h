#ifndef FLUTTER_PLUGIN_BLE_PERIPHERAL_PLUGIN_H_
#define FLUTTER_PLUGIN_BLE_PERIPHERAL_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <windows.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Windows.Devices.Enumeration.h>
#include <winrt/Windows.Devices.Radios.h>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Bluetooth.Advertisement.h>
#include <winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h>
#include <memory>
#include "BlePeripheral.g.h"
#include "Utils.h"
#include "ui_thread_handler.hpp"

namespace ble_peripheral
{
    using namespace winrt;
    using namespace winrt::Windows::Devices;
    using namespace winrt::Windows::Foundation;
    using namespace winrt::Windows::Foundation::Collections;
    using namespace winrt::Windows::Storage::Streams;
    using namespace winrt::Windows::Devices::Radios;
    using namespace winrt::Windows::Devices::Bluetooth;
    using namespace winrt::Windows::Devices::Bluetooth::Advertisement;
    using namespace winrt::Windows::Devices::Bluetooth::GenericAttributeProfile;
    using namespace Windows::Devices::Enumeration;

    using flutter::EncodableMap;
    using flutter::EncodableValue;

    // create enum for this
    enum class BlePermission : int
    {
        readable = 0,
        writeable = 1,
        readEncryptionRequired = 2,
        writeEncryptionRequired = 3,
        none = 4,
    };

    struct GattCharacteristicObject
    {
        GattLocalCharacteristic obj = nullptr;
        IVectorView<GattSubscribedClient> stored_clients;
        winrt::event_token value_changed_token;
        winrt::event_token read_requested_token;
        winrt::event_token write_requested_token;
    };

    struct GattServiceProviderObject
    {
        GattServiceProvider obj = nullptr;
        winrt::event_token advertisement_status_changed_token;
        std::map<std::string, GattCharacteristicObject *> characteristics;
    };

    class BlePeripheralPlugin : public flutter::Plugin, public BlePeripheralChannel
    {
    public:
        static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

        BlePeripheralPlugin(flutter::PluginRegistrarWindows *registrar);

        ~BlePeripheralPlugin();

        static void SuccessCallback() {}
        static void ErrorCallback(const FlutterError &error)
        {
            std::cout << "ErrorCallback: " << error.message() << std::endl;
        }

        // Disallow copy and assign.
        BlePeripheralPlugin(const BlePeripheralPlugin &) = delete;
        BlePeripheralPlugin &operator=(const BlePeripheralPlugin &) = delete;

        BlePeripheralUiThreadHandler uiThreadHandler_;

        // BluetoothLe
        Radio bluetoothRadio{nullptr};

        winrt::fire_and_forget InitializeAdapter();
        winrt::fire_and_forget AddServiceAsync(const BleService &service);
        GattCharacteristicProperties toGattCharacteristicProperties(int property);
        BlePermission toBlePermission(int permission);
        std::string AdvertisementStatusToString(GattServiceProviderAdvertisementStatus status);
        void disposeGattServiceObject(GattServiceProviderObject *gattServiceObject);
        void Radio_StateChanged(Radio radio, IInspectable args);
        RadioState oldRadioState = RadioState::Unknown;
        winrt::event_revoker<IRadio> radioStateChangedRevoker;
        std::string ParseBluetoothClientId(hstring clientId);

        GattCharacteristicObject *FindGattCharacteristicObject(std::string characteristicId);

        void ServiceProvider_AdvertisementStatusChanged(GattServiceProvider const &sender, GattServiceProviderAdvertisementStatusChangedEventArgs const &);
        void SubscribedClientsChanged(GattLocalCharacteristic const &sender, IInspectable const &);
        winrt::fire_and_forget ReadRequestedAsync(GattLocalCharacteristic const &, GattReadRequestedEventArgs args);
        winrt::fire_and_forget WriteRequestedAsync(GattLocalCharacteristic const &, GattWriteRequestedEventArgs args);
        std::string ParseBluetoothError(BluetoothError error);
        bool AreAllServicesStarted();

        // BlePeripheralChannel
        std::optional<FlutterError> Initialize();
        ErrorOr<std::optional<bool>> IsAdvertising();
        ErrorOr<bool> IsSupported();
        std::optional<FlutterError> StopAdvertising();
        ErrorOr<bool> AskBlePermission();
        std::optional<FlutterError> AddService(const BleService &service);
        std::optional<FlutterError> RemoveService(const std::string &service_id);
        std::optional<FlutterError> ClearServices();
        ErrorOr<flutter::EncodableList> GetServices();
        std::optional<FlutterError> StartAdvertising(
            const flutter::EncodableList &services,
            const std::string* local_name,
            const int64_t *timeout,
            const ManufacturerData *manufacturer_data,
            bool add_manufacturer_data_in_scan_response);
        std::optional<FlutterError> UpdateCharacteristic(
            const std::string& characteristic_id,
            const std::vector<uint8_t>& value,
            const std::string* device_id);
    };

} // namespace ble_peripheral

#endif // FLUTTER_PLUGIN_BLE_PERIPHERAL_PLUGIN_H_

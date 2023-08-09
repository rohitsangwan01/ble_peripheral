#ifndef FLUTTER_PLUGIN_BLE_PERIPHERAL_PLUGIN_H_
#define FLUTTER_PLUGIN_BLE_PERIPHERAL_PLUGIN_H_

#include <windows.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Windows.Devices.Radios.h>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Bluetooth.Advertisement.h>
#include <winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h>
#include <winrt/Windows.Devices.Enumeration.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <memory>
#include "BlePeripheral.g.h"

namespace ble_peripheral
{
    using namespace winrt;
    using namespace winrt::Windows::Foundation;
    using namespace winrt::Windows::Foundation::Collections;
    using namespace winrt::Windows::Storage::Streams;
    using namespace winrt::Windows::Devices::Radios;
    using namespace winrt::Windows::Devices::Bluetooth;
    using namespace winrt::Windows::Devices::Bluetooth::Advertisement;
    using namespace winrt::Windows::Devices::Bluetooth::GenericAttributeProfile;
    using namespace winrt::Windows::Devices::Enumeration;

    using flutter::EncodableMap;
    using flutter::EncodableValue;

    class BlePeripheralPlugin : public flutter::Plugin, public BlePeripheralChannel
    {
    public:
        static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

        BlePeripheralPlugin();

        virtual ~BlePeripheralPlugin();

        // Disallow copy and assign.
        BlePeripheralPlugin(const BlePeripheralPlugin &) = delete;
        BlePeripheralPlugin &operator=(const BlePeripheralPlugin &) = delete;

        // BluetoothLe
        winrt::fire_and_forget InitializeAdapter();

        Radio bluetoothRadio{nullptr};

        BluetoothLEAdvertisementPublisher bluetoothLEPublisher{nullptr};
        winrt::event_token status_changed_token;

        // BlePeripheralChannel

        std::optional<FlutterError> Initialize() override;

        ErrorOr<bool> IsAdvertising() override;

        ErrorOr<bool> IsSupported() override;

        std::optional<FlutterError> StopAdvertising() override;

        std::optional<FlutterError> AddServices(const flutter::EncodableList &services) override;

        std::optional<FlutterError> StartAdvertising(
            const flutter::EncodableList &services,
            const std::string &local_name) override;

        std::optional<FlutterError> UpdateCharacteristic(
            const BleCentral &central,
            const BleCharacteristic &characteristic,
            const std::vector<uint8_t> &value) override;
    };

} // namespace ble_peripheral

#endif // FLUTTER_PLUGIN_BLE_PERIPHERAL_PLUGIN_H_

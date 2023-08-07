#ifndef FLUTTER_PLUGIN_BLE_PERIPHERAL_PLUGIN_H_
#define FLUTTER_PLUGIN_BLE_PERIPHERAL_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <memory>
#include "BlePeripheral.g.h"

namespace ble_peripheral
{

    class BlePeripheralPlugin : public flutter::Plugin, public BlePeripheralChannel
    {
    public:
        static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

        BlePeripheralPlugin();

        virtual ~BlePeripheralPlugin();

        // Disallow copy and assign.
        BlePeripheralPlugin(const BlePeripheralPlugin &) = delete;
        BlePeripheralPlugin &operator=(const BlePeripheralPlugin &) = delete;

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

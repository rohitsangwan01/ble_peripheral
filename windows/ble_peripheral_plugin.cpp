#include "ble_peripheral_plugin.h"
// This must be included before many other Windows headers.
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
#include <flutter/standard_method_codec.h>

#include <memory>
#include <sstream>
#include "BlePeripheral.g.h"

namespace ble_peripheral
{
  using ble_peripheral::BleCallback;
  using ble_peripheral::BlePeripheralChannel;
  using ble_peripheral::ErrorOr;
  std::unique_ptr<BleCallback> bleCallback;

  // static
  void BlePeripheralPlugin::RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar)
  {
    auto plugin = std::make_unique<BlePeripheralPlugin>();
    BlePeripheralChannel::SetUp(registrar->messenger(), plugin.get());
    bleCallback = std::make_unique<BleCallback>(registrar->messenger());
    registrar->AddPlugin(std::move(plugin));
  }

  BlePeripheralPlugin::BlePeripheralPlugin() {}

  BlePeripheralPlugin::~BlePeripheralPlugin() {}

  winrt::fire_and_forget BlePeripheralPlugin::InitializeAdapter()
  {
    auto bluetoothAdapter = co_await BluetoothAdapter::GetDefaultAsync();
    bluetoothRadio = co_await bluetoothAdapter.GetRadioAsync();
    bluetoothLEPublisher = BluetoothLEAdvertisementPublisher();
  }

  std::optional<FlutterError> BlePeripheralPlugin::Initialize()
  {
    InitializeAdapter();
    std::cout << "Initialize called" << std::endl;

    return std::nullopt;
  }

  ErrorOr<std::optional<bool>> BlePeripheralPlugin::IsAdvertising()
  {
    std::cout << "IsAdvertising called" << std::endl;
    return ErrorOr<std::optional<bool>>(std::nullopt);
  }

  ErrorOr<bool> BlePeripheralPlugin::IsSupported()
  {
    std::cout << "IsSupported called" << std::endl;
    return true;
  }

  ErrorOr<bool> BlePeripheralPlugin::AskBlePermission()
  {
    std::cout << "AskBlePermission called" << std::endl;
    return true;
  };

  std::optional<FlutterError> BlePeripheralPlugin::AddService(const BleService &service)
  {
    std::cout << "AddService called" << std::endl;
    return std::nullopt;
  };

  std::optional<FlutterError> BlePeripheralPlugin::StartAdvertising(
      const flutter::EncodableList &services,
      const std::string &local_name,
      const int64_t *timeout,
      const ManufacturerData *manufacturer_data,
      bool add_manufacturer_data_in_scan_response)
  {
    Advertisement::BluetoothLEManufacturerData manufacturerData = Advertisement::BluetoothLEManufacturerData();
    manufacturerData.CompanyId(0xFFFE);
    auto dataWriter = DataWriter();
    dataWriter.WriteBytes("Test");
    manufacturerData.Data(dataWriter.DetachBuffer());

    bluetoothLEPublisher.Advertisement().ManufacturerData().Append(manufacturerData);
    bluetoothLEPublisher.Start();
    std::cout << "StartAdvertising called" << std::endl;
    return std::nullopt;
  }

  std::optional<FlutterError> BlePeripheralPlugin::StopAdvertising()
  {
    std::cout << "StopAdvertising called" << std::endl;
    bluetoothLEPublisher.Advertisement().ManufacturerData().Clear();
    bluetoothLEPublisher.Stop();
    return std::nullopt;
  }

  std::optional<FlutterError> BlePeripheralPlugin::UpdateCharacteristic(
      const std::string &devoice_i_d,
      const std::string &characteristic_id,
      const std::vector<uint8_t> &value)
  {
    std::cout << "UpdateCharacteristic called" << std::endl;
    return std::nullopt;
  }

} // namespace ble_peripheral

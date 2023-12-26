#include "ble_peripheral_plugin.h"
#include <windows.h>
#include <flutter/plugin_registrar_windows.h>
#include <map>
#include <memory>
#include <sstream>
#include <algorithm>
#include <iomanip>
#include <thread>
#include <regex>
#include "Utils.h"

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
    bluetoothLEPublisher.StatusChanged([this](auto &&, auto &&)
                                       {
                                         std::cout << "AdvertisingStatusChanged" << std::endl;
                                         //  auto status = bluetoothLEPublisher.Status();
                                         //  bleCallback->OnAdvertisingStarted(nullptr, SuccessCallback, ErrorCallback);
                                       });
  }

  std::optional<FlutterError> BlePeripheralPlugin::Initialize()
  {
    InitializeAdapter();
    return std::nullopt;
  }

  ErrorOr<std::optional<bool>> BlePeripheralPlugin::IsAdvertising()
  {
    auto status = bluetoothLEPublisher.Status();
    return ErrorOr<std::optional<bool>>(status == BluetoothLEAdvertisementPublisherStatus::Started);
  }

  ErrorOr<bool> BlePeripheralPlugin::IsSupported()
  {
    return bluetoothLEPublisher != nullptr;
  }

  ErrorOr<bool> BlePeripheralPlugin::AskBlePermission()
  {
    std::cout << "AskBlePermission called" << std::endl;
    return true;
  };

  std::optional<FlutterError> BlePeripheralPlugin::AddService(const BleService &service)
  {
    auto serviceUuid = service.uuid();
    std::cout << "Adding service " << serviceUuid << std::endl;
    bluetoothLEPublisher.Advertisement().ServiceUuids().Append(uuid_to_guid(serviceUuid));
    bleCallback->OnServiceAdded(serviceUuid, nullptr, SuccessCallback, ErrorCallback);
    return std::nullopt;
  };

  std::optional<FlutterError> BlePeripheralPlugin::StartAdvertising(
      const flutter::EncodableList &services,
      const std::string &local_name,
      const int64_t *timeout,
      const ManufacturerData *manufacturer_data,
      bool add_manufacturer_data_in_scan_response)
  {
    // Advertisement::BluetoothLEManufacturerData manufacturerData = Advertisement::BluetoothLEManufacturerData();
    // manufacturerData.CompanyId(0xFFFE);
    // advertisement.ManufacturerData().Append(manufacturerData);
    BluetoothLEAdvertisement advertisement = bluetoothLEPublisher.Advertisement();
    advertisement.Flags(BluetoothLEAdvertisementFlags::GeneralDiscoverableMode);

    bluetoothLEPublisher.Start();
    advertising = true;
    std::cout << "StartAdvertising called" << std::endl;
    return std::nullopt;
  }

  std::optional<FlutterError> BlePeripheralPlugin::StopAdvertising()
  {
    std::cout << "StopAdvertising called" << std::endl;
    // bluetoothLEPublisher.Advertisement().ManufacturerData().Clear();
    bluetoothLEPublisher.Stop();
    advertising = false;
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

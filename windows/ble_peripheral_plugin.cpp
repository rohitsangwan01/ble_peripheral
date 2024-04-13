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
  std::vector<BleService> bleAddedServices = {};

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
  }

  std::optional<FlutterError> BlePeripheralPlugin::Initialize()
  {
    InitializeAdapter();
    return std::nullopt;
  };

  ErrorOr<std::optional<bool>> BlePeripheralPlugin::IsAdvertising()
  {
    return ErrorOr<std::optional<bool>>(std::optional<bool>(advertising));
  };

  ErrorOr<bool> BlePeripheralPlugin::IsSupported()
  {
    return true;
  };

  ErrorOr<bool> BlePeripheralPlugin::AskBlePermission()
  {
    std::cout << "AskBlePermission called" << std::endl;
    return true;
  };

  std::optional<FlutterError> BlePeripheralPlugin::AddService(const BleService &service)
  {
    AddServiceAsync(service);
    return std::nullopt;
  };

  std::optional<FlutterError> BlePeripheralPlugin::RemoveService(const std::string &service_id)
  {
    std::cout << "RemoveService called" << std::endl;
    return std::nullopt;
  }

  std::optional<FlutterError> BlePeripheralPlugin::ClearServices()
  {
    std::cout << "ClearServices called" << std::endl;
    return std::nullopt;
  }

  ErrorOr<flutter::EncodableList> BlePeripheralPlugin::GetServices()
  {
    std::cout << "GetServices called" << std::endl;
    return ErrorOr<flutter::EncodableList>(flutter::EncodableList());
  }

  std::optional<FlutterError> BlePeripheralPlugin::StartAdvertising(
      const flutter::EncodableList &services,
      const std::string &local_name,
      const int64_t *timeout,
      const ManufacturerData *manufacturer_data,
      bool add_manufacturer_data_in_scan_response)
  {
    try
    {
      std::cout << "StartAdvertising called" << std::endl;

      auto advertisementParameter = GattServiceProviderAdvertisingParameters();
      advertisementParameter.IsDiscoverable(true);
      advertisementParameter.IsConnectable(true);

      for (BleService service : bleAddedServices)
      {
        auto serviceUuid = service.uuid();
        auto serviceProviderResult = async_get(GattServiceProvider::CreateAsync(uuid_to_guid(serviceUuid)));
        auto serviceProvider = serviceProviderResult.ServiceProvider();
        std::cout << "Adding service " << serviceUuid << std::endl;
        serviceProvider.AdvertisementStatusChanged([this, serviceUuid](auto &&, auto &&)
                                                   { std::cout << "AdvertisingStatusChanged " << serviceUuid << std::endl; });

        serviceProvider.StartAdvertising(advertisementParameter);
      }

      advertising = true;
      std::cout << "StartAdvertising called" << std::endl;
      return std::nullopt;
    }
    catch (const winrt::hresult_error &e)
    {
      std::wcerr << "Failed with error: Code: " << e.code() << "Message: " << e.message().c_str() << std::endl;
      return std::nullopt;
    }
    catch (const std::exception &e)
    {
      std::cout << "Error: " << e.what() << std::endl;
      return std::nullopt;
    }
    catch (...)
    {
      std::cout << "Error: "
                << "Unknown error" << std::endl;
      return std::nullopt;
    }
  }

  std::optional<FlutterError> BlePeripheralPlugin::StopAdvertising()
  {

    std::cout << "StopAdvertising called" << std::endl;
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

  // Helpers
  winrt::fire_and_forget BlePeripheralPlugin::AddServiceAsync(const BleService &service)
  {
    auto serviceUuid = service.uuid();
    try
    {
      // Build Service
      std::cout << "Adding service " << serviceUuid << std::endl;
      auto characteristics = service.characteristics();

      auto serviceProviderResult = co_await GattServiceProvider::CreateAsync(uuid_to_guid(serviceUuid));
      if (serviceProviderResult.Error() != BluetoothError::Success)
      {
        std::string *err = new std::string(winrt::to_string(L"Failed to create service provider: " + static_cast<int>(serviceProviderResult.Error())));
        bleCallback->OnServiceAdded(serviceUuid, err, SuccessCallback, ErrorCallback);
        co_return;
      }
      auto serviceProvider = serviceProviderResult.ServiceProvider();

      // Build Characteristic
      for (auto characteristicEncoded : characteristics)
      {
        BleCharacteristic characteristic = std::any_cast<BleCharacteristic>(std::get<flutter::CustomEncodableValue>(characteristicEncoded));
        flutter::EncodableList descriptors = characteristic.descriptors() == nullptr ? flutter::EncodableList() : *characteristic.descriptors();

        auto charParameters = GattLocalCharacteristicParameters();
        auto characteristicUuid = characteristic.uuid();

        // Add characteristic properties
        auto charProperties = characteristic.properties();
        for (flutter::EncodableValue propertyEncoded : charProperties)
        {
          auto property = std::get<int>(propertyEncoded);
          charParameters.CharacteristicProperties(charParameters.CharacteristicProperties() | toGattCharacteristicProperties(property));
        }

        // Add characteristic permissions
        auto charPermissions = characteristic.permissions();
        for (flutter::EncodableValue permissionEncoded : charPermissions)
        {
          auto blePermission = toBlePermission(std::get<int>(permissionEncoded));
          switch (blePermission)
          {
          case BlePermission::readable:
            charParameters.ReadProtectionLevel(GattProtectionLevel::Plain);
            break;
          case BlePermission::writeable:
            charParameters.WriteProtectionLevel(GattProtectionLevel::Plain);
            break;
          case BlePermission::readEncryptionRequired:
            charParameters.ReadProtectionLevel(GattProtectionLevel::EncryptionRequired);
            break;
          case BlePermission::writeEncryptionRequired:
            charParameters.WriteProtectionLevel(GattProtectionLevel::EncryptionRequired);
            break;
          }
        }

        auto characteristicResult = co_await serviceProvider.Service().CreateCharacteristicAsync(uuid_to_guid(characteristicUuid), charParameters);
        if (characteristicResult.Error() != BluetoothError::Success)
        {
          std::wcerr << "Failed to create Char Provider: " << std::endl;
          co_return;
        }
        auto gattCharacteristic = characteristicResult.Characteristic();

        // Build Descriptors
        for (flutter::EncodableValue descriptorEncoded : descriptors)
        {
          BleDescriptor descriptor = std::any_cast<BleDescriptor>(std::get<flutter::CustomEncodableValue>(descriptorEncoded));
          auto descriptorUuid = descriptor.uuid();
          auto descriptorParameters = GattLocalDescriptorParameters();

          //  Add descriptor permissions
          flutter::EncodableList descriptorPermissions = descriptor.permissions() == nullptr ? flutter::EncodableList() : *descriptor.permissions();
          for (flutter::EncodableValue permissionsEncoded : descriptorPermissions)
          {
            auto blePermission = toBlePermission(std::get<int>(permissionsEncoded));
            switch (blePermission)
            {
            case BlePermission::readable:
              descriptorParameters.ReadProtectionLevel(GattProtectionLevel::Plain);
              break;
            case BlePermission::writeable:
              descriptorParameters.WriteProtectionLevel(GattProtectionLevel::Plain);
              break;
            case BlePermission::readEncryptionRequired:
              descriptorParameters.ReadProtectionLevel(GattProtectionLevel::EncryptionRequired);
              break;
            case BlePermission::writeEncryptionRequired:
              descriptorParameters.WriteProtectionLevel(GattProtectionLevel::EncryptionRequired);
              break;
            }
          }

          auto descriptorResult = co_await gattCharacteristic.CreateDescriptorAsync(uuid_to_guid(descriptorUuid), descriptorParameters);
          if (descriptorResult.Error() != BluetoothError::Success)
          {
            std::wcerr << "Failed to create Descriptor Provider: " << std::endl;
            co_return;
          }
          auto gattDescriptor = descriptorResult.Descriptor();

          // Add descriptor value: FIXME
          // auto descriptorValue = descriptor.value();
          // if (descriptorValue != nullptr)
          // {
          //   auto writer = DataWriter();
          //   winrt::array_view<const uint8_t> view(descriptorValue->data(), descriptorValue->data() + descriptorValue->size());
          //   writer.WriteBytes(view);
          //   auto descriptorValueResult = co_await gattDescriptor.WriteValueAsync(writer.DetachBuffer());
          //   if (descriptorValueResult.Status() != GattCommunicationStatus::Success)
          //   {
          //     std::wcerr << "Failed to write descriptor value: " << std::endl;
          //     co_return;
          //   }
          // }
        }
      }
      //  bleAddedServices.push_back(service);

      serviceProvider.StartAdvertising(GattServiceProviderAdvertisingParameters());
      serviceProvider.AdvertisementStatusChanged([this, serviceUuid](auto &&, auto &&)
                                                 { std::cout << "AdvertisingStatusChanged " << serviceUuid << std::endl; });
      bleCallback->OnServiceAdded(serviceUuid, nullptr, SuccessCallback, ErrorCallback);
      std::cout << "Service added" << std::endl;
    }
    catch (const winrt::hresult_error &e)
    {
      std::wcerr << "Failed with error: Code: " << e.code() << "Message: " << e.message().c_str() << std::endl;
      std::string errorMessage = winrt::to_string(e.message());
      bleCallback->OnServiceAdded(serviceUuid, &errorMessage, SuccessCallback, ErrorCallback);
    }
    catch (const std::exception &e)
    {
      std::cout << "Error: " << e.what() << std::endl;
      std::wstring errorMessage = winrt::to_hstring(e.what()).c_str();
      std::string *err = new std::string(winrt::to_string(errorMessage));
      bleCallback->OnServiceAdded(serviceUuid, err, SuccessCallback, ErrorCallback);
    }
    catch (...)
    {
      std::cout << "Error: Unknown error" << std::endl;
      std::string *err = new std::string(winrt::to_string(L"Unknown error"));
      bleCallback->OnServiceAdded(serviceUuid, err, SuccessCallback, ErrorCallback);
    }
  }

  GattCharacteristicProperties BlePeripheralPlugin::toGattCharacteristicProperties(int property)
  {
    switch (property)
    {
    case 0:
      return GattCharacteristicProperties::Broadcast;
    case 1:
      return GattCharacteristicProperties::Read;
    case 2:
      return GattCharacteristicProperties::WriteWithoutResponse;
    case 3:
      return GattCharacteristicProperties::Write;
    case 4:
      return GattCharacteristicProperties::Notify;
    case 5:
      return GattCharacteristicProperties::Indicate;
    case 6:
      return GattCharacteristicProperties::AuthenticatedSignedWrites;
    case 7:
      return GattCharacteristicProperties::ExtendedProperties;
    case 8:
      return GattCharacteristicProperties::Notify;
    case 9:
      return GattCharacteristicProperties::Indicate;
    default:
      return GattCharacteristicProperties::None;
    }
  }

  // Check if these permissions are correct
  BlePermission BlePeripheralPlugin::toBlePermission(int permission)
  {
    switch (permission)
    {
    case 0:
      return BlePermission::readable;
    case 1:
      return BlePermission::writeable;
    case 2:
      return BlePermission::readEncryptionRequired;
    case 3:
      return BlePermission::writeEncryptionRequired;
    default:
      return BlePermission::none;
    }
  }

} // namespace ble_peripheral

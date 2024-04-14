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
  std::map<std::string, GattServiceProviderObject *> serviceProviderMap;

  // static
  void BlePeripheralPlugin::RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar)
  {
    auto plugin = std::make_unique<BlePeripheralPlugin>(registrar);
    BlePeripheralChannel::SetUp(registrar->messenger(), plugin.get());
    bleCallback = std::make_unique<BleCallback>(registrar->messenger());
    registrar->AddPlugin(std::move(plugin));
  }

  BlePeripheralPlugin::BlePeripheralPlugin(flutter::PluginRegistrarWindows *registrar) : uiThreadHandler_(registrar) {}

  BlePeripheralPlugin::~BlePeripheralPlugin() {}

  winrt::fire_and_forget BlePeripheralPlugin::InitializeAdapter()
  {
    auto radios = co_await Radio::GetRadiosAsync();
    for (auto &&radio : radios)
    {
      if (radio.Kind() == RadioKind::Bluetooth)
      {
        bluetoothRadio = radio;
        radioStateChangedRevoker = bluetoothRadio.StateChanged(winrt::auto_revoke, {this, &BlePeripheralPlugin::Radio_StateChanged});
        bool isOn = bluetoothRadio.State() == RadioState::On;
        uiThreadHandler_.Post([isOn]
                              { bleCallback->OnBleStateChange(isOn, SuccessCallback, ErrorCallback); });

        break;
      }
    }
    if (!bluetoothRadio)
    {
      std::cout << "Bluetooth is not available" << std::endl;
    }
  }

  std::optional<FlutterError> BlePeripheralPlugin::Initialize()
  {
    InitializeAdapter();
    return std::nullopt;
  };

  ErrorOr<std::optional<bool>> BlePeripheralPlugin::IsAdvertising()
  {
    // Check is any service is advertising, or if services list is empty
    // Get serviceProviderMap length
    if (serviceProviderMap.size() == 0)
      return ErrorOr<std::optional<bool>>(std::optional<bool>(false));

    bool advertising = true;
    for (auto const &[key, gattServiceObject] : serviceProviderMap)
    {
      if (gattServiceObject->lastStatus != GattServiceProviderAdvertisementStatus::Started)
      {
        advertising = false;
        break;
      }
    }
    return ErrorOr<std::optional<bool>>(std::optional<bool>(advertising));
  };

  ErrorOr<bool> BlePeripheralPlugin::IsSupported()
  {
    return bluetoothRadio != nullptr;
  };

  ErrorOr<bool> BlePeripheralPlugin::AskBlePermission()
  {
    // No need to ask permission on Windows
    return true;
  };

  std::optional<FlutterError> BlePeripheralPlugin::AddService(const BleService &service)
  {
    AddServiceAsync(service);
    return std::nullopt;
  };

  std::optional<FlutterError> BlePeripheralPlugin::RemoveService(const std::string &service_id)
  {
    // lower case the service_id
    std::string serviceId = service_id;
    std::transform(serviceId.begin(), serviceId.end(), serviceId.begin(),
                   [](unsigned char c) -> char
                   { return static_cast<char>(std::tolower(c)); });

    if (serviceProviderMap.find(serviceId) == serviceProviderMap.end())
    {
      std::cout << "Service not found in map" << std::endl;
      return FlutterError("Service not found");
    }
    auto gattServiceObject = serviceProviderMap[serviceId];
    disposeGattServiceObject(gattServiceObject);
    serviceProviderMap.erase(serviceId);
    return std::nullopt;
  }

  std::optional<FlutterError> BlePeripheralPlugin::ClearServices()
  {
    for (auto const &[key, gattServiceObject] : serviceProviderMap)
    {
      disposeGattServiceObject(gattServiceObject);
    }
    // Clear map
    serviceProviderMap.clear();
    return std::nullopt;
  }

  ErrorOr<flutter::EncodableList> BlePeripheralPlugin::GetServices()
  {
    flutter::EncodableList services = flutter::EncodableList();
    for (auto const &[key, gattServiceObject] : serviceProviderMap)
    {
      services.push_back(flutter::EncodableValue(key));
    }
    return services;
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
      // check if services are empty
      if (serviceProviderMap.size() == 0)
        return FlutterError("No services added to advertise");

      auto advertisementParameter = GattServiceProviderAdvertisingParameters();
      advertisementParameter.IsDiscoverable(true);
      advertisementParameter.IsConnectable(true);

      for (auto const &[key, gattServiceObject] : serviceProviderMap)
      {
        if (gattServiceObject->obj.AdvertisementStatus() == GattServiceProviderAdvertisementStatus::Started)
        {
          std::cout << "Service " << key << " is already advertising, skipping" << std::endl;
          continue;
        }
        gattServiceObject->obj.StartAdvertising(advertisementParameter);
      }

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
    for (auto const &[key, gattServiceObject] : serviceProviderMap)
    {
      if (gattServiceObject->obj.AdvertisementStatus() != GattServiceProviderAdvertisementStatus::Started)
      {
        std::cout << "Service " << key << " is not advertising, skipping" << std::endl;
        continue;
      }
      gattServiceObject->obj.StopAdvertising();
    }

    uiThreadHandler_.Post([]
                          { bleCallback->OnAdvertisingStatusUpdate(false, nullptr, SuccessCallback, ErrorCallback); });

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
      auto characteristics = service.characteristics();
      auto gattCharacteristicObjList = std::map<std::string, GattCharacteristicObject>();

      auto serviceProviderResult = co_await GattServiceProvider::CreateAsync(uuid_to_guid(serviceUuid));
      if (serviceProviderResult.Error() != BluetoothError::Success)
      {
        std::string *err = new std::string(winrt::to_string(L"Failed to create service provider: " + static_cast<int>(serviceProviderResult.Error())));
        bleCallback->OnServiceAdded(serviceUuid, err, SuccessCallback, ErrorCallback);
        co_return;
      }

      GattServiceProvider serviceProvider = serviceProviderResult.ServiceProvider();

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

        auto gattCharacteristicObject = GattCharacteristicObject();
        gattCharacteristicObject.obj = gattCharacteristic;

        gattCharacteristicObject.read_requested_token = gattCharacteristic.ReadRequested({this, &BlePeripheralPlugin::ReadRequestedAsync});
        gattCharacteristicObject.write_requested_token = gattCharacteristic.WriteRequested({this, &BlePeripheralPlugin::WriteRequestedAsync});
        gattCharacteristicObject.value_changed_token = gattCharacteristic.SubscribedClientsChanged({this, &BlePeripheralPlugin::SubscribedClientsChanged});

        gattCharacteristicObjList.insert_or_assign(characteristicUuid, gattCharacteristicObject);
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

      GattServiceProviderObject *gattServiceProviderObject = new GattServiceProviderObject();
      gattServiceProviderObject->obj = serviceProvider;
      gattServiceProviderObject->characteristics = gattCharacteristicObjList;
      gattServiceProviderObject->advertisement_status_changed_token = serviceProvider.AdvertisementStatusChanged({this, &BlePeripheralPlugin::ServiceProvider_AdvertisementStatusChanged});
      gattServiceProviderObject->lastStatus = serviceProvider.AdvertisementStatus();
      serviceProviderMap.insert_or_assign(guid_to_uuid(serviceProvider.Service().Uuid()), gattServiceProviderObject);

      uiThreadHandler_.Post([serviceUuid]
                            { bleCallback->OnServiceAdded(serviceUuid, nullptr, SuccessCallback, ErrorCallback); });
    }
    catch (const winrt::hresult_error &e)
    {
      std::wcerr << "Failed with error: Code: " << e.code() << "Message: " << e.message().c_str() << std::endl;
      std::string errorMessage = winrt::to_string(e.message());

      uiThreadHandler_.Post([serviceUuid, errorMessage]
                            { bleCallback->OnServiceAdded(serviceUuid, &errorMessage, SuccessCallback, ErrorCallback); });
    }
    catch (const std::exception &e)
    {
      std::cout << "Error: " << e.what() << std::endl;
      std::wstring errorMessage = winrt::to_hstring(e.what()).c_str();
      std::string *err = new std::string(winrt::to_string(errorMessage));
      uiThreadHandler_.Post([serviceUuid, err]
                            { bleCallback->OnServiceAdded(serviceUuid, err, SuccessCallback, ErrorCallback); });
    }
    catch (...)
    {
      std::cout << "Error: Unknown error" << std::endl;
      std::string *err = new std::string(winrt::to_string(L"Unknown error"));
      uiThreadHandler_.Post([serviceUuid, err]
                            { bleCallback->OnServiceAdded(serviceUuid, err, SuccessCallback, ErrorCallback); });
    }
  }

  /// Handlers
  void BlePeripheralPlugin::ServiceProvider_AdvertisementStatusChanged(GattServiceProvider const &sender, GattServiceProviderAdvertisementStatusChangedEventArgs const &)
  {
    auto serviceUuid = guid_to_uuid(sender.Service().Uuid());

    for (auto const &[key, gattServiceObject] : serviceProviderMap)
    {
      // if last state is Created and current is aborted then ignore this
      if (serviceUuid == key)
      {
        if (gattServiceObject->lastStatus == GattServiceProviderAdvertisementStatus::Created && sender.AdvertisementStatus() == GattServiceProviderAdvertisementStatus::Aborted)
          return;
        else
          gattServiceObject->lastStatus = sender.AdvertisementStatus();
        auto statusStr = AdvertisementStatusToString(sender.AdvertisementStatus());
        std::cout << "AdvertisingStatusChanged " << serviceUuid << "AdvertisingStatus " << statusStr << " /n " << std::endl;
        break;
      }
    }

    // Check if all services started
    bool allServicesStarted = true;
    for (auto const &[key, gattServiceObject] : serviceProviderMap)
    {
      if (gattServiceObject->lastStatus != GattServiceProviderAdvertisementStatus::Started)
      {
        allServicesStarted = false;
        break;
      };
    }

    // Notify Flutter
    if (allServicesStarted)
    {
      uiThreadHandler_.Post([]
                            { bleCallback->OnAdvertisingStatusUpdate(true, nullptr, SuccessCallback, ErrorCallback); });
    }
  }

  void BlePeripheralPlugin::SubscribedClientsChanged(GattLocalCharacteristic const &sender, IInspectable const &)
  {
  }

  winrt::fire_and_forget BlePeripheralPlugin::ReadRequestedAsync(GattLocalCharacteristic const &localChar, GattReadRequestedEventArgs args)
  {
    auto deferral = args.GetDeferral();
    auto request = co_await args.GetRequestAsync();
    if (request == nullptr)
    {
      // No access allowed to the device.  Application should indicate this to the user.
      std::cout << "No access allowed to the device" << std::endl;
      deferral.Complete();
      co_return;
    }

    uiThreadHandler_.Post([localChar, request, deferral]
                          {
                          auto characteristicId = guid_to_uuid(localChar.Uuid());
                          auto deviceId = ""; // FIXME: Device id is not available
                          int64_t offset = request.Offset();
                          // FIXME: static value is always empty
                          IBuffer charValue = localChar.StaticValue();
                          std::vector<uint8_t> *value_arg = nullptr;
                          if (charValue != nullptr)
                          {
                            auto bytevc = to_bytevc(charValue);
                            value_arg = &bytevc;
                          }
                          bleCallback->OnReadRequest(
                                deviceId,characteristicId, offset,value_arg,
                                // SuccessCallback,
                                [deferral, request, localChar](const ReadRequestResult *readResult)
                                {
                                  if (readResult == nullptr)
                                  {
                                    std::cout << "ReadRequestResult is null" << std::endl;
                                    request.RespondWithProtocolError(GattProtocolError::InvalidHandle());
                                  }
                                  else
                                  {
                                    // FIXME: use offset as well
                                    std::vector<uint8_t> resultVal = readResult->value();
                                    IBuffer result = from_bytevc(resultVal);

                                    // Send response
                                    DataWriter writer;
                                    writer.ByteOrder(ByteOrder::LittleEndian);
                                    writer.WriteBuffer(result);
                                    request.RespondWithValue(writer.DetachBuffer());
                                  }
                                  deferral.Complete();
                                },
                                // ErrorCallback
                                [deferral](const FlutterError &error)
                                {
                                  std::cout << "ErrorCallback: " << error.message() << std::endl;
                                  deferral.Complete();
                                }); });
  }

  winrt::fire_and_forget BlePeripheralPlugin::WriteRequestedAsync(GattLocalCharacteristic const &localChar, GattWriteRequestedEventArgs args)
  {
    auto deferral = args.GetDeferral();
    GattWriteRequest request = co_await args.GetRequestAsync();
    if (request == nullptr)
    {
      std::cout << "No access allowed to the device" << std::endl;
      deferral.Complete();
      co_return;
    }

    uiThreadHandler_.Post([localChar, request, deferral]
                          {
                            auto characteristicId = guid_to_uuid(localChar.Uuid());
                            auto deviceId = ""; // FIXME: Device id is not available
                            int64_t offset = request.Offset();
                            auto bytevc = to_bytevc(request.Value());
                            std::vector<uint8_t> *value_arg = &bytevc;

                            bleCallback->OnWriteRequest(
                                deviceId, characteristicId, offset, value_arg,
                                // SuccessCallback
                                [deferral, request, localChar](const WriteRequestResult *writeResult)
                                {
                                  // respond with error if status is not null,
                                  // FIXME: parse proper error
                                  if (writeResult->status() != nullptr)
                                    request.RespondWithProtocolError(GattProtocolError::InvalidHandle());
                                  else
                                    request.Respond();
                                  deferral.Complete();
                                },
                                // ErrorCallback
                                [deferral](const FlutterError &error)
                                {
                                  std::cout << "ErrorCallback: " << error.message() << std::endl;
                                  deferral.Complete();
                                });

                            // Write Request
                          });
  }

  void BlePeripheralPlugin::disposeGattServiceObject(GattServiceProviderObject *gattServiceObject)
  {
    try
    {
      auto serviceId = guid_to_uuid(gattServiceObject->obj.Service().Uuid());
      // check if serviceMap have this uuid
      if (serviceProviderMap.find(serviceId) == serviceProviderMap.end())
      {
        std::cout << "Service not found in map" << std::endl;
        return;
      }
      std::cout << "Cleaning service: " << serviceId << std::endl;
      // clean resources for this service
      gattServiceObject->obj.AdvertisementStatusChanged(gattServiceObject->advertisement_status_changed_token);

      // Stop advertising if started
      if (gattServiceObject->obj.AdvertisementStatus() == GattServiceProviderAdvertisementStatus::Started)
      {
        gattServiceObject->obj.StopAdvertising();
      };

      // clean resources for characteristics
      for (auto const &[chatKey, gattCharacteristicObject] : gattServiceObject->characteristics)
      {
        gattCharacteristicObject.obj.ReadRequested(gattCharacteristicObject.read_requested_token);
        gattCharacteristicObject.obj.WriteRequested(gattCharacteristicObject.write_requested_token);
        gattCharacteristicObject.obj.SubscribedClientsChanged(gattCharacteristicObject.value_changed_token);
      }
    }
    catch (const winrt::hresult_error &e)
    {
      std::wcerr << "Failed with error: Code: " << e.code() << "Message: " << e.message().c_str() << std::endl;
    }
    catch (const std::exception &e)
    {
      std::cout << "Error: " << e.what() << std::endl;
    }
    catch (...)
    {
      std::cout << "Error: Unknown error" << std::endl;
    }
  }

  void BlePeripheralPlugin::Radio_StateChanged(Radio radio, IInspectable args)
  {
    auto radioState = !radio ? RadioState::Disabled : radio.State();
    if (oldRadioState == radioState)
    {
      return;
    }
    oldRadioState = radioState;
    bleCallback->OnBleStateChange(radioState == RadioState::On, SuccessCallback, ErrorCallback);
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

  std::string BlePeripheralPlugin::AdvertisementStatusToString(GattServiceProviderAdvertisementStatus status)
  {
    switch (status)
    {
    case GattServiceProviderAdvertisementStatus::Created:
      return "Created";
    case GattServiceProviderAdvertisementStatus::Started:
      return "Started";
    case GattServiceProviderAdvertisementStatus::Stopped:
      return "Stopped";
    case GattServiceProviderAdvertisementStatus::Aborted:
      return "Aborted";
    case GattServiceProviderAdvertisementStatus::StartedWithoutAllAdvertisementData:
      return "StartedWithoutAllAdvertisementData";
    default:
      return "Unknown";
    }
  }
} // namespace ble_peripheral

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
  std::mutex cout_mutex;

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
    bool advertising = AreAllServicesStarted();
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
    std::string serviceId = to_lower_case(service_id);
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
      const std::string* local_name,
      const int64_t *timeout,
      const ManufacturerData *manufacturer_data,
      bool add_manufacturer_data_in_scan_response)
  {
    try
    {
      // check if services are empty
      if (serviceProviderMap.size() == 0)
        return FlutterError("No services added to advertise");

      if (AreAllServicesStarted())
      {
        std::cout << "All services already advertising" << std::endl;
        uiThreadHandler_.Post([]
                              { bleCallback->OnAdvertisingStatusUpdate(true, nullptr, SuccessCallback, ErrorCallback); });
        return std::nullopt;
      }

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
      try
      {
        gattServiceObject->obj.StopAdvertising();
        std::cout << "Stopped advertising for service: " << key << std::endl;
      }
      catch (const winrt::hresult_error &e)
      {
        std::wcerr << "Failed to stop service: " << key.c_str() << ", Error: " << e.message().c_str() << std::endl;
      }
      catch (...)
      {
        std::cout << "Error: Unknown error" << std::endl;
      }
    }
    uiThreadHandler_.Post([]
                          { bleCallback->OnAdvertisingStatusUpdate(false, nullptr, SuccessCallback, ErrorCallback); });
    return std::nullopt;
  }

  std::optional<FlutterError> BlePeripheralPlugin::UpdateCharacteristic(
      const std::string& characteristic_id,
      const std::vector<uint8_t>& value,
      const std::string* device_id)
  {
    GattCharacteristicObject *gattCharacteristicObject = FindGattCharacteristicObject(characteristic_id);
    if (gattCharacteristicObject == nullptr)
      return FlutterError("Failed to get this characteristic");

    IBuffer bytes = from_bytevc(value);
    DataWriter writer;
    writer.ByteOrder(ByteOrder::LittleEndian);
    writer.WriteBuffer(bytes);
    gattCharacteristicObject->obj.NotifyValueAsync(writer.DetachBuffer());
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
      auto gattCharacteristicObjList = std::map<std::string, GattCharacteristicObject *>();

      auto serviceProviderResult = co_await GattServiceProvider::CreateAsync(uuid_to_guid(serviceUuid));
      if (serviceProviderResult.Error() != BluetoothError::Success)
      {
        std::string bleError = ParseBluetoothError(serviceProviderResult.Error());
        std::string err = "Failed to create service provider: " + serviceUuid + ", errorCode: " + bleError;
        std::cout << err << std::endl;
        bleCallback->OnServiceAdded(serviceUuid, &err, SuccessCallback, ErrorCallback);
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

        const std::vector<uint8_t> *characteristicValue = characteristic.value();
        if (characteristicValue != nullptr)
        {
          auto characteristicBytes = from_bytevc(*characteristicValue);
          charParameters.StaticValue(characteristicBytes);
        }

        auto characteristicResult = co_await serviceProvider.Service().CreateCharacteristicAsync(uuid_to_guid(characteristicUuid), charParameters);
        if (characteristicResult.Error() != BluetoothError::Success)
        {
          std::wcerr << "Failed to create Char Provider: " << std::endl;
          co_return;
        }
        auto gattCharacteristic = characteristicResult.Characteristic();

        auto gattCharacteristicObject = new GattCharacteristicObject();
        gattCharacteristicObject->obj = gattCharacteristic;
        gattCharacteristicObject->stored_clients = gattCharacteristic.SubscribedClients();

        gattCharacteristicObject->read_requested_token = gattCharacteristic.ReadRequested({this, &BlePeripheralPlugin::ReadRequestedAsync});
        gattCharacteristicObject->write_requested_token = gattCharacteristic.WriteRequested({this, &BlePeripheralPlugin::WriteRequestedAsync});
        gattCharacteristicObject->value_changed_token = gattCharacteristic.SubscribedClientsChanged({this, &BlePeripheralPlugin::SubscribedClientsChanged});

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
          const std::vector<uint8_t> *descriptorValue = descriptor.value();
          if (descriptorValue != nullptr)
          {
            auto descriptorBytes = from_bytevc(*descriptorValue);
            descriptorParameters.StaticValue(descriptorBytes);
          }
          auto descriptorResult = co_await gattCharacteristic.CreateDescriptorAsync(uuid_to_guid(descriptorUuid), descriptorParameters);
          if (descriptorResult.Error() != BluetoothError::Success)
          {
            std::wcerr << "Failed to create Descriptor Provider: " << std::endl;
            co_return;
          }
          GattLocalDescriptor gattDescriptor = descriptorResult.Descriptor();
        }

        gattCharacteristicObjList.insert_or_assign(guid_to_uuid(gattCharacteristic.Uuid()), gattCharacteristicObject);
      }

      GattServiceProviderObject *gattServiceProviderObject = new GattServiceProviderObject();
      gattServiceProviderObject->obj = serviceProvider;
      gattServiceProviderObject->characteristics = gattCharacteristicObjList;
      gattServiceProviderObject->advertisement_status_changed_token = serviceProvider.AdvertisementStatusChanged({this, &BlePeripheralPlugin::ServiceProvider_AdvertisementStatusChanged});
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

  /// Advertisements Listener
  void BlePeripheralPlugin::ServiceProvider_AdvertisementStatusChanged(GattServiceProvider const &sender, GattServiceProviderAdvertisementStatusChangedEventArgs const &args)
  {
    std::lock_guard<std::mutex> lock(cout_mutex);
    auto serviceUuid = guid_to_uuid(sender.Service().Uuid());
    if (args.Error() != BluetoothError::Success)
    {
      std::string errorStr = ParseBluetoothError(args.Error());
      std::cout << "AdvertisementStatusChanged " << serviceUuid << ", Error " << errorStr << std::endl;

      uiThreadHandler_.Post([errorStr]
                            { bleCallback->OnAdvertisingStatusUpdate(false, &errorStr, SuccessCallback, ErrorCallback); });
      return;
    }

    auto argStatus = args.Status();
    auto statusStr = AdvertisementStatusToString(argStatus);
    std::cout << "AdvertisingStatus of service " << serviceUuid << ", changed to " << statusStr << " " << std::endl;

    // Check if all services started
    if (AreAllServicesStarted())
    {
      uiThreadHandler_.Post([]
                            { bleCallback->OnAdvertisingStatusUpdate(true, nullptr, SuccessCallback, ErrorCallback); });
    }
  }

  /// Characteristic Listeners
  void BlePeripheralPlugin::SubscribedClientsChanged(GattLocalCharacteristic const &localChar, IInspectable const &)
  {
    auto characteristicId = guid_to_uuid(localChar.Uuid());

    // Find GattCharacteristicObject
    GattCharacteristicObject *gattCharacteristicObject = FindGattCharacteristicObject(characteristicId);

    if (gattCharacteristicObject == nullptr)
    {
      std::cout << "Failed to get char " << characteristicId << std::endl;
      return;
    }

    // Compare Stored clients and New clients
    IVectorView<GattSubscribedClient> currentClients = localChar.SubscribedClients();
    IVectorView<GattSubscribedClient> oldClients = gattCharacteristicObject->stored_clients;

    // Check if any client removed
    for (unsigned int i = 0; i < oldClients.Size(); ++i)
    {
      auto oldClient = oldClients.GetAt(i);
      bool found = false;
      for (unsigned int j = 0; j < currentClients.Size(); ++j)
      {
        if (currentClients.GetAt(j) == oldClient)
        {
          found = true;
          break;
        }
      }
      if (!found)
      {
        // oldClient is not in currentClients, so it was removed
        std::string deviceIdArg = ParseBluetoothClientId(oldClient.Session().DeviceId().Id());
        uiThreadHandler_.Post([deviceIdArg, characteristicId]
                              {
                                bleCallback->OnCharacteristicSubscriptionChange(
                                    deviceIdArg, characteristicId, false,
                                    SuccessCallback, ErrorCallback);
                                // Notify subscription change
                              });
      }
    }

    // Check if any client added
    for (unsigned int i = 0; i < currentClients.Size(); ++i)
    {
      auto currentClient = currentClients.GetAt(i);
      bool found = false;
      for (unsigned int j = 0; j < oldClients.Size(); ++j)
      {
        if (oldClients.GetAt(j) == currentClient)
        {
          found = true;
          break;
        }
      }
      if (!found)
      {
        // currentClient is not in oldClients, so it was added
        std::string deviceIdArg = ParseBluetoothClientId(currentClient.Session().DeviceId().Id());
        uiThreadHandler_.Post([deviceIdArg, characteristicId]
                              {
                                bleCallback->OnCharacteristicSubscriptionChange(
                                    deviceIdArg, characteristicId, true,
                                    SuccessCallback, ErrorCallback);
                                // Notify subscription change
                              });

        int64_t maxPuid = currentClient.Session().MaxPduSize();
        uiThreadHandler_.Post([deviceIdArg, maxPuid]
                              {
                                bleCallback->OnMtuChange(deviceIdArg, maxPuid,
                                                         SuccessCallback, ErrorCallback);
                                // Notify added device MTU change
                              });
      }
    }

    // Update stored clients in stored char
    gattCharacteristicObject->stored_clients = currentClients;
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

    std::string deviceId = ParseBluetoothClientId(args.Session().DeviceId().Id());

    uiThreadHandler_.Post([localChar, request, deferral, deviceId]
                          {
                          auto characteristicId = guid_to_uuid(localChar.Uuid());
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
                                    // request.RespondWithProtocolError(GattProtocolError::InvalidHandle());
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

    std::string deviceId = ParseBluetoothClientId(args.Session().DeviceId().Id());

    uiThreadHandler_.Post([localChar, request, deferral, deviceId]
                          {
                            auto characteristicId = guid_to_uuid(localChar.Uuid());
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
                                    // request.RespondWithProtocolError(GattProtocolError::InvalidHandle());
                                    std::cout << "WriteRequestResult should throw error" << std::endl;
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
    auto serviceId = guid_to_uuid(gattServiceObject->obj.Service().Uuid());
    try
    {
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

      try
      {
        if (gattServiceObject->obj.AdvertisementStatus() == GattServiceProviderAdvertisementStatus::Started)
        {
          gattServiceObject->obj.StopAdvertising();
        }
      }
      catch (...)
      {
        std::cout << "Warning: Failed to stop advertisement of " << serviceId << std::endl;
      }

      // clean resources for characteristics
      for (auto const &[chatKey, gattCharacteristicObject] : gattServiceObject->characteristics)
      {
        gattCharacteristicObject->obj.ReadRequested(gattCharacteristicObject->read_requested_token);
        gattCharacteristicObject->obj.WriteRequested(gattCharacteristicObject->write_requested_token);
        gattCharacteristicObject->obj.SubscribedClientsChanged(gattCharacteristicObject->value_changed_token);
      }
    }
    catch (const winrt::hresult_error &e)
    {
      std::wcerr << "Failed to clear service: " << serviceId.c_str() << ", Error: " << e.message().c_str() << std::endl;
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

  std::string BlePeripheralPlugin::ParseBluetoothClientId(hstring clientId)
  {
    std::string deviceIdString = winrt::to_string(clientId);
    size_t pos = deviceIdString.find_last_of('-');
    if (pos != std::string::npos)
    {
      return deviceIdString.substr(pos + 1);
    }
    return deviceIdString;
  }

  std::string BlePeripheralPlugin::ParseBluetoothError(BluetoothError error)
  {
    switch (error)
    {
    case BluetoothError::Success:
      return "Success";
    case BluetoothError::RadioNotAvailable:
      return "RadioNotAvailable";
    case BluetoothError::ResourceInUse:
      return "ResourceInUse";
    case BluetoothError::DeviceNotConnected:
      return "DeviceNotConnected";
    case BluetoothError::OtherError:
      return "OtherError";
    case BluetoothError::DisabledByPolicy:
      return "DisabledByPolicy";
    case BluetoothError::NotSupported:
      return "NotSupported";
    case BluetoothError::DisabledByUser:
      return "DisabledByUser";
    case BluetoothError::ConsentRequired:
      return "ConsentRequired";
    case BluetoothError::TransportNotSupported:
      return "TransportNotSupported";
    default:
      return "Unknown";
    }
  }

  GattCharacteristicObject *BlePeripheralPlugin::FindGattCharacteristicObject(std::string characteristicId)
  {
    // This might return wrong result if multiple services have same characteristic Id
    std::string loweCaseCharId = to_lower_case(characteristicId);
    for (auto const &[key, gattServiceObject] : serviceProviderMap)
    {
      for (auto const &[charKey, gattChar] : gattServiceObject->characteristics)
      {
        if (charKey == loweCaseCharId)
          return gattChar;
      }
    }
    return nullptr;
  }

  bool BlePeripheralPlugin::AreAllServicesStarted()
  {
    for (auto const &[key, gattServiceObject] : serviceProviderMap)
    {
      if (gattServiceObject->obj.AdvertisementStatus() != GattServiceProviderAdvertisementStatus::Started)
      {
        return false;
      }
    }
    return true;
  }

} // namespace ble_peripheral

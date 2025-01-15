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
    const auto &bluetooth_adapter = co_await BluetoothAdapter::GetDefaultAsync();
    if (bluetooth_adapter != nullptr)
    {
      adapter = bluetooth_adapter;
      bluetoothRadio = co_await bluetooth_adapter.GetRadioAsync();
    }
    else
    {
      std::cout << "Bluetooth adapter is not available" << std::endl;
      auto radios = co_await Radio::GetRadiosAsync();
      for (auto &&radio : radios)
      {
        if (radio.Kind() == RadioKind::Bluetooth)
        {
          std::cout << "Bluetooth Radio found" << std::endl;
          bluetoothRadio = radio;
          break;
        }
      }
    }

    if (bluetoothRadio != nullptr)
    {
      radioStateChangedRevoker = bluetoothRadio.StateChanged(winrt::auto_revoke, {this, &BlePeripheralPlugin::Radio_StateChanged});
      bool isOn = bluetoothRadio.State() == RadioState::On;
      uiThreadHandler_.Post([isOn]
                            { bleCallback->OnBleStateChange(isOn, SuccessCallback, ErrorCallback); });
    }
    else
    {
      std::cout << "Bluetooth radio is not available" << std::endl;
    }
  }

  std::optional<FlutterError> BlePeripheralPlugin::Initialize()
  {
    InitializeAdapter();
    return std::nullopt;
  };

  ErrorOr<std::optional<bool>> BlePeripheralPlugin::IsAdvertising()
  {
    if (!publisher)
    {
      return ErrorOr<std::optional<bool>>(std::optional<bool>(false));
    }
    bool advertising = publisher.Status() == BluetoothLEAdvertisementPublisherStatus::Started;
    return ErrorOr<std::optional<bool>>(std::optional<bool>(advertising));
  };

  ErrorOr<bool> BlePeripheralPlugin::IsSupported()
  {
    if (!adapter)
    {
      return FlutterError("Bluetooth adapter is not available");
    }
    return adapter.IsPeripheralRoleSupported();
  };

  ErrorOr<bool> BlePeripheralPlugin::AskBlePermission()
  {
    // No need to ask permission on Windows
    return true;
  };

  std::optional<FlutterError> BlePeripheralPlugin::AddService(const BleService &service)
  {
    // Check if service already exists
    std::string serviceId = to_lower_case(service.uuid());
    if (serviceProviderMap.find(serviceId) != serviceProviderMap.end())
    {
      return FlutterError("Service already added");
    }

    // Add service
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

  ErrorOr<flutter::EncodableList> BlePeripheralPlugin::GetSubscribedClients()
  {
    // Map of deviceId to list of services and characteristics
    auto deviceMap = std::map<std::string, flutter::EncodableList>();
    for (auto const &[key, gattServiceObject] : serviceProviderMap)
    {
      for (auto const &[charKey, gattChar] : gattServiceObject->characteristics)
      {
        auto clients = gattChar->stored_clients;
        for (unsigned int i = 0; i < clients.Size(); ++i)
        {
          auto client = clients.GetAt(i);
          std::string deviceId = ParseBluetoothClientId(client.Session().DeviceId().Id());

          if (deviceMap.find(deviceId) != deviceMap.end())
          {
            deviceMap[deviceId].push_back(flutter::EncodableValue(charKey));
          }
          else
          {
            flutter::EncodableList charList = flutter::EncodableList();
            charList.push_back(flutter::EncodableValue(charKey));
            deviceMap.insert_or_assign(deviceId, charList);
          }
        }
      }
    }

    // Get all subscribed clients
    flutter::EncodableList clients_list = flutter::EncodableList();
    for (auto const &[deviceId, charList] : deviceMap)
    {
      clients_list.push_back(flutter::CustomEncodableValue(SubscribedClient(deviceId, charList)));
    }
    return clients_list;
  }

  std::optional<FlutterError> BlePeripheralPlugin::StartAdvertising(
      const flutter::EncodableList &services,
      const std::string *local_name,
      const int64_t *timeout,
      const ManufacturerData *manufacturer_data,
      bool add_manufacturer_data_in_scan_response)
  {
    try
    {
      // Lazy initialization of publisher
      if (!publisher)
      {
        publisher = BluetoothLEAdvertisementPublisher();
        publisher.StatusChanged({this, &BlePeripheralPlugin::Publisher_StatusChanged});
      }

      if (publisher.Status() == BluetoothLEAdvertisementPublisherStatus::Started)
      {
        return FlutterError("Already advertising");
      }

      // Advertising with LocalName is not supported
      // if (local_name != nullptr)
      // {
      //   publisher.Advertisement().LocalName(winrt::to_hstring(*local_name));
      // }

      // Adding Services throws Invalid Args Error..
      // for (const auto &service : services)
      // {
      //   publisher.Advertisement().ServiceUuids().Append(uuid_to_guid(std::get<std::string>(service)));
      // }

      if (manufacturer_data != nullptr)
      {
        const auto leManufacturerData = BluetoothLEManufacturerData();
        auto manufacturerId = static_cast<uint16_t>(manufacturer_data->manufacturer_id());
        auto manufacturerBytes = from_bytevc(manufacturer_data->data());
        leManufacturerData.CompanyId(manufacturerId);
        leManufacturerData.Data(manufacturerBytes);
        publisher.Advertisement().ManufacturerData().Append(leManufacturerData);
      }

      publisher.Start();
      return std::nullopt;
    }
    catch (const winrt::hresult_error &e)
    {
      std::wcerr << "Failed with error: Code: " << e.code() << "Message: " << e.message().c_str() << std::endl;
      std::string errorMessage = winrt::to_string(e.message());
      return FlutterError(winrt::to_string(e.message()));
    }
    catch (const std::exception &e)
    {
      std::cout << "Error: " << e.what() << std::endl;
      std::wstring errorMessage = winrt::to_hstring(e.what()).c_str();
      return FlutterError(winrt::to_string(errorMessage));
    }

    catch (...)
    {
      std::cout << "Error: Unknown error" << std::endl;
      return FlutterError("Something Went Wrong");
    }
  }

  std::optional<FlutterError> BlePeripheralPlugin::StopAdvertising()
  {
    try
    {
      if (publisher)
      {
        std::cout << "Stopping advertising" << std::endl;
        publisher.Advertisement().ServiceUuids().Clear();
        publisher.Advertisement().ManufacturerData().Clear();
        publisher.Stop();
      }
      return std::nullopt;
    }
    catch (const winrt::hresult_error &e)
    {
      std::wcerr << "Failed to stop advertise Error: " << e.message().c_str() << std::endl;
      return FlutterError("Failed", winrt::to_string(e.message()));
    }
    catch (...)
    {
      std::cout << "Error: Unknown error" << std::endl;
      return FlutterError("Failed", "Something Went Wrong");
    }
  }

  std::optional<FlutterError> BlePeripheralPlugin::UpdateCharacteristic(
      const std::string &characteristic_id,
      const std::vector<uint8_t> &value,
      const std::string *device_id)
  {
    GattCharacteristicObject *gattCharacteristicObject = FindGattCharacteristicObject(characteristic_id);
    if (gattCharacteristicObject == nullptr)
      return FlutterError("Failed to get this characteristic");

    IBuffer bytes = from_bytevc(value);
    DataWriter writer;
    writer.ByteOrder(ByteOrder::LittleEndian);
    writer.WriteBuffer(bytes);

    if (device_id != nullptr)
    {
      std::string deviceId = *device_id;
      for (auto const &client : gattCharacteristicObject->stored_clients)
      {
        if (ParseBluetoothClientId(client.Session().DeviceId().Id()) == deviceId)
        {
          gattCharacteristicObject->obj.NotifyValueAsync(writer.DetachBuffer(), client);
          return std::nullopt;
        }
      }
      return FlutterError("Device not subscribed to this characteristic");
    }

    gattCharacteristicObject->obj.NotifyValueAsync(writer.DetachBuffer());
    return std::nullopt;
  }

  // Helpers
  //
  void BlePeripheralPlugin::Publisher_StatusChanged(BluetoothLEAdvertisementPublisher const &sender, IInspectable const &args)
  {
    auto status = sender.Status();

    if (status == BluetoothLEAdvertisementPublisherStatus::Started)
    {
      uiThreadHandler_.Post([]
                            { bleCallback->OnAdvertisingStatusUpdate(true, nullptr, SuccessCallback, ErrorCallback); });
    }
    else if (status == BluetoothLEAdvertisementPublisherStatus::Stopped || status == BluetoothLEAdvertisementPublisherStatus::Aborted)
    {
      uiThreadHandler_.Post([]
                            { bleCallback->OnAdvertisingStatusUpdate(false, nullptr, SuccessCallback, ErrorCallback); });
    }

    auto status_str = ParseLEAdvertisementStatus(status);
    std::cout << "BlePublisherStatusChanged: " << status_str << std::endl;
  }

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
          CharacteristicProperties property = std::any_cast<CharacteristicProperties>(std::get<flutter::CustomEncodableValue>(propertyEncoded));
          charParameters.CharacteristicProperties(charParameters.CharacteristicProperties() | toGattCharacteristicProperties(property));
        }

        // Add characteristic permissions
        auto charPermissions = characteristic.permissions();
        for (flutter::EncodableValue permissionEncoded : charPermissions)
        {
          AttributePermissions bleAttributePermission = std::any_cast<AttributePermissions>(std::get<flutter::CustomEncodableValue>(permissionEncoded));
          auto blePermission = toBlePermission(bleAttributePermission);
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

          // Add descriptor permissions
          flutter::EncodableList descriptorPermissions = descriptor.permissions() == nullptr ? flutter::EncodableList() : *descriptor.permissions();
          for (flutter::EncodableValue permissionsEncoded : descriptorPermissions)
          {
            AttributePermissions bleAttributePermission = std::any_cast<AttributePermissions>(std::get<flutter::CustomEncodableValue>(permissionsEncoded));
            auto blePermission = toBlePermission(bleAttributePermission);
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

      if (serviceProvider.AdvertisementStatus() == GattServiceProviderAdvertisementStatus::Started)
      {
        std::cout << "Service is already advertising" << std::endl;
      }
      else
      {
        auto advertisementParameter = GattServiceProviderAdvertisingParameters();
        advertisementParameter.IsDiscoverable(true);
        advertisementParameter.IsConnectable(true);
        serviceProvider.StartAdvertising(advertisementParameter);
      }

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
    auto serviceUuid = guid_to_uuid(sender.Service().Uuid());
    if (args.Error() != BluetoothError::Success)
    {
      std::string errorStr = ParseBluetoothError(args.Error());
      std::cout << "ServiceAdvertisementStatusChanged " << serviceUuid << ", Error " << errorStr << std::endl;
    }
    else
    {
      std::cout << "AdvertisingStatus of service " << serviceUuid << ", changed to " << AdvertisementStatusToString(args.Status()) << " " << std::endl;
    }
  }

  void BlePeripheralPlugin::onSubscriptionUpdate(std::string deviceName, std::string deviceId, std::string characteristicId, bool subscribed)
  {
    /// Notify Flutter
    uiThreadHandler_.Post([deviceName, deviceId, characteristicId, subscribed]
                          {
                            bleCallback->OnCharacteristicSubscriptionChange(
                                deviceId, characteristicId, subscribed, &deviceName,
                                SuccessCallback, ErrorCallback);
                            // Notify subscription change
                          });
  }

  /// Characteristic Listeners
  winrt::fire_and_forget BlePeripheralPlugin::SubscribedClientsChanged(GattLocalCharacteristic const &localChar, IInspectable const &)
  {
    auto characteristicId = guid_to_uuid(localChar.Uuid());

    // Find GattCharacteristicObject
    GattCharacteristicObject *gattCharacteristicObject = FindGattCharacteristicObject(characteristicId);

    if (gattCharacteristicObject == nullptr)
    {
      std::cout << "Failed to get char " << characteristicId << std::endl;
      co_return;
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
        try
        {
          auto deviceInfo = co_await DeviceInformation::CreateFromIdAsync(oldClient.Session().DeviceId().Id());
          auto deviceName = winrt::to_string(deviceInfo.Name());
          onSubscriptionUpdate(deviceName, deviceIdArg, characteristicId, false);
        }
        catch (...)
        {
          std::cerr << "Failed to retrieve device name" << std::endl;
        }
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

        try
        {
          auto deviceInfo = co_await DeviceInformation::CreateFromIdAsync(currentClient.Session().DeviceId().Id());
          auto deviceName = winrt::to_string(deviceInfo.Name());
          onSubscriptionUpdate(deviceName, deviceIdArg, characteristicId, true);
        }
        catch (...)
        {
          std::cerr << "Failed to retrieve device name" << std::endl;
        }

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
    std::string characteristicId = to_uuidstr(localChar.Uuid());
    std::vector<uint8_t> *value_arg = nullptr;
    IBuffer charValue = localChar.StaticValue();
    // IBuffer charValue = nullptr;
    if (charValue != nullptr)
    {
      auto bytevc = to_bytevc(charValue);
      value_arg = &bytevc;
    }

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
    int64_t offset = request.Offset();

    uiThreadHandler_.Post([deviceId, characteristicId, offset, value_arg, deferral, request]
                          {
                            bleCallback->OnReadRequest(
                                deviceId, characteristicId, offset, value_arg,
                                // SuccessCallback,
                                [deferral, request](const ReadRequestResult *readResult)
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
                                });
                            // Handle readRequest result
                          });
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
        auto status = gattServiceObject->obj.AdvertisementStatus();
        // Created, Stopped, Started, Aborted, StartedWithoutAllAdvertisementData
        if (status == GattServiceProviderAdvertisementStatus::Started)
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
    bool isOn = radioState == RadioState::On;
    uiThreadHandler_.Post([isOn]
                          { bleCallback->OnBleStateChange(isOn, SuccessCallback, ErrorCallback); });
  }

  GattCharacteristicProperties BlePeripheralPlugin::toGattCharacteristicProperties(CharacteristicProperties property)
  {
    switch (property)
    {
    case CharacteristicProperties::kBroadcast:
      return GattCharacteristicProperties::Broadcast;
    case CharacteristicProperties::kRead:
      return GattCharacteristicProperties::Read;
    case CharacteristicProperties::kWriteWithoutResponse:
      return GattCharacteristicProperties::WriteWithoutResponse;
    case CharacteristicProperties::kWrite:
      return GattCharacteristicProperties::Write;
    case CharacteristicProperties::kNotify:
      return GattCharacteristicProperties::Notify;
    case CharacteristicProperties::kIndicate:
      return GattCharacteristicProperties::Indicate;
    case CharacteristicProperties::kAuthenticatedSignedWrites:
      return GattCharacteristicProperties::AuthenticatedSignedWrites;
    case CharacteristicProperties::kExtendedProperties:
      return GattCharacteristicProperties::ExtendedProperties;
    case CharacteristicProperties::kNotifyEncryptionRequired:
      return GattCharacteristicProperties::Notify;
    case CharacteristicProperties::kIndicateEncryptionRequired:
      return GattCharacteristicProperties::Indicate;
    default:
      return GattCharacteristicProperties::None;
    }
  }

  BlePermission BlePeripheralPlugin::toBlePermission(AttributePermissions permission)
  {
    switch (permission)
    {
    case AttributePermissions::kReadable:
      return BlePermission::readable;
    case AttributePermissions::kWriteable:
      return BlePermission::writeable;
    case AttributePermissions::kReadEncryptionRequired:
      return BlePermission::readEncryptionRequired;
    case AttributePermissions::kWriteEncryptionRequired:
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

  std::string BlePeripheralPlugin::ParseLEAdvertisementStatus(BluetoothLEAdvertisementPublisherStatus status)
  {
    switch (status)
    {
    case BluetoothLEAdvertisementPublisherStatus::Created:
      return "Created";
    case BluetoothLEAdvertisementPublisherStatus::Waiting:
      return "Waiting";
    case BluetoothLEAdvertisementPublisherStatus::Started:
      return "Started";
    case BluetoothLEAdvertisementPublisherStatus::Stopped:
      return "Stopped";
    case BluetoothLEAdvertisementPublisherStatus::Stopping:
      return "Stopping";
    case BluetoothLEAdvertisementPublisherStatus::Aborted:
      return "Aborted";
    default:
      return "Unknown";
    }
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

} // namespace ble_peripheral

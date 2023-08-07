#include "include/ble_peripheral/ble_peripheral_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "ble_peripheral_plugin.h"

void BlePeripheralPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  ble_peripheral::BlePeripheralPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

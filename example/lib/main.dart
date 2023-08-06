import 'package:ble_peripheral_example/home_controller.dart';
import 'package:ble_peripheral_example/home_view.dart';
import 'package:flutter/material.dart';

import 'package:get/get.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Get.put(HomeController());
  runApp(
    const GetMaterialApp(
      debugShowCheckedModeBanner: false,
      title: "BlePeripheral",
      home: HomeView(),
    ),
  );
}

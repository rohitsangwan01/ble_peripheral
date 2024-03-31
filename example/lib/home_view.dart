import 'package:ble_peripheral/ble_peripheral.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'home_controller.dart';

class HomeView extends GetView<HomeController> {
  const HomeView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('Ble Peripheral'),
          centerTitle: true,
          elevation: 4,
        ),
        body: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Obx(() =>
                      Text("Advertising: ${controller.isAdvertising.value}")),
                  Obx(() => Text("BleOn: ${controller.isBleOn.value}")),
                ],
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    const ElevatedButton(
                      onPressed: BlePeripheral.askBlePermission,
                      child: Text('Ask Permission'),
                    ),
                    ElevatedButton(
                      onPressed: controller.addServices,
                      child: const Text('Add Services'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    ElevatedButton(
                      onPressed: controller.getAllServices,
                      child: const Text('Get Services'),
                    ),
                    ElevatedButton(
                      onPressed: controller.removeServices,
                      child: const Text('Remove Services'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    ElevatedButton(
                      onPressed: controller.startAdvertising,
                      child: const Text('Start Advertising'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        await BlePeripheral.stopAdvertising();
                        controller.isAdvertising.value = false;
                      },
                      child: const Text('Stop Advertising'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    ElevatedButton(
                      onPressed: () async {
                        controller.updateCharacteristic();
                      },
                      child: const Text('Update Characteristic value'),
                    ),
                  ],
                ),
              ),
              const Divider(),
              const Center(child: Text("Devices")),
              Expanded(
                child: Obx(() => ListView.builder(
                      itemCount: controller.devices.length,
                      itemBuilder: (BuildContext context, int index) {
                        return Card(
                          child: ListTile(
                            title: Text(controller.devices[index]),
                          ),
                        );
                      },
                    )),
              ),
            ],
          ),
        ));
  }
}

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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  ElevatedButton(
                    onPressed: controller.start,
                    child: const Text('Start Advertising'),
                  ),
                  ElevatedButton(
                    onPressed: controller.stop,
                    child: const Text('Stop Advertising'),
                  ),
                ],
              ),
              const Divider(),
              const Text("Devices"),
              Expanded(
                child: Obx(() => ListView.builder(
                      itemCount: controller.devices.length,
                      itemBuilder: (BuildContext context, int index) {
                        return Card(
                          child: ListTile(
                            title: Text(controller.devices[index].uuid.value),
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

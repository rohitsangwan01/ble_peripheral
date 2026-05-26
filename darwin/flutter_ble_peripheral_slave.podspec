#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_ble_peripheral_slave.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_ble_peripheral_slave'
  s.version          = '2.4.3'
  s.summary          = 'Ble peripheral is a Flutter plugin that allows you to use your device as Bluetooth Low Energy (BLE) peripheral'
  s.description      = <<-DESC
Ble peripheral is a Flutter plugin that allows you to use your device as Bluetooth Low Energy (BLE) peripheral
                       DESC
  s.homepage         = 'https://github.com/FaroukBoussarsar/ble_peripheral'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Farouk Boussarsar' => 'farouk@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '11.0'
  s.osx.deployment_target = '10.14'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end

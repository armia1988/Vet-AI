import 'ble_sensor_models.dart';

class VetBleSensorProvisioner {
  VetBleSensorProvisioner._();
  static final instance = VetBleSensorProvisioner._();

  bool get supported => false;

  Stream<VetBleAdapterState> get adapterState =>
      Stream.value(VetBleAdapterState.unavailable);

  Stream<VetBleDevice> scan() => const Stream<VetBleDevice>.empty();

  Future<void> stopScan() async {}

  Future<VetBleDeviceInfo> readDeviceInfo(String deviceId) {
    throw UnsupportedError('Bluetooth sensor onboarding requires the Vet AI mobile app.');
  }

  Future<VetBleProvisionStatus> provision({
    required String deviceId,
    required VetBleCloudConfig config,
    required void Function(VetBleProvisionStatus status) onStatus,
  }) {
    throw UnsupportedError('Bluetooth sensor onboarding requires the Vet AI mobile app.');
  }
}

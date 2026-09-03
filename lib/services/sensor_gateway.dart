import '../models/vet_models.dart';

/// Hardware-neutral contract for Vet AI telemetry.
/// Real collars/tags/barn gateways will implement this through BLE/Wi-Fi/MQTT.
abstract class SensorGateway {
  Stream<SensorSnapshot> watchAnimal(String animalId);
  Future<void> connect();
  Future<void> disconnect();
}

class DemoSensorGateway implements SensorGateway {
  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Stream<SensorSnapshot> watchAnimal(String animalId) async* {
    var tick = 0;
    while (true) {
      await Future<void>.delayed(const Duration(seconds: 3));
      tick++;
      yield SensorSnapshot(
        animalId: animalId,
        bodyTemperatureC: 38.6 + ((tick % 3) * 0.1),
        ambientTemperatureC: 27.4,
        humidityPercent: 58,
        activityIndex: 0.72,
        distanceFromHerdMeters: 4.8,
        steps: 3420 + tick * 4,
        lyingMinutesToday: 286,
        feedingMinutesToday: 118,
        ruminationMinutesToday: 347,
        calvingRiskPercent: 18,
        lastUpdate: DateTime.now(),
      );
    }
  }
}

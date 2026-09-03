# Vet AI Smart Monitoring — Sensor System V1

## Goal

Detect meaningful changes early enough to help farm staff intervene before avoidable losses occur. The system must never treat one noisy sensor reading as a diagnosis; it fuses multiple signals against the animal/flock baseline and raises an alert with evidence.

## 1. On-animal device

Recommended modular collar/ear-tag architecture:

- 3-axis accelerometer + gyroscope (IMU): movement, posture change, activity, lying/standing patterns, gait-related anomalies.
- Temperature sensing: body-proxy/skin/ear temperature trend. Exact placement must be validated because surface temperature is not interchangeable with core temperature.
- Positioning:
  - GNSS/GPS for outdoor pasture use.
  - UWB anchors/tags for accurate indoor barn location where installed.
  - BLE RSSI can be used for coarse proximity only and should not be presented as precise meter-level distance unless field validation supports it.
- Optional acoustic channel or barn microphone for cough/respiratory-event research.
- Battery, charging/battery-health telemetry and tamper/device-offline status.

## 2. Barn / room gateway

- Ambient temperature.
- Relative humidity.
- Optional CO2.
- Optional ammonia (NH3) with calibrated agricultural-grade sensing.
- Sound/noise channel where approved.
- Wi-Fi/Ethernet/cellular backhaul.
- BLE/UWB receiver depending on animal tags.

## 3. Derived behavior features

Raw measurements are converted into time-window features such as:

- Activity index vs individual baseline.
- Steps / locomotion intensity.
- Lying time and lying bouts.
- Standing time.
- Feeding proxy.
- Rumination proxy where sensor placement supports it.
- Separation/isolation behavior: time and distance away from herd baseline.
- Repeated pacing/restlessness.
- Sudden immobility.
- Heat-stress context using animal + environmental data.
- Device-offline and missing-data quality flags.

## 4. Calving watch

Calving is a prediction task, not an exact countdown. The model should combine multiple indicators when available:

- Restlessness/activity change.
- Reduced feeding/rumination.
- Increased lying bouts/postural changes.
- Isolation-seeking behavior.
- Tail movement/raising if camera or suitable tag supports it.
- Temperature trend.
- Pregnancy due-date context and parity/history.

Output example:

- Low / moderate / high calving-watch signal.
- Evidence list showing which indicators changed.
- Confidence/calibration based on validated farm data.
- Never claim a precise delivery time unless validation supports the interval.

## 5. Connectivity

### Device → Gateway

- BLE for low-power short-range telemetry.
- UWB where precise indoor positioning is required.
- LoRa/LoRaWAN can be evaluated for wide-area farm telemetry where bandwidth is low.

### Gateway → Vet AI backend

- MQTT over TLS is preferred for streaming telemetry.
- HTTPS REST for provisioning, configuration and fallback batch upload.

Every payload should include:

```json
{
  "device_id": "tag-000205",
  "animal_id": "cow-A205",
  "farm_id": "farm-001",
  "timestamp_utc": "...",
  "metric": "body_temp_proxy_c",
  "value": 38.7,
  "quality": 0.97,
  "battery_percent": 82,
  "firmware_version": "1.0.0"
}
```

## 6. Alert engine

Alert logic should fuse:

1. Individual animal baseline.
2. Herd/flock baseline.
3. Environmental context.
4. Multi-sensor agreement.
5. Recent AI scan/symptom data.
6. Data quality/device status.

Initial alert classes:

- RED: critical / rapid veterinary assessment or biosecurity action.
- ORANGE: high concern / prompt assessment.
- YELLOW: meaningful early deviation / closer monitoring.
- GREEN/none: no current alert.
- INSUFFICIENT DATA: sensor/image quality does not support a conclusion.

## 7. Safety and validation

- Thresholds must be species-, age-, production-stage- and sensor-placement-aware.
- Body surface/ear/skin temperature cannot be labeled as core temperature unless the hardware and placement have been validated for that use.
- Indoor distance requires a positioning technology capable of the claimed accuracy; BLE signal strength alone is not a guaranteed meter measurement.
- Calving alerts require farm validation with sensitivity, specificity, PPV and false-alert rate before commercial claims.
- Store raw data (where practical) plus derived features so algorithms can be revalidated.

## 8. App integration

`lib/services/sensor_gateway.dart` provides a hardware-neutral interface. Production adapters will replace `DemoSensorGateway` for real BLE/MQTT/UWB/GNSS devices while keeping the UI and analytics contract stable.

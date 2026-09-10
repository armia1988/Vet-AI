# Vet AI Universal BLE Sensor Onboarding v1

This protocol is the common mobile provisioning contract for Vet AI-compatible collars, tags, room sensors and gateways. It is intentionally separate from the sensor's long-term telemetry transport.

## User flow

1. Put a new sensor in pairing mode.
2. Vet AI discovers it over Bluetooth Low Energy.
3. The app reads the sensor identity and firmware information.
4. Vet AI registers the device through the authenticated `provision-sensor-device` backend function and receives a one-time device token.
5. The app sends the farm Wi-Fi/cloud configuration over the encrypted BLE link.
6. The sensor joins the internet and confirms `cloud_connected`/`provisioned` over BLE.
7. Bluetooth setup is finished. Normal telemetry continues independently through Wi-Fi/Ethernet/cellular/LoRa gateway as appropriate.

## Advertising

Compatible devices SHOULD advertise the primary service below and SHOULD use a local name beginning with `VetAI-`.

Primary service UUID:

`7d5f0001-5a11-4e7a-9b9a-564554414931`

## GATT characteristics

- Device info, read: `7d5f0002-5a11-4e7a-9b9a-564554414931`
- Provisioning config, write-with-response: `7d5f0003-5a11-4e7a-9b9a-564554414931`
- Provisioning status, read/notify: `7d5f0004-5a11-4e7a-9b9a-564554414931`

## Device info payload

UTF-8 JSON:

```json
{
  "protocol_version": 1,
  "device_uid": "VETAI-COLLAR-000205",
  "device_type": "vetai_collar",
  "firmware_version": "1.0.0",
  "capabilities": ["imu", "temperature", "battery"]
}
```

`device_uid` MUST be a stable factory identity and MUST NOT be the transient iOS Bluetooth peripheral identifier.

## Configuration framing

The mobile app serializes the provisioning object as UTF-8 JSON, splits it into small chunks and writes each chunk to the config characteristic as this frame:

```json
{
  "seq": 0,
  "total": 3,
  "data": "BASE64_CHUNK"
}
```

Firmware MUST collect every frame for one transaction, order by `seq`, Base64-decode and concatenate the chunks, then parse the resulting JSON.

The resulting configuration object is:

```json
{
  "protocol_version": 1,
  "command": "provision",
  "farm_id": "...",
  "device_token": "...",
  "cloud_url": "https://mzqwjyantyvizwbzetwf.supabase.co",
  "wifi_ssid": "Farm WiFi",
  "wifi_password": "..."
}
```

The Wi-Fi password and device token MUST NOT be logged by firmware and SHOULD be stored only in protected/non-volatile configuration appropriate to the controller.

## Status notifications

The status characteristic emits UTF-8 JSON, for example:

```json
{"status":"wifi_connecting"}
{"status":"cloud_connecting"}
{"status":"cloud_connected"}
{"status":"provisioned"}
```

Failure example:

```json
{"status":"error","message":"Wi-Fi authentication failed"}
```

The app considers `cloud_connected` or `provisioned` successful.

## Security requirements

- The backend device token is generated server-side and returned only during authenticated provisioning.
- A production sensor SHOULD require an authenticated/encrypted BLE connection before accepting configuration writes.
- Firmware MUST reject unsupported protocol versions and malformed/incomplete frame sets.
- Provisioning mode SHOULD automatically expire after a short period and SHOULD require physical presence (button/power-cycle/manufacturing pairing state) before accepting new credentials.
- Long-term device-to-cloud traffic must use TLS and the existing Vet AI device authentication path.

## Scope

This protocol makes onboarding uniform for Vet AI-compatible hardware. It cannot make an arbitrary third-party BLE sensor configurable unless that device exposes this protocol or Vet AI adds a vendor-specific adapter for it.

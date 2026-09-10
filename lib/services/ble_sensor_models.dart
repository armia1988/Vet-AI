import 'dart:convert';

/// Vet AI universal BLE onboarding protocol v1.
///
/// Hardware vendors can implement these UUIDs on ESP32/nRF52-class devices so
/// the same Vet AI mobile flow can pair collars, tags and barn gateways.
class VetBleProtocol {
  VetBleProtocol._();

  static const serviceUuid = '7d5f0001-5a11-4e7a-9b9a-564554414931';
  static const deviceInfoUuid = '7d5f0002-5a11-4e7a-9b9a-564554414931';
  static const configUuid = '7d5f0003-5a11-4e7a-9b9a-564554414931';
  static const statusUuid = '7d5f0004-5a11-4e7a-9b9a-564554414931';

  static const protocolVersion = 1;
  static const advertisedNamePrefix = 'VetAI-';
}

enum VetBleAdapterState { unknown, unavailable, unauthorized, off, ready }

class VetBleDevice {
  const VetBleDevice({
    required this.id,
    required this.name,
    required this.rssi,
    required this.compatible,
  });

  final String id;
  final String name;
  final int rssi;
  final bool compatible;
}

class VetBleDeviceInfo {
  const VetBleDeviceInfo({
    required this.deviceUid,
    required this.deviceType,
    required this.firmwareVersion,
    required this.protocolVersion,
    required this.capabilities,
  });

  final String deviceUid;
  final String deviceType;
  final String firmwareVersion;
  final int protocolVersion;
  final List<String> capabilities;

  factory VetBleDeviceInfo.fromBytes(List<int> bytes) {
    final raw = jsonDecode(utf8.decode(bytes));
    if (raw is! Map) throw const FormatException('Invalid Vet AI device info');
    final map = Map<String, dynamic>.from(raw);
    final uid = '${map['device_uid'] ?? ''}'.trim();
    if (uid.isEmpty) throw const FormatException('Device UID is missing');
    final version = (map['protocol_version'] as num?)?.toInt() ?? 0;
    if (version != VetBleProtocol.protocolVersion) {
      throw FormatException('Unsupported BLE protocol version $version');
    }
    return VetBleDeviceInfo(
      deviceUid: uid,
      deviceType: '${map['device_type'] ?? 'vetai_sensor'}'.trim(),
      firmwareVersion: '${map['firmware_version'] ?? ''}'.trim(),
      protocolVersion: version,
      capabilities: (map['capabilities'] as List? ?? const [])
          .map((e) => '$e')
          .where((e) => e.trim().isNotEmpty)
          .toList(growable: false),
    );
  }
}

class VetBleCloudConfig {
  const VetBleCloudConfig({
    required this.farmId,
    required this.deviceToken,
    required this.supabaseUrl,
    required this.wifiSsid,
    required this.wifiPassword,
  });

  final String farmId;
  final String deviceToken;
  final String supabaseUrl;
  final String wifiSsid;
  final String wifiPassword;

  Map<String, dynamic> toJson() => {
        'protocol_version': VetBleProtocol.protocolVersion,
        'command': 'provision',
        'farm_id': farmId,
        'device_token': deviceToken,
        'cloud_url': supabaseUrl,
        'wifi_ssid': wifiSsid,
        'wifi_password': wifiPassword,
      };
}

class VetBleProvisionStatus {
  const VetBleProvisionStatus({required this.code, this.message = ''});
  final String code;
  final String message;

  bool get success => code == 'provisioned' || code == 'cloud_connected';

  factory VetBleProvisionStatus.fromBytes(List<int> bytes) {
    final raw = jsonDecode(utf8.decode(bytes));
    if (raw is! Map) throw const FormatException('Invalid status payload');
    final map = Map<String, dynamic>.from(raw);
    return VetBleProvisionStatus(
      code: '${map['status'] ?? ''}'.trim(),
      message: '${map['message'] ?? ''}'.trim(),
    );
  }
}

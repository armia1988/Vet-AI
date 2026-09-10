enum CameraAlertSeverity { info, warning, critical }

class CameraAlertDecision {
  const CameraAlertDecision({
    required this.category,
    required this.title,
    required this.severity,
    required this.shouldSurface,
    this.temperatureC,
  });

  final String category;
  final String title;
  final CameraAlertSeverity severity;
  final bool shouldSurface;
  final double? temperatureC;
}

class CameraEventClassifier {
  const CameraEventClassifier._();

  static CameraAlertDecision classify({
    required String topic,
    required Map<String, String> values,
    double criticalTemperatureC = 41.0,
  }) {
    final haystack = '${topic.toLowerCase()} ${values.entries.map((e) => '${e.key}=${e.value}').join(' ').toLowerCase()}';
    final active = _isActive(values);
    final temperature = _firstTemperature(values);

    if (_containsAny(haystack, const ['fire', 'flame', 'smoke'])) {
      return CameraAlertDecision(
        category: 'fire',
        title: 'Fire / smoke event',
        severity: active ? CameraAlertSeverity.critical : CameraAlertSeverity.info,
        shouldSurface: active,
      );
    }

    if (_containsAny(haystack, const ['temperature', 'thermometry', 'thermal', 'overheat', 'high temp'])) {
      final critical = temperature != null && temperature >= criticalTemperatureC;
      return CameraAlertDecision(
        category: 'thermal',
        title: temperature == null ? 'Thermal event' : 'Thermal event ${temperature.toStringAsFixed(1)} °C',
        severity: critical ? CameraAlertSeverity.critical : CameraAlertSeverity.warning,
        shouldSurface: active || temperature != null,
        temperatureC: temperature,
      );
    }

    if (_containsAny(haystack, const ['intrusion', 'linecross', 'line crossing', 'region entrance', 'regionexit', 'fielddetector'])) {
      return CameraAlertDecision(
        category: 'intrusion',
        title: 'Intrusion / zone event',
        severity: active ? CameraAlertSeverity.warning : CameraAlertSeverity.info,
        shouldSurface: active,
      );
    }

    if (_containsAny(haystack, const ['motion', 'ismotion', 'cellmotion'])) {
      return CameraAlertDecision(
        category: 'motion',
        title: 'Motion detected',
        severity: CameraAlertSeverity.warning,
        shouldSurface: active,
      );
    }

    if (_containsAny(haystack, const ['person', 'human', 'face'])) {
      return CameraAlertDecision(
        category: 'person',
        title: 'Person / human event',
        severity: CameraAlertSeverity.info,
        shouldSurface: active,
      );
    }

    if (_containsAny(haystack, const ['vehicle', 'car', 'truck'])) {
      return CameraAlertDecision(
        category: 'vehicle',
        title: 'Vehicle event',
        severity: CameraAlertSeverity.info,
        shouldSurface: active,
      );
    }

    return CameraAlertDecision(
      category: 'camera_event',
      title: topic.isEmpty ? 'Camera event' : topic,
      severity: CameraAlertSeverity.info,
      shouldSurface: active,
    );
  }

  static bool _isActive(Map<String, String> values) {
    if (values.isEmpty) return true;
    const likelyStateKeys = ['State', 'IsMotion', 'Motion', 'Alarm', 'Active', 'Detected', 'LogicalState'];
    for (final key in likelyStateKeys) {
      final raw = values[key];
      if (raw == null) continue;
      final value = raw.trim().toLowerCase();
      if (const ['true', '1', 'on', 'active', 'start', 'started', 'detected', 'alarm'].contains(value)) return true;
      if (const ['false', '0', 'off', 'inactive', 'stop', 'stopped', 'clear', 'cleared'].contains(value)) return false;
    }
    return true;
  }

  static double? _firstTemperature(Map<String, String> values) {
    const keys = ['Temperature', 'MaxTemperature', 'maxTemperature', 'temperature', 'temperatureC'];
    for (final key in keys) {
      final raw = values[key];
      if (raw == null) continue;
      final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(raw);
      final parsed = match == null ? null : double.tryParse(match.group(0)!);
      if (parsed != null) return parsed;
    }
    return null;
  }

  static bool _containsAny(String haystack, List<String> needles) => needles.any(haystack.contains);
}

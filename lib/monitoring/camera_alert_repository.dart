import '../services/vet_backend.dart';
import 'camera_event_classifier.dart';
import 'onvif_analytics_events_service.dart';

class CameraAlertRepository {
  const CameraAlertRepository();

  String _risk(CameraAlertSeverity severity) {
    switch (severity) {
      case CameraAlertSeverity.info:
        return 'yellow';
      case CameraAlertSeverity.warning:
        return 'orange';
      case CameraAlertSeverity.critical:
        return 'red';
    }
  }

  Future<Map<String, dynamic>> save({
    required String farmId,
    required String cameraUid,
    required String cameraName,
    required OnvifCameraEvent event,
    required CameraAlertDecision decision,
  }) async {
    final details = <String>[
      'Camera: $cameraName',
      'Topic: ${event.topic}',
      if (event.operation != null && event.operation!.trim().isNotEmpty)
        'Operation: ${event.operation}',
      if (event.values.isNotEmpty)
        event.values.entries.map((e) => '${e.key}=${e.value}').join(' • '),
    ].join('\n');
    final metric = 'camera:$cameraUid:${decision.category}';
    final createdAt = event.utcTime?.toUtc();

    if (createdAt != null) {
      final duplicate = await VetBackend.instance.client
          .from('alerts')
          .select()
          .eq('farm_id', farmId)
          .eq('source', 'camera')
          .eq('metric', metric)
          .eq('created_at', createdAt.toIso8601String())
          .limit(1);
      if (duplicate.isNotEmpty) {
        final existing = Map<String, dynamic>.from(duplicate.first);
        existing['_inserted'] = false;
        return existing;
      }
    }

    final now = DateTime.now().toUtc();
    final throttleSince = now.subtract(const Duration(seconds: 20));
    final recentSame = await VetBackend.instance.client
        .from('alerts')
        .select()
        .eq('farm_id', farmId)
        .eq('source', 'camera')
        .eq('metric', metric)
        .eq('title', '$cameraName — ${decision.title}')
        .gte('created_at', throttleSince.toIso8601String())
        .order('created_at', ascending: false)
        .limit(1);
    if (recentSame.isNotEmpty) {
      final existing = Map<String, dynamic>.from(recentSame.first);
      existing['_inserted'] = false;
      return existing;
    }

    final row = await VetBackend.instance.client
        .from('alerts')
        .insert({
          'farm_id': farmId,
          'risk': _risk(decision.severity),
          'title': '$cameraName — ${decision.title}',
          'details': details,
          'source': 'camera',
          'metric': metric,
          if (decision.temperatureC != null)
            'value_numeric': decision.temperatureC,
          'threshold_text': event.topic,
          if (createdAt != null)
            'created_at': createdAt.toIso8601String(),
        })
        .select()
        .single();
    final inserted = Map<String, dynamic>.from(row);
    inserted['_inserted'] = true;
    return inserted;
  }

  Future<List<Map<String, dynamic>>> recentForCamera({
    required String farmId,
    required String cameraUid,
    int limit = 50,
  }) async {
    final rows = await VetBackend.instance.client
        .from('alerts')
        .select()
        .eq('farm_id', farmId)
        .eq('source', 'camera')
        .like('metric', 'camera:$cameraUid:%')
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(
      rows.map((e) => Map<String, dynamic>.from(e)),
    );
  }

  Future<double> thermalCriticalThreshold({
    required String farmId,
    required String cameraUid,
  }) async {
    final row = await VetBackend.instance.client
        .from('sensor_devices')
        .select('capabilities')
        .eq('farm_id', farmId)
        .eq('device_uid', cameraUid)
        .limit(1)
        .maybeSingle();
    if (row == null) return 41.0;
    final capabilities = Map<String, dynamic>.from(row['capabilities'] as Map? ?? const {});
    final raw = capabilities['thermal_alert_threshold_c'];
    return double.tryParse((raw ?? '').toString()) ?? 41.0;
  }

  Future<void> setThermalCriticalThreshold({
    required String farmId,
    required String cameraUid,
    required double valueC,
  }) async {
    if (!valueC.isFinite || valueC < 30 || valueC > 60) {
      throw ArgumentError.value(valueC, 'valueC', 'Thermal threshold must be between 30 and 60 °C');
    }
    final row = await VetBackend.instance.client
        .from('sensor_devices')
        .select('capabilities')
        .eq('farm_id', farmId)
        .eq('device_uid', cameraUid)
        .limit(1)
        .maybeSingle();
    if (row == null) throw StateError('Camera registration not found');
    final capabilities = Map<String, dynamic>.from(row['capabilities'] as Map? ?? const {});
    capabilities['thermal_alert_threshold_c'] = valueC;
    await VetBackend.instance.client
        .from('sensor_devices')
        .update({'capabilities': capabilities})
        .eq('farm_id', farmId)
        .eq('device_uid', cameraUid);
  }

  Future<void> acknowledge(String alertId) async {
    final userId = VetBackend.instance.client.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign-in required to acknowledge alerts');
    await VetBackend.instance.client
        .from('alerts')
        .update({
          'acknowledged_at': DateTime.now().toUtc().toIso8601String(),
          'acknowledged_by': userId,
        })
        .eq('id', alertId);
  }

  Future<void> dispatchPush(String alertId) async {
    final response = await VetBackend.instance.client.functions.invoke(
      'vet-ai-apns-push',
      body: {'alert_id': alertId},
    );
    if (response.status < 200 || response.status >= 300) {
      throw StateError('Push dispatch failed with HTTP ${response.status}');
    }
  }
}

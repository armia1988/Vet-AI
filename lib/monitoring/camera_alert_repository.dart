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

    final row = await VetBackend.instance.client
        .from('alerts')
        .insert({
          'farm_id': farmId,
          'risk': _risk(decision.severity),
          'title': '$cameraName — ${decision.title}',
          'details': details,
          'source': 'camera',
          'metric': 'camera:$cameraUid:${decision.category}',
          if (decision.temperatureC != null)
            'value_numeric': decision.temperatureC,
          'threshold_text': event.topic,
          if (event.utcTime != null)
            'created_at': event.utcTime!.toUtc().toIso8601String(),
        })
        .select()
        .single();
    return Map<String, dynamic>.from(row);
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

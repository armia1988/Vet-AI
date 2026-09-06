import 'vet_backend.dart';

extension VetOperations on VetBackend {
  Future<bool> isSupportAgent() async {
    if (currentUser == null) return false;
    try {
      final value = await client.rpc('is_support_agent');
      return value == true;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> supportAgentThreads({String? status}) async {
    dynamic query = client.from('support_threads').select('id,farm_id,created_by,subject,status,created_at,updated_at,farms(farm_name,company_name)');
    if (status != null && status.isNotEmpty) query = query.eq('status', status);
    final rows = await query.order('updated_at', ascending: false).limit(100);
    return (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Stream<List<Map<String, dynamic>>> supportAgentMessagesStream(String threadId) => client.from('support_messages').stream(primaryKey: ['id']).eq('thread_id', threadId).order('created_at');

  Future<void> sendSupportAgentMessage(String threadId, String message) async {
    final user = currentUser;
    if (user == null) throw StateError('Support agent login required.');
    final clean = message.trim();
    if (clean.isEmpty) return;
    await client.from('support_messages').insert({'thread_id': threadId, 'sender_id': user.id, 'sender_role': 'support', 'message': clean});
    await client.from('support_threads').update({'status': 'open', 'updated_at': DateTime.now().toIso8601String()}).eq('id', threadId);
  }

  Future<void> setSupportThreadStatus(String threadId, String status) async {
    if (!{'open', 'closed', 'pending'}.contains(status)) throw ArgumentError('Unsupported support status.');
    await client.from('support_threads').update({'status': status, 'updated_at': DateTime.now().toIso8601String()}).eq('id', threadId);
  }

  Future<void> saveFarmAnimalProfile(
    String farmId, {
    required Set<String> livestockSpecies,
    required Set<String> birdSpecies,
    required bool dogEnabled,
    Set<String> dogBreeds = const <String>{},
  }) async {
    await client.from('farms').update({
      'livestock_species': livestockSpecies.toList()..sort(),
      'bird_species': birdSpecies.toList()..sort(),
      'dog_enabled': dogEnabled,
      'dog_breeds': dogEnabled ? (dogBreeds.toList()..sort()) : <String>[],
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', farmId);
  }

  Future<void> setAssessmentSpecies(
    String assessmentId, {
    required String speciesCode,
    String? birdType,
  }) async {
    await client.from('assessments').update({
      'species_code': speciesCode,
      'bird_type': birdType,
    }).eq('id', assessmentId);
  }

  Future<List<Map<String, dynamic>>> sensorAlertRules(String farmId) async {
    final rows = await client.from('sensor_alert_rules').select().eq('farm_id', farmId).order('metric');
    return rows.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>> saveSensorAlertRule({
    String? id,
    required String farmId,
    required String metric,
    double? minValue,
    double? maxValue,
    required String severity,
    required String label,
    required int cooldownMinutes,
    required bool enabled,
    required String unit,
    required String sensorModel,
    required String valueKind,
    required String comparisonMode,
  }) async {
    final user = currentUser;
    if (user == null) throw StateError('Signed-in user required.');
    if (minValue == null && maxValue == null) throw ArgumentError('At least one threshold is required.');
    if (minValue != null && maxValue != null && minValue >= maxValue) {
      throw ArgumentError('Minimum threshold must be lower than maximum threshold.');
    }
    final data = <String, dynamic>{
      'farm_id': farmId,
      'metric': metric,
      'min_value': minValue,
      'max_value': maxValue,
      'severity': severity,
      'label': label.trim(),
      'cooldown_minutes': cooldownMinutes,
      'enabled': enabled,
      'created_by': user.id,
      'updated_at': DateTime.now().toIso8601String(),
      'unit': unit,
      'sensor_model': sensorModel,
      'value_kind': valueKind,
      'comparison_mode': comparisonMode,
    };
    if (id == null) {
      final row = await client.from('sensor_alert_rules').insert(data).select().single();
      return Map<String, dynamic>.from(row);
    }
    final row = await client.from('sensor_alert_rules').update(data).eq('id', id).select().single();
    return Map<String, dynamic>.from(row);
  }

  Future<void> deleteSensorAlertRule(String id) => client.from('sensor_alert_rules').delete().eq('id', id);

  Stream<List<Map<String, dynamic>>> alertsStream(String farmId) => client.from('alerts').stream(primaryKey: ['id']).eq('farm_id', farmId).order('created_at', ascending: false);

  Future<List<Map<String, dynamic>>> animalsForFarm(String farmId) async {
    final rows = await client.from('animals').select('id,external_id,name,species,animal_group,active').eq('farm_id', farmId).eq('active', true).order('created_at');
    return rows.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<Map<String, dynamic>>> hardwareCatalog() async {
    final rows = await client.from('sensor_hardware_catalog').select().order('category');
    return rows.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>> provisionSensorDevice({
    required String farmId,
    required String deviceUid,
    String firmwareVersion = '',
    List<String> sensorModels = const ['MPU6050', 'SHT40', 'SC4-O2', 'SCT-013', 'TP4056 + LiPo 3.7V 5000mAh'],
  }) async {
    final response = await client.functions.invoke('provision-sensor-device', body: {
      'farm_id': farmId,
      'device_uid': deviceUid,
      'device_type': 'vetai_sensor_hub',
      'firmware_version': firmwareVersion,
      'sensor_models': sensorModels,
    });
    if (response.data is Map) return Map<String, dynamic>.from(response.data as Map);
    throw StateError('Device provisioning returned an invalid response.');
  }

  Future<void> logVoiceClientEvent({
    required String stage,
    String? route,
    int? httpStatus,
    String? detail,
    String? appVersion,
    String? projectRef,
  }) async {
    final user = currentUser;
    if (user == null) return;
    try {
      await client.from('voice_client_events').insert({
        'user_id': user.id,
        'stage': stage,
        'route': route,
        'http_status': httpStatus,
        'detail': detail,
        'app_version': appVersion,
        'project_ref': projectRef,
      });
    } catch (_) {
      // Telemetry must never block voice playback.
    }
  }
}

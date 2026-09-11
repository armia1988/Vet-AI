import 'package:supabase_flutter/supabase_flutter.dart';

class AnimalTimelineItem {
  const AnimalTimelineItem({
    required this.kind,
    required this.title,
    required this.occurredAt,
    this.details,
    this.value,
    this.unit,
    this.risk,
  });

  final String kind;
  final String title;
  final DateTime occurredAt;
  final String? details;
  final num? value;
  final String? unit;
  final String? risk;
}

class AnimalHealthService {
  AnimalHealthService._();

  static final AnimalHealthService instance = AnimalHealthService._();

  SupabaseClient get _client => Supabase.instance.client;

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  List<Map<String, dynamic>> _rows(dynamic value) {
    if (value is! List) return const [];
    return value.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  DateTime _date(dynamic value) {
    if (value is DateTime) return value;
    return DateTime.tryParse('${value ?? ''}')?.toLocal() ?? DateTime.now();
  }

  Future<Map<String, dynamic>> dashboard(String farmId) async {
    final value = await _client.rpc(
      'farm_health_dashboard',
      params: {'p_farm_id': farmId},
    );
    return _map(value);
  }

  Future<List<Map<String, dynamic>>> animals(String farmId) async {
    final rows = await _client
        .from('animals')
        .select()
        .eq('farm_id', farmId)
        .eq('active', true)
        .order('created_at', ascending: false);
    return _rows(rows);
  }

  Future<Map<String, dynamic>> createAnimal({
    required String farmId,
    required String animalGroup,
    required String externalId,
    required String name,
    required String species,
    required String breed,
    required String sex,
    double? weightKg,
  }) async {
    final row = await _client
        .from('animals')
        .insert({
          'farm_id': farmId,
          'animal_group': animalGroup,
          'external_id': externalId.trim().isEmpty ? null : externalId.trim(),
          'name': name.trim().isEmpty ? null : name.trim(),
          'species': species.trim().isEmpty ? null : species.trim(),
          'breed': breed.trim().isEmpty ? null : breed.trim(),
          'sex': sex.trim().isEmpty ? null : sex.trim(),
          if (weightKg != null) 'weight_kg': weightKg,
        })
        .select()
        .single();
    return Map<String, dynamic>.from(row);
  }

  Future<void> addHealthEvent({
    required String farmId,
    required String animalId,
    required String eventType,
    required String title,
    String? details,
    num? value,
    String? unit,
    DateTime? occurredAt,
  }) async {
    await _client.from('animal_health_events').insert({
      'farm_id': farmId,
      'animal_id': animalId,
      'event_type': eventType,
      'title': title.trim(),
      'details': details?.trim().isEmpty == true ? null : details?.trim(),
      'value_numeric': value,
      'unit': unit?.trim().isEmpty == true ? null : unit?.trim(),
      'occurred_at': (occurredAt ?? DateTime.now()).toUtc().toIso8601String(),
      'source': 'manual',
    });

    if (eventType == 'weight' && value != null) {
      await _client
          .from('animals')
          .update({'weight_kg': value})
          .eq('id', animalId)
          .eq('farm_id', farmId);
    }
  }

  Future<List<Map<String, dynamic>>> vaccinations(String farmId) async {
    final rows = await _client
        .from('animal_vaccinations')
        .select()
        .eq('farm_id', farmId)
        .order('due_at');
    return _rows(rows);
  }

  Future<void> addVaccination({
    required String farmId,
    required String animalId,
    required String vaccineName,
    required DateTime dueAt,
    String? dose,
    String? batchNumber,
    String? notes,
  }) async {
    await _client.from('animal_vaccinations').insert({
      'farm_id': farmId,
      'animal_id': animalId,
      'vaccine_name': vaccineName.trim(),
      'dose': dose?.trim().isEmpty == true ? null : dose?.trim(),
      'batch_number': batchNumber?.trim().isEmpty == true ? null : batchNumber?.trim(),
      'due_at': dueAt.toUtc().toIso8601String(),
      'status': dueAt.isBefore(DateTime.now()) ? 'due' : 'planned',
      'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
    });
  }

  Future<void> markVaccinationAdministered(Map<String, dynamic> vaccination) async {
    final now = DateTime.now();
    await _client
        .from('animal_vaccinations')
        .update({
          'status': 'administered',
          'administered_at': now.toUtc().toIso8601String(),
        })
        .eq('id', '${vaccination['id']}');

    await addHealthEvent(
      farmId: '${vaccination['farm_id']}',
      animalId: '${vaccination['animal_id']}',
      eventType: 'treatment',
      title: 'Vaccination: ${vaccination['vaccine_name'] ?? ''}',
      details: vaccination['dose'] == null ? null : 'Dose: ${vaccination['dose']}',
      occurredAt: now,
    );
  }

  Future<List<Map<String, dynamic>>> medications(String farmId) async {
    final rows = await _client
        .from('animal_medications')
        .select()
        .eq('farm_id', farmId)
        .order('starts_at', ascending: false);
    return _rows(rows);
  }

  Future<void> addMedication({
    required String farmId,
    required String animalId,
    required String medicationName,
    required String dose,
    required String route,
    required String frequency,
    required DateTime startsAt,
    DateTime? endsAt,
    int? doseIntervalHours,
    DateTime? nextDoseAt,
    String? notes,
  }) async {
    await _client.from('animal_medications').insert({
      'farm_id': farmId,
      'animal_id': animalId,
      'medication_name': medicationName.trim(),
      'dose': dose.trim().isEmpty ? null : dose.trim(),
      'route': route.trim().isEmpty ? null : route.trim(),
      'frequency': frequency.trim().isEmpty ? null : frequency.trim(),
      'dose_interval_hours': doseIntervalHours,
      'starts_at': startsAt.toUtc().toIso8601String(),
      if (endsAt != null) 'ends_at': endsAt.toUtc().toIso8601String(),
      if (nextDoseAt != null) 'next_dose_at': nextDoseAt.toUtc().toIso8601String(),
      'status': startsAt.isAfter(DateTime.now()) ? 'planned' : 'active',
      'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
    });

    await addHealthEvent(
      farmId: farmId,
      animalId: animalId,
      eventType: 'treatment',
      title: 'Medication started: ${medicationName.trim()}',
      details: [
        if (dose.trim().isNotEmpty) 'Dose: ${dose.trim()}',
        if (route.trim().isNotEmpty) 'Route: ${route.trim()}',
        if (frequency.trim().isNotEmpty) 'Frequency: ${frequency.trim()}',
      ].join(' · '),
      occurredAt: startsAt,
    );
  }

  Future<void> recordMedicationDose(Map<String, dynamic> medication) async {
    final now = DateTime.now();
    final rawInterval = medication['dose_interval_hours'];
    final intervalHours = rawInterval is num
        ? rawInterval.toInt()
        : int.tryParse('${rawInterval ?? ''}');
    final nextDose = intervalHours != null && intervalHours > 0
        ? now.add(Duration(hours: intervalHours))
        : null;

    await _client
        .from('animal_medications')
        .update({
          'status': 'active',
          'next_dose_at': nextDose?.toUtc().toIso8601String(),
        })
        .eq('id', '${medication['id']}');

    await addHealthEvent(
      farmId: '${medication['farm_id']}',
      animalId: '${medication['animal_id']}',
      eventType: 'treatment',
      title: 'Medication dose given: ${medication['medication_name'] ?? ''}',
      details: [
        if (medication['dose'] != null) 'Dose: ${medication['dose']}',
        if (medication['route'] != null) 'Route: ${medication['route']}',
        if (nextDose != null) 'Next dose: ${nextDose.toLocal()}',
      ].join(' · '),
      occurredAt: now,
    );
  }

  Future<void> completeMedication(Map<String, dynamic> medication) async {
    final now = DateTime.now();
    await _client
        .from('animal_medications')
        .update({
          'status': 'completed',
          'ends_at': now.toUtc().toIso8601String(),
          'next_dose_at': null,
        })
        .eq('id', '${medication['id']}');

    await addHealthEvent(
      farmId: '${medication['farm_id']}',
      animalId: '${medication['animal_id']}',
      eventType: 'treatment',
      title: 'Medication completed: ${medication['medication_name'] ?? ''}',
      occurredAt: now,
    );
  }

  Future<List<AnimalTimelineItem>> timeline({
    required String farmId,
    required String animalId,
  }) async {
    final results = await Future.wait<dynamic>([
      _client
          .from('animal_health_events')
          .select()
          .eq('farm_id', farmId)
          .eq('animal_id', animalId)
          .order('occurred_at', ascending: false)
          .limit(60),
      _client
          .from('assessments')
          .select()
          .eq('farm_id', farmId)
          .eq('animal_id', animalId)
          .order('created_at', ascending: false)
          .limit(30),
      _client
          .from('alerts')
          .select()
          .eq('farm_id', farmId)
          .eq('animal_id', animalId)
          .order('created_at', ascending: false)
          .limit(30),
      _client
          .from('sensor_readings')
          .select('recorded_at,body_temperature_c,ambient_temperature_c,activity_index,battery_percent')
          .eq('farm_id', farmId)
          .eq('animal_id', animalId)
          .order('recorded_at', ascending: false)
          .limit(30),
      _client
          .from('animal_vaccinations')
          .select()
          .eq('farm_id', farmId)
          .eq('animal_id', animalId)
          .order('due_at', ascending: false)
          .limit(30),
      _client
          .from('animal_medications')
          .select()
          .eq('farm_id', farmId)
          .eq('animal_id', animalId)
          .order('starts_at', ascending: false)
          .limit(30),
    ]);

    final items = <AnimalTimelineItem>[];

    for (final row in _rows(results[0])) {
      items.add(AnimalTimelineItem(
        kind: '${row['event_type'] ?? 'note'}',
        title: '${row['title'] ?? 'Health event'}',
        details: row['details']?.toString(),
        value: row['value_numeric'] as num?,
        unit: row['unit']?.toString(),
        occurredAt: _date(row['occurred_at']),
      ));
    }

    for (final row in _rows(results[1])) {
      final ai = row['ai_analysis'];
      String? details = row['symptom_notes']?.toString();
      if ((details == null || details.isEmpty) && ai is Map) {
        details = ai['summary']?.toString() ?? ai['diagnosis']?.toString();
      }
      items.add(AnimalTimelineItem(
        kind: 'diagnosis',
        title: 'Vet AI assessment',
        details: details,
        risk: row['risk']?.toString(),
        occurredAt: _date(row['created_at']),
      ));
      final lab = row['laboratory_result']?.toString();
      if (lab != null && lab.trim().isNotEmpty) {
        items.add(AnimalTimelineItem(
          kind: 'lab',
          title: 'Laboratory result',
          details: lab,
          occurredAt: _date(row['created_at']),
        ));
      }
    }

    for (final row in _rows(results[2])) {
      items.add(AnimalTimelineItem(
        kind: 'alert',
        title: '${row['title'] ?? 'Health alert'}',
        details: row['details']?.toString(),
        risk: row['risk']?.toString(),
        value: row['value_numeric'] as num?,
        unit: row['metric']?.toString(),
        occurredAt: _date(row['created_at']),
      ));
    }

    for (final row in _rows(results[3])) {
      final temp = row['body_temperature_c'] as num?;
      if (temp == null) continue;
      items.add(AnimalTimelineItem(
        kind: 'temperature',
        title: 'Body temperature',
        details: row['activity_index'] == null
            ? null
            : 'Activity index: ${row['activity_index']}',
        value: temp,
        unit: '°C',
        occurredAt: _date(row['recorded_at']),
      ));
    }

    for (final row in _rows(results[4])) {
      final administered = row['administered_at'];
      items.add(AnimalTimelineItem(
        kind: 'vaccination',
        title: 'Vaccine: ${row['vaccine_name'] ?? ''}',
        details: [
          if (row['dose'] != null) 'Dose: ${row['dose']}',
          'Status: ${row['status'] ?? 'planned'}',
        ].join(' · '),
        occurredAt: administered == null ? _date(row['due_at']) : _date(administered),
      ));
    }

    for (final row in _rows(results[5])) {
      items.add(AnimalTimelineItem(
        kind: 'medication',
        title: 'Medication: ${row['medication_name'] ?? ''}',
        details: [
          if (row['dose'] != null) 'Dose: ${row['dose']}',
          if (row['frequency'] != null) '${row['frequency']}',
          'Status: ${row['status'] ?? 'active'}',
        ].join(' · '),
        occurredAt: _date(row['starts_at']),
      ));
    }

    items.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return items;
  }
}
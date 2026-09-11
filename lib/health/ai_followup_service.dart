import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/vet_backend.dart';

class AiFollowupService {
  AiFollowupService._();

  static final AiFollowupService instance = AiFollowupService._();

  SupabaseClient get _client => Supabase.instance.client;

  List<Map<String, dynamic>> _rows(dynamic value) {
    if (value is! List) return const [];
    return value.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> followups(String farmId) async {
    final rows = await _client
        .from('animal_ai_followups')
        .select(
          '*, animals(name,external_id,species), assessments(ai_analysis,risk,symptom_notes,media_path,ai_generated_at,species_code,bird_type)',
        )
        .eq('farm_id', farmId)
        .order('due_at');
    return _rows(rows);
  }

  Future<Map<String, dynamic>> submitFollowup({
    required Map<String, dynamic> followup,
    required Uint8List imageBytes,
    required String extension,
    required String language,
    String symptomNotes = '',
    double? temperatureC,
  }) async {
    if (imageBytes.isEmpty) {
      throw StateError('A follow-up image is required.');
    }

    final farmId = '${followup['farm_id']}';
    final followupId = '${followup['id']}';
    final mediaPath = await VetBackend.instance.uploadDiagnosticMedia(
      farmId: farmId,
      bytes: imageBytes,
      extension: extension,
    );

    await _client
        .from('animal_ai_followups')
        .update({
          'media_path': mediaPath,
          'symptom_notes': symptomNotes.trim().isEmpty ? null : symptomNotes.trim(),
          'temperature_c': temperatureC,
        })
        .eq('id', followupId)
        .eq('farm_id', farmId);

    try {
      final response = await _client.functions.invoke(
        'analyze-followup',
        body: {
          'followup_id': followupId,
          'language': language,
        },
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        if (data['code'] == 'AI_FOLLOWUP_COMPLETE') return data;
        throw StateError('${data['error'] ?? 'Follow-up analysis failed.'}');
      }
      if (data is Map) {
        final result = Map<String, dynamic>.from(data);
        if (result['code'] == 'AI_FOLLOWUP_COMPLETE') return result;
        throw StateError('${result['error'] ?? 'Follow-up analysis failed.'}');
      }
      throw StateError('The follow-up AI returned an unreadable response.');
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['error'] != null) {
        throw StateError('${details['error']}');
      }
      throw StateError(error.reasonPhrase ?? 'Follow-up analysis failed.');
    }
  }

  Future<void> skipFollowup(Map<String, dynamic> followup) async {
    await _client
        .from('animal_ai_followups')
        .update({
          'status': 'skipped',
          'completed_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', '${followup['id']}')
        .eq('farm_id', '${followup['farm_id']}');
  }
}
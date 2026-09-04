import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'vet_backend.dart';

extension VetCaseWorkflow on VetBackend {
  Future<Map<String, dynamic>> finalizeAssessment(
    String assessmentId, {
    required String language,
    required List<Map<String, String>> answers,
  }) async {
    try {
      final response = await client.functions
          .invoke(
            'finalize-case-report',
            body: {
              'assessment_id': assessmentId,
              'language': language,
              'answers': answers,
            },
          )
          .timeout(const Duration(seconds: 65));
      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
    } on TimeoutException {
      return {
        'code': 'FINAL_REPORT_TIMEOUT',
        'risk': 'insufficient_data',
        'message': language.toLowerCase().startsWith('ar')
            ? 'المراجعة الموثقة أخدت وقت أطول من المتوقع. جرّب إنشاء التقرير النهائي تاني.'
            : 'The verified evidence review took longer than expected. Please retry the final report.',
      };
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map<String, dynamic>) return details;
      if (details is Map) return Map<String, dynamic>.from(details);
      return {
        'code': 'FINAL_REPORT_FUNCTION_ERROR',
        'risk': 'insufficient_data',
        'message': language.toLowerCase().startsWith('ar')
            ? 'ماقدرناش نكمل التقرير النهائي دلوقتي. جرّب تاني.'
            : (error.reasonPhrase ?? 'The final veterinary evidence review could not be completed.'),
      };
    }
    return {
      'code': 'INVALID_FINAL_REPORT_RESPONSE',
      'risk': 'insufficient_data',
      'message': language.toLowerCase().startsWith('ar')
          ? 'التقرير النهائي رجع بصيغة غير قابلة للعرض. جرّب تاني.'
          : 'The final veterinary evidence service returned an unreadable response.',
    };
  }

  Future<Uint8List?> naturalCaseVoice({
    required String text,
    required String language,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) return null;
    try {
      final response = await client.functions
          .invoke(
            'case-voice',
            body: {
              'text': clean.length > 3900 ? clean.substring(0, 3900) : clean,
              'language': language,
            },
          )
          .timeout(const Duration(seconds: 24));
      final data = response.data;
      final encoded = data is Map ? data['audio_base64']?.toString() : null;
      if (encoded == null || encoded.isEmpty) return null;
      return Uint8List.fromList(base64Decode(encoded));
    } catch (_) {
      return null;
    }
  }
}

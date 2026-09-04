import 'package:supabase_flutter/supabase_flutter.dart';

import 'vet_backend.dart';

extension VetCaseWorkflow on VetBackend {
  Future<Map<String, dynamic>> finalizeAssessment(
    String assessmentId, {
    required String language,
    required List<Map<String, String>> answers,
  }) async {
    try {
      final response = await client.functions.invoke(
        'finalize-case-report',
        body: {
          'assessment_id': assessmentId,
          'language': language,
          'answers': answers,
        },
      );
      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map<String, dynamic>) return details;
      if (details is Map) return Map<String, dynamic>.from(details);
      return {
        'code': 'FINAL_REPORT_FUNCTION_ERROR',
        'risk': 'insufficient_data',
        'message': error.reasonPhrase ?? 'The final veterinary evidence review could not be completed.',
      };
    }
    return {
      'code': 'INVALID_FINAL_REPORT_RESPONSE',
      'risk': 'insufficient_data',
      'message': 'The final veterinary evidence service returned an unreadable response.',
    };
  }
}

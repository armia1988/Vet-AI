import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
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
          .timeout(const Duration(seconds: 60));
      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
    } on TimeoutException {
      return {
        'code': 'FINAL_REPORT_TIMEOUT',
        'risk': 'insufficient_data',
        'message': language.toLowerCase().startsWith('ar')
            ? 'التقرير النهائي أخد وقت أطول من المتوقع. جرّب مرة تانية؛ النظام بيستخدم المعرفة البيطرية المراجعة بدل ما يسيبك مستني.'
            : 'The final report took longer than expected. Please retry; Vet AI uses its reviewed veterinary knowledge instead of leaving the case waiting indefinitely.',
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
            : (error.reasonPhrase ??
                  'The final veterinary report could not be completed.'),
      };
    }
    return {
      'code': 'INVALID_FINAL_REPORT_RESPONSE',
      'risk': 'insufficient_data',
      'message': language.toLowerCase().startsWith('ar')
          ? 'التقرير النهائي رجع بصيغة غير قابلة للعرض. جرّب تاني.'
          : 'The final veterinary report service returned an unreadable response.',
    };
  }

  Future<Uint8List?> naturalCaseVoice({
    required String text,
    required String language,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) return null;

    Future<Uint8List?> requestOnce(String accessToken) async {
      final httpClient = HttpClient()..connectionTimeout = const Duration(seconds: 12);
      try {
        final uri = Uri.parse(
          '${SupabaseConfig.url}/functions/v1/case-voice',
        );
        final request = await httpClient.postUrl(uri).timeout(
          const Duration(seconds: 12),
        );
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
        request.headers.set('apikey', SupabaseConfig.publishableKey);
        request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        request.headers.set('x-client-info', 'vet-ai-ios-direct-voice-v32');
        request.add(
          utf8.encode(
            jsonEncode({
              'text': clean.length > 1200 ? clean.substring(0, 1200) : clean,
              'language': language,
            }),
          ),
        );

        final response = await request.close().timeout(
          const Duration(seconds: 70),
        );
        final raw = await utf8.decoder.bind(response).join().timeout(
          const Duration(seconds: 70),
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          return null;
        }
        final decoded = jsonDecode(raw);
        if (decoded is! Map) return null;
        final encoded =
            (decoded['audio_base64'] ?? decoded['audioContent'])?.toString().trim();
        if (encoded == null || encoded.isEmpty) return null;
        return Uint8List.fromList(base64Decode(encoded));
      } catch (_) {
        return null;
      } finally {
        httpClient.close(force: true);
      }
    }

    var session = client.auth.currentSession;
    if (session == null) return null;

    var audio = await requestOnce(session.accessToken);
    if (audio != null && audio.isNotEmpty) return audio;

    try {
      final refreshed = await client.auth.refreshSession();
      session = refreshed.session;
      if (session == null) return null;
      audio = await requestOnce(session.accessToken);
      if (audio != null && audio.isNotEmpty) return audio;
    } catch (_) {
      return null;
    }

    return null;
  }
}

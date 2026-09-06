import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import 'vet_backend.dart';
import 'vet_operations.dart';

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

  Uint8List? _decodeVoicePayload(dynamic data) {
    if (data is! Map) return null;
    final encoded =
        (data['audio_base64'] ?? data['audioContent'])?.toString().trim();
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final bytes = Uint8List.fromList(base64Decode(encoded));
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> naturalCaseVoice({
    required String text,
    required String language,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) return null;
    await logVoiceClientEvent(stage: 'start', route: 'voice_v35', appVersion: '0.6.21', projectRef: SupabaseConfig.projectRef);
    final body = {
      'text': clean.length > 1200 ? clean.substring(0, 1200) : clean,
      'language': language,
    };

    Future<Uint8List?> requestDirect(String accessToken) async {
      final httpClient = HttpClient()
        ..connectionTimeout = const Duration(seconds: 12);
      try {
        final uri = Uri.parse(
          '${SupabaseConfig.url}/functions/v1/case-voice',
        );
        final request = await httpClient.postUrl(uri).timeout(
          const Duration(seconds: 12),
        );
        // Supabase authenticated client calls use BOTH headers: the signed-in
        // user's JWT in Authorization and the project publishable key in apikey.
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $accessToken',
        );
        request.headers.set('apikey', SupabaseConfig.publishableKey);
        request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        request.headers.set('x-client-info', 'vet-ai-ios-direct-voice-v34');
        request.headers.set('x-vet-ai-project-ref', SupabaseConfig.projectRef);
        request.add(utf8.encode(jsonEncode(body)));

        final response = await request.close().timeout(
          const Duration(seconds: 25),
        );
        final raw = await utf8.decoder.bind(response).join().timeout(
          const Duration(seconds: 25),
        );
        await logVoiceClientEvent(stage: 'direct_response', route: 'http', httpStatus: response.statusCode, detail: 'bytes=${raw.length}', appVersion: '0.6.21', projectRef: SupabaseConfig.projectRef);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          return null;
        }
        final decoded = jsonDecode(raw);
        return _decodeVoicePayload(decoded);
      } catch (e) {
        await logVoiceClientEvent(stage: 'direct_exception', route: 'http', detail: e.toString(), appVersion: '0.6.21', projectRef: SupabaseConfig.projectRef);
        return null;
      } finally {
        httpClient.close(force: true);
      }
    }

    Future<Uint8List?> requestViaSdk() async {
      try {
        final response = await client.functions
            .invoke(
              'case-voice',
              body: body,
              headers: {
                'x-client-info': 'vet-ai-ios-sdk-voice-v34',
                'x-vet-ai-project-ref': SupabaseConfig.projectRef,
              },
            )
            .timeout(const Duration(seconds: 30));
        final decoded = _decodeVoicePayload(response.data);
        await logVoiceClientEvent(stage: decoded == null ? 'sdk_decode_empty' : 'sdk_success', route: 'sdk', detail: decoded == null ? 'No decodable audio payload' : 'audio_bytes=${decoded.length}', appVersion: '0.6.21', projectRef: SupabaseConfig.projectRef);
        return decoded;
      } catch (e) {
        await logVoiceClientEvent(stage: 'sdk_exception', route: 'sdk', detail: e.toString(), appVersion: '0.6.21', projectRef: SupabaseConfig.projectRef);
        return null;
      }
    }

    // A recovered Supabase session can briefly be absent from currentSession
    // after app/update startup. Restore it before giving up.
    var session = client.auth.currentSession;
    if (session == null) {
      try {
        final refreshed = await client.auth.refreshSession();
        session = refreshed.session;
      } catch (_) {
        session = null;
      }
    }
    if (session == null) {
      await logVoiceClientEvent(stage: 'no_session', route: 'auth', appVersion: '0.6.21', projectRef: SupabaseConfig.projectRef);
      return null;
    }

    // Route 1: explicit HTTP with the documented Authorization + apikey pair.
    var audio = await requestDirect(session.accessToken);
    if (audio != null && audio.isNotEmpty) return audio;

    // Route 2: official Supabase Functions client, which manages gateway auth.
    audio = await requestViaSdk();
    if (audio != null && audio.isNotEmpty) return audio;

    // One token refresh protects against a session that expired between opening
    // the report and tapping the speaker.
    try {
      final refreshed = await client.auth.refreshSession();
      session = refreshed.session;
      if (session == null) return null;
      audio = await requestDirect(session.accessToken);
      if (audio != null && audio.isNotEmpty) return audio;
      audio = await requestViaSdk();
      if (audio != null && audio.isNotEmpty) return audio;
    } catch (_) {
      return null;
    }

    return null;
  }
}

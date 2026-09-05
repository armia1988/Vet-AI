from pathlib import Path


def replace_once(path: str, old: str, new: str, label: str):
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'Missing marker for {label} in {path}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')
    print(f'patched: {label}')


# Stable SHA-256 cache for exact same image + notes + language + animal group.
replace_once(
    'lib/v5_app.dart',
    "import 'package:flutter/material.dart';\n",
    "import 'dart:convert';\n\nimport 'package:crypto/crypto.dart';\nimport 'package:flutter/material.dart';\n",
    'scan cache imports',
)

helper_marker = """  Future<void> analyze() async {\n    if (file == null || bytes == null) return;\n"""
helper_replacement = r'''  Future<String> _scanCacheKey() async {
    final language = Localizations.localeOf(context).languageCode.toLowerCase();
    final metadata = utf8.encode(
      '|$group|$language|${notes.text.trim().toLowerCase()}',
    );
    final digest = sha256.convert(<int>[...bytes!, ...metadata]).toString();
    return 'vet_ai_exact_scan_v2_$digest';
  }

  Future<Map<String, dynamic>?> _readExactScanCache(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final savedAt = DateTime.tryParse((decoded['saved_at'] ?? '').toString());
      if (savedAt == null || DateTime.now().difference(savedAt).inHours > 72) {
        await prefs.remove(key);
        return null;
      }
      final cachedResult = decoded['result'];
      final cachedAssessmentId = (decoded['assessment_id'] ?? '').toString();
      if (cachedResult is! Map ||
          cachedResult['code']?.toString() != 'AI_ANALYSIS_COMPLETE' ||
          cachedAssessmentId.isEmpty) {
        return null;
      }
      return {
        'assessment_id': cachedAssessmentId,
        'result': Map<String, dynamic>.from(cachedResult),
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeExactScanCache(
    String key,
    String assessmentId,
    Map<String, dynamic> response,
  ) async {
    if (response['code']?.toString() != 'AI_ANALYSIS_COMPLETE') return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        key,
        jsonEncode({
          'saved_at': DateTime.now().toIso8601String(),
          'assessment_id': assessmentId,
          'result': response,
        }),
      );
    } catch (_) {
      // Cache failure must never block a real veterinary assessment.
    }
  }

  Future<void> analyze() async {
    if (file == null || bytes == null) return;
'''
replace_once(
    'lib/v5_app.dart',
    helper_marker,
    helper_replacement,
    'exact scan cache helpers',
)

analyze_start = """    try {\n      final extension = file!.name.contains('.')\n"""
analyze_start_replacement = """    try {\n      final cacheKey = await _scanCacheKey();\n      final cached = await _readExactScanCache(cacheKey);\n      if (cached != null) {\n        assessmentId = cached['assessment_id'] as String;\n        final cachedResult = Map<String, dynamic>.from(\n          cached['result'] as Map<String, dynamic>,\n        );\n        cachedResult['cache_reused_on_device'] = true;\n        if (mounted) {\n          setState(() {\n            result = cachedResult;\n            busy = false;\n          });\n        }\n        return;\n      }\n\n      final extension = file!.name.contains('.')\n"""
replace_once(
    'lib/v5_app.dart',
    analyze_start,
    analyze_start_replacement,
    'reuse exact scan before upload/provider call',
)

response_marker = """      // Do not automatically hammer the AI provider after a 429/timeout.\n      // One explicit user action now produces one provider request.\n      if (mounted) setState(() => result = response);\n"""
response_replacement = """      // Do not automatically hammer the AI provider after a 429/timeout.\n      // One explicit user action now produces one provider request.\n      await _writeExactScanCache(cacheKey, newAssessmentId, response);\n      if (mounted) setState(() => result = response);\n"""
replace_once(
    'lib/v5_app.dart',
    response_marker,
    response_replacement,
    'save successful exact scan result locally',
)

# Prefer the best installed Arabic voice for the emergency on-device fallback.
voice_marker = """    try {\n      await _tts.stop();\n      final isArabic = widget.languageCode.toLowerCase().startsWith('ar');\n      if (isArabic) {\n        var configured = false;\n        for (final locale in const ['ar-EG', 'ar-SA', 'ar']) {\n"""
voice_replacement = r'''    try {
      await _tts.stop();
      final isArabic = widget.languageCode.toLowerCase().startsWith('ar');
      if (isArabic) {
        var configured = false;
        try {
          final rawVoices = await _tts.getVoices;
          if (rawVoices is List) {
            final candidates = rawVoices
                .whereType<Map>()
                .map((voice) => {
                      'name': (voice['name'] ?? '').toString(),
                      'locale': (voice['locale'] ?? '').toString(),
                    })
                .where((voice) => voice['name']!.isNotEmpty && voice['locale']!.toLowerCase().startsWith('ar'))
                .toList();
            int score(Map<String, String> voice) {
              final locale = voice['locale']!.toLowerCase();
              final name = voice['name']!.toLowerCase();
              var value = 0;
              if (locale.startsWith('ar-eg')) value += 100;
              if (locale.startsWith('ar-xa') || locale.startsWith('ar-001')) value += 80;
              if (locale.startsWith('ar-sa')) value += 60;
              if (name.contains('premium')) value += 35;
              if (name.contains('enhanced')) value += 25;
              if (name.contains('neural')) value += 20;
              return value;
            }
            candidates.sort((a, b) => score(b).compareTo(score(a)));
            if (candidates.isNotEmpty) {
              final best = candidates.first;
              final result = await _tts.setVoice({
                'name': best['name']!,
                'locale': best['locale']!,
              });
              configured = result != false;
            }
          }
        } catch (_) {
          // Fall through to locale selection below.
        }
        for (final locale in const ['ar-EG', 'ar-XA', 'ar-SA', 'ar']) {
          if (configured) break;
'''
replace_once(
    'lib/analysis/vet_analysis_report.dart',
    voice_marker,
    voice_replacement,
    'prefer best installed Arabic fallback voice',
)

# Dependency and release version.
replace_once(
    'pubspec.yaml',
    "  intl: ^0.20.2\n",
    "  intl: ^0.20.2\n  crypto: ^3.0.6\n",
    'crypto dependency',
)
replace_once(
    'pubspec.yaml',
    'version: 0.6.12+24',
    'version: 0.6.13+25',
    'V27 version',
)

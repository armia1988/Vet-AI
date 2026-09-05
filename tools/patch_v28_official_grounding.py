from pathlib import Path
import re


def sub_once(path: str, pattern: str, replacement: str, label: str, flags=0):
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    updated, count = re.subn(pattern, replacement, text, count=1, flags=flags)
    if count != 1:
        raise SystemExit(f'Expected exactly one match for {label} in {path}; got {count}')
    p.write_text(updated, encoding='utf-8')
    print(f'patched: {label}')


# 1) Make the protected analysis catalog species-aware and explicitly distinguish
# Orf's thick crusted proliferative lesions from FMD vesicles/erosions.
sub_once(
    'supabase/functions/analyze-case/index.ts',
    r'curation_status"\)\n      \.eq\("curation_status", "reviewed"\)',
    'curation_status,species_scope,source_org,source_url")\n      .eq("curation_status", "reviewed")',
    'analysis catalog source/species fields',
)
sub_once(
    'supabase/functions/analyze-case/index.ts',
    r'reportable_or_listed: d\.reportable_or_listed,\n      visible_signs:',
    'reportable_or_listed: d.reportable_or_listed,\n      species_scope: d.species_scope,\n      source_org: d.source_org,\n      source_url: d.source_url,\n      visible_signs:',
    'analysis compact official catalog metadata',
)
sub_once(
    'supabase/functions/analyze-case/index.ts',
    r'Rank differentials ONLY by compatibility with visible signs plus supplied history\. Do not choose a disease just because it is common\.',
    'Rank differentials ONLY by compatibility with visible signs plus supplied history. Do not choose a disease just because it is common. For sheep/goats, distinguish lesion morphology carefully: thick proliferative scabs/crusts around the lips or muzzle favor Orf/contagious ecthyma; do NOT relabel thick scabs as FMD vesicles. FMD becomes materially more compatible when true vesicles/erosions are present together with signs such as hypersalivation and/or foot lesions or lameness.',
    'analysis Orf versus FMD morphology rule',
)

# 2) The app waits briefly for a fast official-source verification stage before
# showing the preliminary result. If the verifier is unavailable, it safely keeps
# the original reviewed-catalog result rather than failing the scan.
sub_once(
    'lib/services/vet_backend.dart',
    r"  Future<Map<String, dynamic>> analyzeAssessment\(\n    String assessmentId, \{\n    String language = 'en',\n  \}\) async \{.*?\n  \}\n\}",
    """  Future<Map<String, dynamic>> analyzeAssessment(
    String assessmentId, {
    String language = 'en',
  }) async {
    try {
      final response = await client.functions.invoke(
        'analyze-case',
        body: {'assessment_id': assessmentId, 'language': language},
      );
      final data = response.data;
      Map<String, dynamic>? result;
      if (data is Map<String, dynamic>) {
        result = data;
      } else if (data is Map) {
        result = Map<String, dynamic>.from(data);
      }

      if (result != null &&
          result['code'] == 'AI_ANALYSIS_COMPLETE' &&
          result['group_match'] != 'mismatch') {
        try {
          final verifiedResponse = await client.functions
              .invoke(
                'verify-case-evidence',
                body: {'assessment_id': assessmentId, 'language': language},
              )
              .timeout(const Duration(seconds: 7));
          final verifiedData = verifiedResponse.data;
          Map<String, dynamic>? verified;
          if (verifiedData is Map<String, dynamic>) {
            verified = verifiedData;
          } else if (verifiedData is Map) {
            verified = Map<String, dynamic>.from(verifiedData);
          }
          if (verified != null &&
              verified['code'] == 'AI_ANALYSIS_COMPLETE' &&
              verified['official_evidence_verified'] == true) {
            return verified;
          }
        } catch (_) {
          // Official web verification is an accuracy layer, not a single point
          // of failure. The reviewed local veterinary knowledge result remains.
        }
      }

      if (result != null) return result;
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map<String, dynamic>) return details;
      if (details is Map) return Map<String, dynamic>.from(details);
      return {
        'code': 'AI_FUNCTION_ERROR',
        'risk': 'insufficient_data',
        'message':
            error.reasonPhrase ??
            'The protected AI service could not complete the case.',
      };
    }
    return {
      'code': 'INVALID_AI_RESPONSE',
      'risk': 'insufficient_data',
      'message': 'The protected AI service returned an unreadable response.',
    };
  }
}
""",
    'client official evidence verification',
    re.S,
)

# 3) Configure iOS for spoken playback so auto voice is not silenced by the
# Ring/Silent switch, and prime the audio session before the first auto-speak.
sub_once(
    'lib/analysis/vet_analysis_report.dart',
    r"    _syncQuestions\(\);\n    WidgetsBinding\.instance\.addPostFrameCallback\(\(_\) => _speakCurrent\(\)\);",
    """    _syncQuestions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_configureSpeechAudioSession().then((_) => _speakCurrent()));
    });""",
    'initial automatic speech session',
)
sub_once(
    'lib/analysis/vet_analysis_report.dart',
    r"      _syncQuestions\(\);\n      WidgetsBinding\.instance\.addPostFrameCallback\(\(_\) => _speakCurrent\(\)\);",
    """      _syncQuestions();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_configureSpeechAudioSession().then((_) => _speakCurrent()));
      });""",
    'updated result automatic speech session',
)
sub_once(
    'lib/analysis/vet_analysis_report.dart',
    r"  Future<void> _speakCurrent\(\) async \{",
    """  Future<void> _configureSpeechAudioSession() async {
    try {
      await _audio.setAudioContext(
        AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {AVAudioSessionOptions.duckOthers},
          ),
        ),
      );
    } catch (_) {
      // Continue: some platforms do not need an explicit audio context.
    }
    try {
      await _tts.setSharedInstance(true);
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        const [IosTextToSpeechAudioCategoryOptions.duckOthers],
        IosTextToSpeechAudioMode.spokenAudio,
      );
    } catch (_) {
      // Non-iOS platforms ignore this path.
    }
  }

  Future<void> _speakCurrent() async {""",
    'speech audio session configuration',
)

# Give the natural Egyptian cloud voice one quick retry before falling back to
# the device TTS. This avoids an unnecessary robotic voice on a transient call.
sub_once(
    'lib/analysis/vet_analysis_report.dart',
    r"    try \{\n      await _audio\.stop\(\);\n      await _tts\.stop\(\);\n      final natural = await VetBackend\.instance\.naturalCaseVoice\(\n        text: text,\n        language: widget\.languageCode,\n      \);\n      if \(_muted \|\| !mounted\) return;\n      if \(natural != null && natural\.isNotEmpty\) \{\n        await _audio\.play\(BytesSource\(natural\)\);\n        return;\n      \}\n    \} catch \(_\) \{\n      // Natural network voice was unavailable\.\n    \}",
    """    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _audio.stop();
        await _tts.stop();
        final natural = await VetBackend.instance.naturalCaseVoice(
          text: text,
          language: widget.languageCode,
        );
        if (_muted || !mounted) return;
        if (natural != null && natural.isNotEmpty) {
          await _audio.play(BytesSource(natural));
          return;
        }
      } catch (_) {
        // Retry the natural voice once before using the device fallback.
      }
      if (attempt == 0) await Future<void>.delayed(const Duration(milliseconds: 350));
    }""",
    'natural voice retry before local fallback',
    re.S,
)

# 4) New TestFlight release.
sub_once(
    'pubspec.yaml',
    r'version: 0\.6\.13\+25',
    'version: 0.6.14+26',
    'V28 release version',
)

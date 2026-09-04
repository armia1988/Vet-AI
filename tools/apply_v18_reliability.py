from pathlib import Path


def patch_v5():
    p = Path('lib/v5_app.dart')
    s = p.read_text()
    start = s.index("        SizedBox(\n          height: 116,\n", s.index('class V5Home'))
    marker = "        _Notice(icon: Icons.shield_outlined"
    end = s.index(marker, start)
    header = """        SizedBox(
          height: 74,
          child: Row(
            textDirection: TextDirection.ltr,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const _HeaderBrand(),
              const Spacer(),
              IconButton.filledTonal(
                tooltip: tr(context, 'Language', 'اللغة', 'Taal'),
                style: IconButton.styleFrom(backgroundColor: VetColors.surface3),
                icon: const Icon(Icons.language_rounded, size: 30, color: VetColors.blue),
                onPressed: () => showVetLanguagePicker(context),
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: tr(context, 'Account & settings', 'الحساب والإعدادات', 'Account & instellingen'),
                style: IconButton.styleFrom(backgroundColor: VetColors.surface3),
                icon: const Icon(Icons.account_circle_outlined, size: 31, color: VetColors.primary),
                onPressed: onAccount,
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          farm['farm_name']?.toString() ?? 'Vet AI',
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w900),
        ),
        if ((farm['company_name']?.toString() ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              farm['company_name'].toString(),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: VetColors.muted, fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        const SizedBox(height: 18),
"""
    s = s[:start] + header + s[end:]
    s = s.replace("width: 34, height: 34, fit: BoxFit.contain", "width: 48, height: 48, fit: BoxFit.contain")
    s = s.replace("Image.asset(asset, width: 64, height: 64, fit: BoxFit.contain", "Image.asset(asset, width: 86, height: 86, fit: BoxFit.contain")
    s = s.replace("Image.asset(asset,width:54,height:54,fit:BoxFit.contain", "Image.asset(asset,width:80,height:80,fit:BoxFit.contain")
    s = s.replace("Image.asset(asset,width:62,height:62,fit:BoxFit.contain", "Image.asset(asset,width:92,height:92,fit:BoxFit.contain")
    p.write_text(s)


def patch_backend():
    p = Path('lib/services/vet_backend.dart')
    s = p.read_text()
    start = s.index('  Future<Map<String, dynamic>> analyzeAssessment(')
    end = s.index('\n}', start)
    method = r'''  Future<Map<String, dynamic>> analyzeAssessment(
    String assessmentId, {
    String language = 'en',
  }) async {
    const transientCodes = <String>{
      'AI_PROVIDER_RATE_LIMIT',
      'AI_TIMEOUT',
      'AI_PROVIDER_ERROR',
      'ANALYSIS_INTERNAL_ERROR',
      'AI_EMPTY_RESPONSE',
    };

    Map<String, dynamic>? lastResult;
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await client.functions.invoke(
          'analyze-case',
          body: {
            'assessment_id': assessmentId,
            'language': language,
          },
        );
        final data = response.data;
        final result = data is Map<String, dynamic>
            ? data
            : data is Map
                ? Map<String, dynamic>.from(data)
                : <String, dynamic>{
                    'code': 'INVALID_AI_RESPONSE',
                    'risk': 'insufficient_data',
                    'message': 'The protected AI service returned an unreadable response.',
                  };
        lastResult = result;
        final code = result['code']?.toString() ?? '';
        if (!transientCodes.contains(code) || attempt == 2) return result;
      } on FunctionException catch (error) {
        lastError = error;
        final details = error.details;
        final result = details is Map<String, dynamic>
            ? details
            : details is Map
                ? Map<String, dynamic>.from(details)
                : <String, dynamic>{
                    'code': 'AI_FUNCTION_ERROR',
                    'risk': 'insufficient_data',
                    'message': error.reasonPhrase ?? 'The protected AI service could not complete the case.',
                  };
        lastResult = result;
        final code = result['code']?.toString() ?? '';
        if (!transientCodes.contains(code) || attempt == 2) return result;
      } catch (error) {
        lastError = error;
        if (attempt == 2) break;
      }

      await Future<void>.delayed(Duration(seconds: attempt == 0 ? 2 : 5));
    }

    if (lastResult != null) return lastResult;
    return {
      'code': 'NETWORK_OR_SERVICE_ERROR',
      'risk': 'insufficient_data',
      'message': language.toLowerCase().startsWith('ar')
          ? 'تعذر الوصول إلى خدمة التحليل بعد عدة محاولات آمنة. جرّب مرة أخرى بعد قليل.'
          : language.toLowerCase().startsWith('nl')
              ? 'De analyseservice kon na meerdere veilige pogingen niet worden bereikt. Probeer het zo opnieuw.'
              : 'The analysis service could not be reached after several safe retries. Please try again shortly.',
      if (lastError != null) 'retry_failed': true,
    };
  }
'''
    s = s[:start] + method + s[end:]
    p.write_text(s)


def patch_locale():
    p = Path('lib/i18n/vet_locale.dart')
    s = p.read_text()
    s = s.replace(
        "  final Set<String> _running = {};\n  bool _loaded = false;",
        "  final Set<String> _running = {};\n  final Map<String, DateTime> _cooldownUntil = {};\n  bool _loaded = false;",
    )
    old = """  void _queue(String language, String source) {
    if (!_loaded || source.trim().isEmpty) return;
    final signedIn = Supabase.instance.client.auth.currentSession != null;
    if (!signedIn && !vetCoreUiStrings.contains(source.trim())) return;
    final set = _queued.putIfAbsent(language, () => <String>{});
    set.add(source.trim());
    _timers[language]?.cancel();
    _timers[language] = Timer(const Duration(milliseconds: 90), () => _flush(language));
  }
"""
    new = """  void _queue(String language, String source) {
    if (!_loaded || source.trim().isEmpty) return;
    final cooldown = _cooldownUntil[language];
    if (cooldown != null && DateTime.now().isBefore(cooldown)) return;
    final signedIn = Supabase.instance.client.auth.currentSession != null;
    if (!signedIn && !vetCoreUiStrings.contains(source.trim())) return;
    final set = _queued.putIfAbsent(language, () => <String>{});
    set.add(source.trim());
    _timers[language]?.cancel();
    _timers[language] = Timer(const Duration(milliseconds: 700), () => _flush(language));
  }
"""
    if old not in s:
        raise SystemExit('locale _queue block not found')
    s = s.replace(old, new)
    s = s.replace(
        "      final translated = await _translateBatch(language, sources);\n      if (translated == null) return;",
        "      final translated = await _translateBatch(language, sources);\n      if (translated == null) {\n        _cooldownUntil[language] = DateTime.now().add(const Duration(seconds: 60));\n        _queued.remove(language);\n        return;\n      }\n      _cooldownUntil.remove(language);",
    )
    s = s.replace(
        "_timers[language] = Timer(const Duration(milliseconds: 60), () => _flush(language));",
        "_timers[language] = Timer(const Duration(milliseconds: 700), () => _flush(language));",
    )
    s = s.replace(
        "      final response = await Supabase.instance.client.functions.invoke(\n        'translate-ui',\n        body: {'target_language': language, 'texts': texts},\n      );",
        "      final response = await Supabase.instance.client.functions\n          .invoke(\n            'translate-ui',\n            body: {'target_language': language, 'texts': texts},\n          )\n          .timeout(const Duration(seconds: 9));",
    )
    p.write_text(s)


patch_v5()
patch_backend()
patch_locale()
print('V18 patch applied')

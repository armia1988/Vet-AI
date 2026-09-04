from pathlib import Path

p = Path('lib/analysis/vet_analysis_report.dart')
s = p.read_text()

s = s.replace("import 'package:flutter/material.dart';\n", "import 'package:audioplayers/audioplayers.dart';\nimport 'package:flutter/material.dart';\n")
s = s.replace("import '../services/vet_backend.dart';\n", "import '../services/vet_backend.dart';\nimport '../reports/vet_pdf_report.dart';\n")

s = s.replace(
"""    required this.translate,\n    this.onFinalized,\n  });""",
"""    required this.translate,\n    this.onFinalized,\n    this.onBack,\n  });"""
)
s = s.replace(
"""  final ValueChanged<Map<String, dynamic>>? onFinalized;""",
"""  final ValueChanged<Map<String, dynamic>>? onFinalized;\n  final VoidCallback? onBack;"""
)
s = s.replace(
"""  final FlutterTts _tts = FlutterTts();\n  final Map<String, TextEditingController> _answerControllers = {};""",
"""  final FlutterTts _tts = FlutterTts();\n  final AudioPlayer _audio = AudioPlayer();\n  final Map<String, TextEditingController> _answerControllers = {};"""
)

start = s.index('  Future<void> _speakCurrent() async {')
end = s.index('  Future<void> _toggleMute() async {', start)
new_speak = r'''  Future<void> _speakCurrent() async {
    if (_muted || !mounted) return;
    String text = (_result['voice_summary'] ?? '').toString().trim();
    if (text.isEmpty) {
      final parts = <String>[];
      final summary = (_result['summary'] ?? '').toString().trim();
      if (summary.isNotEmpty) parts.add(summary);
      final differentials = _maps(_result['differential_diagnoses']);
      if (differentials.isNotEmpty) {
        final top = differentials.first;
        final name = (top['name'] ?? '').toString().trim();
        if (name.isNotEmpty) {
          parts.add(widget.translate(
            'Most likely at this stage: $name.',
            'الأكثر احتمالًا دلوقتي: $name.',
            'Meest waarschijnlijk in deze fase: $name.',
          ));
        }
      }
      final actions = _strings(_result['immediate_actions']);
      if (actions.isNotEmpty) {
        parts.add(widget.translate(
          'What to do now: ${actions.first}',
          'تعمل إيه دلوقتي: ${actions.first}',
          'Wat nu te doen: ${actions.first}',
        ));
      }
      text = parts.join(' ');
    }
    if (text.isEmpty) return;

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
      // Fall through to the local device voice.
    }

    try {
      await _tts.stop();
      await _tts.setLanguage(_speechLanguage(widget.languageCode));
      await _tts.setSpeechRate(.47);
      await _tts.setPitch(1.04);
      await _tts.awaitSpeakCompletion(false);
      await _tts.speak(text);
    } catch (_) {
      // The complete written result remains available if audio is unavailable.
    }
  }

'''
s = s[:start] + new_speak + s[end:]

old_toggle = r'''  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    if (_muted) {
      await _tts.stop();
    } else {
      await _speakCurrent();
    }
  }
'''
new_toggle = r'''  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    if (_muted) {
      await _audio.stop();
      await _tts.stop();
    } else {
      await _speakCurrent();
    }
  }
'''
s = s.replace(old_toggle, new_toggle)

s = s.replace(
"""    unawaited(_tts.stop());\n    for (final c in _answerControllers.values) c.dispose();""",
"""    unawaited(_audio.dispose());\n    unawaited(_tts.stop());\n    for (final c in _answerControllers.values) c.dispose();"""
)

s = s.replace(
"""                AnimatedBuilder(\n                  animation: _pulse,\n                  builder: (context, _) => _RiskLight(risk: risk, glow: _pulse.value),\n                ),""",
"""                if (widget.onBack != null) ...[\n                  IconButton(\n                    tooltip: widget.translate('Back to scan', 'رجوع للفحص', 'Terug naar scan'),\n                    onPressed: widget.onBack,\n                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 24),\n                  ),\n                  const SizedBox(width: 2),\n                ],\n                AnimatedBuilder(\n                  animation: _pulse,\n                  builder: (context, _) => _RiskLight(risk: risk, glow: _pulse.value, translate: widget.translate),\n                ),"""
)

s = s.replace(
"""            text: '${top['name'] ?? top['catalog_slug']} • ${top['suspicion'] ?? ''}',""",
"""            text: '${top['name'] ?? top['catalog_slug']} • ${_suspicionLabel((top['suspicion'] ?? '').toString())}',"""
)

marker = '  Widget _finalReport(BuildContext context) {'
start = s.index(marker)
end = s.index('  static List<String> _strings', start)
new_final = r'''  String _suspicionLabel(String value) => switch (value) {
        'high' => widget.translate('high', 'احتمال مرتفع', 'hoog'),
        'moderate' => widget.translate('moderate', 'احتمال متوسط', 'matig'),
        'low' => widget.translate('low', 'احتمال منخفض', 'laag'),
        _ => widget.translate('uncertain', 'غير مؤكد', 'onzeker'),
      };

  String _vetRequirementLabel(String value) => switch (value) {
        'now' => widget.translate('Veterinarian needed NOW', 'محتاج طبيب بيطري فورًا', 'Dierenarts NU nodig'),
        'today' => widget.translate('Veterinarian needed today', 'محتاج طبيب بيطري النهارده', 'Dierenarts vandaag nodig'),
        'soon' => widget.translate('Arrange a veterinary review soon', 'رتّب مراجعة مع طبيب بيطري قريب', 'Plan binnenkort een veterinaire controle'),
        'not_routinely' => widget.translate('A veterinarian is not routinely required unless the condition changes', 'مش محتاج طبيب بشكل روتيني إلا لو الحالة اتغيرت أو ساءت', 'Een dierenarts is niet routinematig nodig tenzij de situatie verandert'),
        _ => widget.translate('Veterinary need depends on confirmation and progression', 'الحاجة لطبيب بتعتمد على التأكيد وتطور الحالة', 'Veterinaire noodzaak hangt af van bevestiging en verloop'),
      };

  Widget _finalReport(BuildContext context) {
    final primary = _result['primary_condition'] is Map
        ? Map<String, dynamic>.from(_result['primary_condition'] as Map)
        : <String, dynamic>{};
    final verified = _result['evidence_verified'] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SummaryBox(text: (_result['summary'] ?? '').toString()),
        const SizedBox(height: 14),
        _KeyValueSection(
          icon: Icons.coronavirus_outlined,
          color: VetColors.blue,
          title: widget.translate('Disease / most likely condition', 'المرض / الحالة الأكثر احتمالًا', 'Ziekte / meest waarschijnlijke aandoening'),
          text: '${primary['name'] ?? ''}\n${primary['why'] ?? ''}',
        ),
        _KeyValueSection(
          icon: Icons.science_outlined,
          color: VetColors.purple,
          title: widget.translate('Cause', 'السبب', 'Oorzaak'),
          text: (_result['cause'] ?? '').toString(),
        ),
        _KeyValueSection(
          icon: Icons.local_hospital_rounded,
          color: VetColors.orange,
          title: widget.translate('Does this need a veterinarian?', 'هل الحالة محتاجة طبيب بيطري؟', 'Is een dierenarts nodig?'),
          text: '${_vetRequirementLabel((_result['vet_required'] ?? '').toString())}\n${_result['vet_required_reason'] ?? ''}',
        ),
        if (_strings(_result['topical_or_external_care']).isNotEmpty)
          _ListSection(
            icon: Icons.healing_rounded,
            color: VetColors.green,
            title: widget.translate('External / topical care', 'العناية أو العلاج الخارجي الموضعي', 'Uitwendige / lokale verzorging'),
            items: _strings(_result['topical_or_external_care']),
          ),
        _ListSection(
          icon: Icons.medical_services_outlined,
          color: VetColors.green,
          title: widget.translate('Treatment & management', 'العلاج والتعامل', 'Behandeling & management'),
          items: _strings(_result['treatment_and_management']),
        ),
        _ListSection(
          icon: Icons.directions_run_rounded,
          color: VetColors.orange,
          title: widget.translate('What you should do now', 'تعمل إيه دلوقتي؟', 'Wat je nu moet doen'),
          items: _strings(_result['what_to_do_now']),
        ),
        _ListSection(
          icon: Icons.shield_outlined,
          color: VetColors.history,
          title: widget.translate('Prevention', 'الوقاية', 'Preventie'),
          items: _strings(_result['prevention']),
        ),
        _ListSection(
          icon: Icons.local_hospital_outlined,
          color: VetColors.blue,
          title: widget.translate('Veterinary next steps', 'الخطوات البيطرية التالية', 'Volgende veterinaire stappen'),
          items: _strings(_result['veterinary_next_steps']),
        ),
        if (_strings(_result['red_flags']).isNotEmpty)
          _ListSection(
            icon: Icons.warning_rounded,
            color: VetColors.red,
            title: widget.translate('Danger signs', 'علامات الخطر', 'Alarmsignalen'),
            items: _strings(_result['red_flags']),
          ),
        _ListSection(
          icon: Icons.biotech_outlined,
          color: VetColors.purple,
          title: widget.translate('How to confirm', 'إزاي نتأكد؟', 'Hoe te bevestigen'),
          items: _strings(_result['confirmation_plan']),
        ),
        if ((_result['food_animal_medicine_note'] ?? '').toString().trim().isNotEmpty)
          _KeyValueSection(
            icon: Icons.gpp_maybe_outlined,
            color: VetColors.history,
            title: widget.translate('Medicine safety note', 'تنبيه مهم بخصوص الأدوية', 'Veiligheidsnotitie medicijnen'),
            text: _result['food_animal_medicine_note'].toString(),
          ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: verified ? VetColors.softGreen : VetColors.surface2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: verified ? VetColors.green : VetColors.border),
          ),
          child: Row(children: [
            Icon(verified ? Icons.verified_rounded : Icons.fact_check_outlined, color: verified ? VetColors.green : VetColors.muted, size: 27),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                verified
                    ? widget.translate(
                        'Evidence cross-check completed using authoritative veterinary and regulatory sources. Website links are intentionally hidden from the customer report.',
                        'تمت مراجعة الحالة على مصادر بيطرية ورقابية موثوقة. روابط المواقع مش بتظهر في تقرير العميل عمدًا.',
                        'De casus is gecontroleerd aan de hand van gezaghebbende veterinaire en regelgevende bronnen. Websitelinks worden bewust verborgen in het klantverslag.')
                    : widget.translate(
                        'No external evidence verification flag was returned. Treat the report as provisional.',
                        'ماوصلش تأكيد مراجعة المصادر الخارجية، فاعتبر التقرير مبدئي لحد مراجعة طبيب.',
                        'Er is geen externe verificatie teruggekomen. Behandel het rapport als voorlopig.'),
                style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => VetPdfReportScreen(
                report: _result,
                languageCode: widget.languageCode,
                translate: widget.translate,
              ),
            ),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: VetColors.purple,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(56),
          ),
          icon: const Icon(Icons.picture_as_pdf_rounded, size: 28),
          label: Text(widget.translate('Open / share PDF report', 'فتح أو مشاركة تقرير PDF', 'PDF-rapport openen / delen')),
        ),
        const SizedBox(height: 14),
        Text(
          (_result['confidence_statement'] ?? '').toString(),
          style: const TextStyle(color: VetColors.muted, fontStyle: FontStyle.italic, height: 1.4),
        ),
      ],
    );
  }

'''
s = s[:start] + new_final + s[end:]

s = s.replace(
"""class _RiskLight extends StatelessWidget {\n  const _RiskLight({required this.risk, required this.glow});\n  final String risk;\n  final double glow;""",
"""class _RiskLight extends StatelessWidget {\n  const _RiskLight({required this.risk, required this.glow, required this.translate});\n  final String risk;\n  final double glow;\n  final VetUiTranslate translate;"""
)
s = s.replace(
"""      child: Text(risk.replaceAll('_', ' ').toUpperCase(), style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 11)),""",
"""      child: Text(\n        switch (risk) {\n          'red' => translate('RED', 'أحمر', 'ROOD'),\n          'orange' => translate('ORANGE', 'برتقالي', 'ORANJE'),\n          'yellow' => translate('YELLOW', 'أصفر', 'GEEL'),\n          'none' => translate('GREEN', 'أخضر', 'GROEN'),\n          _ => translate('MORE DATA', 'بيانات ناقصة', 'MEER DATA'),\n        },\n        style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 10.5),\n      ),"""
)

p.write_text(s)

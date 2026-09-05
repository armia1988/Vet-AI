import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../services/vet_backend.dart';
import '../reports/vet_pdf_report.dart';
import '../services/vet_case_workflow.dart';
import '../theme/app_theme.dart';

typedef VetUiTranslate = String Function(String en, String ar, String nl);

class VetAnalysisReportCard extends StatefulWidget {
  const VetAnalysisReportCard({
    super.key,
    required this.initialResult,
    required this.assessmentId,
    required this.languageCode,
    required this.translate,
    this.onFinalized,
    this.onBack,
  });

  final Map<String, dynamic> initialResult;
  final String assessmentId;
  final String languageCode;
  final VetUiTranslate translate;
  final ValueChanged<Map<String, dynamic>>? onFinalized;
  final VoidCallback? onBack;

  @override
  State<VetAnalysisReportCard> createState() => _VetAnalysisReportCardState();
}

class _VetAnalysisReportCardState extends State<VetAnalysisReportCard>
    with SingleTickerProviderStateMixin {
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _audio = AudioPlayer();
  final Map<String, TextEditingController> _answerControllers = {};
  late Map<String, dynamic> _result;
  late final AnimationController _pulse;
  bool _muted = false;
  bool _finalizing = false;
  String? _finalError;

  bool get _isFinal => _result['code'] == 'FINAL_REPORT_COMPLETE';
  bool get _isEnglish => widget.languageCode.toLowerCase().startsWith('en');

  @override
  void initState() {
    super.initState();
    _result = Map<String, dynamic>.from(widget.initialResult);
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: .18,
      upperBound: .48,
    )..repeat(reverse: true);
    _syncQuestions();
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakCurrent());
  }

  @override
  void didUpdateWidget(covariant VetAnalysisReportCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialResult != widget.initialResult) {
      _result = Map<String, dynamic>.from(widget.initialResult);
      _syncQuestions();
      WidgetsBinding.instance.addPostFrameCallback((_) => _speakCurrent());
    }
  }

  void _syncQuestions() {
    final current = _strings(_result['follow_up_questions']).toSet();
    for (final question in current) {
      _answerControllers.putIfAbsent(question, TextEditingController.new);
    }
    final removed = _answerControllers.keys
        .where((q) => !current.contains(q))
        .toList();
    for (final q in removed) {
      _answerControllers.remove(q)?.dispose();
    }
  }

  String _speechLanguage(String code) {
    final normalized = code.toLowerCase();
    if (normalized == 'ar') return 'ar-SA';
    if (normalized == 'nl') return 'nl-NL';
    if (normalized == 'de') return 'de-DE';
    if (normalized == 'fr') return 'fr-FR';
    if (normalized == 'es') return 'es-ES';
    if (normalized == 'it') return 'it-IT';
    if (normalized == 'pt') return 'pt-PT';
    if (normalized == 'zh') return 'zh-CN';
    if (normalized == 'ja') return 'ja-JP';
    if (normalized == 'ko') return 'ko-KR';
    if (normalized == 'hi') return 'hi-IN';
    if (normalized == 'tr') return 'tr-TR';
    if (normalized == 'ru') return 'ru-RU';
    return normalized;
  }

  Future<void> _speakCurrent() async {
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
          parts.add(
            widget.translate(
              'Most likely at this stage: $name.',
              'الأكثر احتمالًا دلوقتي: $name.',
              'Meest waarschijnlijk in deze fase: $name.',
            ),
          );
        }
      }
      final actions = _strings(_result['immediate_actions']);
      if (actions.isNotEmpty) {
        parts.add(
          widget.translate(
            'What to do now: ${actions.first}',
            'تعمل إيه دلوقتي: ${actions.first}',
            'Wat nu te doen: ${actions.first}',
          ),
        );
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

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    if (_muted) {
      await _audio.stop();
      await _tts.stop();
    } else {
      await _speakCurrent();
    }
  }

  void _quickAnswer(String question, String value) {
    final controller = _answerControllers[question];
    if (controller == null) return;
    controller.text = value;
    setState(() {});
  }

  Future<void> _finalize() async {
    if (_finalizing) return;
    final answers = <Map<String, String>>[];
    for (final entry in _answerControllers.entries) {
      final answer = entry.value.text.trim();
      if (answer.isNotEmpty)
        answers.add({'question': entry.key, 'answer': answer});
    }
    setState(() {
      _finalizing = true;
      _finalError = null;
    });
    try {
      final response = await VetBackend.instance.finalizeAssessment(
        widget.assessmentId,
        language: widget.languageCode,
        answers: answers,
      );
      if (!mounted) return;
      if (response['code'] == 'FINAL_REPORT_COMPLETE') {
        setState(() {
          _result = response;
          _finalizing = false;
          _finalError = null;
        });
        widget.onFinalized?.call(response);
        await _speakCurrent();
      } else {
        setState(() {
          _finalizing = false;
          _finalError =
              (response['message'] ??
                      widget.translate(
                        'The verified final report could not be completed.',
                        'تعذر إكمال التقرير النهائي الموثق.',
                        'Het geverifieerde eindrapport kon niet worden voltooid.',
                      ))
                  .toString();
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _finalizing = false;
        _finalError = widget.translate(
          'The final evidence review could not be reached. Try again.',
          'تعذر الوصول إلى مراجعة الأدلة النهائية. حاول مرة أخرى.',
          'De definitieve bronnencontrole kon niet worden bereikt. Probeer opnieuw.',
        );
      });
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    unawaited(_audio.dispose());
    unawaited(_tts.stop());
    for (final c in _answerControllers.values) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final risk = (_result['risk'] ?? 'insufficient_data').toString();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (widget.onBack != null) ...[
                  IconButton(
                    tooltip: widget.translate(
                      'Back to scan',
                      'رجوع للفحص',
                      'Terug naar scan',
                    ),
                    onPressed: widget.onBack,
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 2),
                ],
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) => _RiskLight(
                    risk: risk,
                    glow: _pulse.value,
                    translate: widget.translate,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _isFinal
                        ? widget.translate(
                            'Final verified report',
                            'التقرير النهائي الموثق',
                            'Definitief geverifieerd rapport',
                          )
                        : widget.translate(
                            'Fast preliminary assessment',
                            'التقييم الأولي السريع',
                            'Snelle voorlopige beoordeling',
                          ),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: _muted
                      ? widget.translate(
                          'Turn sound on',
                          'تشغيل الصوت',
                          'Geluid aan',
                        )
                      : widget.translate(
                          'Mute result',
                          'كتم النتيجة',
                          'Resultaat dempen',
                        ),
                  onPressed: _toggleMute,
                  icon: Icon(
                    _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    size: 29,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isFinal) _finalReport(context) else _triageReport(context),
          ],
        ),
      ),
    );
  }

  Widget _triageReport(BuildContext context) {
    final differentials = _maps(_result['differential_diagnoses']);
    final top = differentials.isEmpty ? null : differentials.first;
    final questions = _strings(_result['follow_up_questions']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SummaryBox(text: (_result['summary'] ?? '').toString()),
        if (top != null) ...[
          const SizedBox(height: 16),
          _KeyValueSection(
            icon: Icons.coronavirus_outlined,
            color: VetColors.blue,
            title: widget.translate(
              'Most likely at this stage',
              'الأكثر احتمالًا في هذه المرحلة',
              'Meest waarschijnlijk in deze fase',
            ),
            text:
                '${top['name'] ?? top['catalog_slug']} • ${_suspicionLabel((top['suspicion'] ?? '').toString())}',
          ),
          if (_isEnglish && (top['cause'] ?? '').toString().trim().isNotEmpty)
            _KeyValueSection(
              icon: Icons.science_outlined,
              color: VetColors.purple,
              title: widget.translate('Cause', 'السبب', 'Oorzaak'),
              text: top['cause'].toString(),
            ),
          if (_isEnglish &&
              (top['treatment_summary'] ?? '').toString().trim().isNotEmpty)
            _KeyValueSection(
              icon: Icons.medical_services_outlined,
              color: VetColors.green,
              title: widget.translate(
                'Treatment / management',
                'العلاج / التعامل',
                'Behandeling / management',
              ),
              text: top['treatment_summary'].toString(),
            ),
          if (_isEnglish &&
              (top['prevention_summary'] ?? '').toString().trim().isNotEmpty)
            _KeyValueSection(
              icon: Icons.shield_outlined,
              color: VetColors.history,
              title: widget.translate('Prevention', 'الوقاية', 'Preventie'),
              text: top['prevention_summary'].toString(),
            ),
          if (!_isEnglish)
            _KeyValueSection(
              icon: Icons.translate_rounded,
              color: VetColors.primary,
              title: widget.translate(
                'Localized details',
                'التفاصيل بنفس لغة الهاتف',
                'Details in de taal van je telefoon',
              ),
              text: widget.translate(
                'Cause, treatment and prevention details are shown in the final verified report after they are localized into your phone language.',
                'تفاصيل السبب والعلاج والوقاية هتظهر كاملة في التقرير النهائي الموثق بعد تحويلها لنفس لغة الهاتف، من غير خلط إنجليزي.',
                'Oorzaak, behandeling en preventie verschijnen volledig in het definitieve rapport nadat ze naar de taal van je telefoon zijn omgezet.',
              ),
            ),
        ],
        if (_strings(_result['immediate_actions']).isNotEmpty) ...[
          const SizedBox(height: 16),
          _ListSection(
            icon: Icons.first_page_rounded,
            color: VetColors.orange,
            title: widget.translate(
              'What to do now',
              'ماذا تفعل الآن',
              'Wat nu te doen',
            ),
            items: _strings(_result['immediate_actions']),
          ),
        ],
        if (questions.isNotEmpty) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              const Icon(
                Icons.question_answer_outlined,
                size: 28,
                color: VetColors.blue,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  widget.translate(
                    'Answer these to improve the report',
                    'أجب عن هذه الأسئلة لتحسين التقرير',
                    'Beantwoord dit om het rapport te verbeteren',
                  ),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final question in questions)
            _QuestionEditor(
              question: question,
              controller: _answerControllers[question]!,
              translate: widget.translate,
              onQuickAnswer: (value) => _quickAnswer(question, value),
            ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _finalizing ? null : _finalize,
            style: FilledButton.styleFrom(
              backgroundColor: VetColors.blue,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(58),
            ),
            icon: _finalizing
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.fact_check_outlined, size: 28),
            label: Text(
              _finalizing
                  ? widget.translate(
                      'Checking trusted sources…',
                      'جاري مراجعة المصادر الموثوقة…',
                      'Betrouwbare bronnen controleren…',
                    )
                  : widget.translate(
                      'Send answers & create final report',
                      'إرسال الإجابات وإنشاء التقرير النهائي',
                      'Antwoorden verzenden & eindrapport maken',
                    ),
            ),
          ),
          if (_finalError != null) ...[
            const SizedBox(height: 10),
            _ErrorBox(text: _finalError!),
          ],
        ],
        if (questions.isEmpty) ...[
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _finalizing ? null : _finalize,
            style: FilledButton.styleFrom(
              backgroundColor: VetColors.blue,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(58),
            ),
            icon: _finalizing
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.fact_check_outlined, size: 28),
            label: Text(
              _finalizing
                  ? widget.translate(
                      'Checking trusted sources…',
                      'جاري مراجعة المصادر الموثوقة…',
                      'Betrouwbare bronnen controleren…',
                    )
                  : widget.translate(
                      'Create final verified report',
                      'إنشاء التقرير النهائي الموثق',
                      'Definitief geverifieerd rapport maken',
                    ),
            ),
          ),
          if (_finalError != null) ...[
            const SizedBox(height: 10),
            _ErrorBox(text: _finalError!),
          ],
        ],
      ],
    );
  }

  String _suspicionLabel(String value) => switch (value) {
    'high' => widget.translate('high', 'احتمال مرتفع', 'hoog'),
    'moderate' => widget.translate('moderate', 'احتمال متوسط', 'matig'),
    'low' => widget.translate('low', 'احتمال منخفض', 'laag'),
    _ => widget.translate('uncertain', 'غير مؤكد', 'onzeker'),
  };

  String _vetRequirementLabel(String value) => switch (value) {
    'now' => widget.translate(
      'Veterinarian needed NOW',
      'محتاج طبيب بيطري فورًا',
      'Dierenarts NU nodig',
    ),
    'today' => widget.translate(
      'Veterinarian needed today',
      'محتاج طبيب بيطري النهارده',
      'Dierenarts vandaag nodig',
    ),
    'soon' => widget.translate(
      'Arrange a veterinary review soon',
      'رتّب مراجعة مع طبيب بيطري قريب',
      'Plan binnenkort een veterinaire controle',
    ),
    'not_routinely' => widget.translate(
      'A veterinarian is not routinely required unless the condition changes',
      'مش محتاج طبيب بشكل روتيني إلا لو الحالة اتغيرت أو ساءت',
      'Een dierenarts is niet routinematig nodig tenzij de situatie verandert',
    ),
    _ => widget.translate(
      'Veterinary need depends on confirmation and progression',
      'الحاجة لطبيب بتعتمد على التأكيد وتطور الحالة',
      'Veterinaire noodzaak hangt af van bevestiging en verloop',
    ),
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
          title: widget.translate(
            'Disease / most likely condition',
            'المرض / الحالة الأكثر احتمالًا',
            'Ziekte / meest waarschijnlijke aandoening',
          ),
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
          title: widget.translate(
            'Does this need a veterinarian?',
            'هل الحالة محتاجة طبيب بيطري؟',
            'Is een dierenarts nodig?',
          ),
          text:
              '${_vetRequirementLabel((_result['vet_required'] ?? '').toString())}\n${_result['vet_required_reason'] ?? ''}',
        ),
        if (_strings(_result['topical_or_external_care']).isNotEmpty)
          _ListSection(
            icon: Icons.healing_rounded,
            color: VetColors.green,
            title: widget.translate(
              'External / topical care',
              'العناية أو العلاج الخارجي الموضعي',
              'Uitwendige / lokale verzorging',
            ),
            items: _strings(_result['topical_or_external_care']),
          ),
        _ListSection(
          icon: Icons.medical_services_outlined,
          color: VetColors.green,
          title: widget.translate(
            'Treatment & management',
            'العلاج والتعامل',
            'Behandeling & management',
          ),
          items: _strings(_result['treatment_and_management']),
        ),
        _ListSection(
          icon: Icons.directions_run_rounded,
          color: VetColors.orange,
          title: widget.translate(
            'What you should do now',
            'تعمل إيه دلوقتي؟',
            'Wat je nu moet doen',
          ),
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
          title: widget.translate(
            'Veterinary next steps',
            'الخطوات البيطرية التالية',
            'Volgende veterinaire stappen',
          ),
          items: _strings(_result['veterinary_next_steps']),
        ),
        if (_strings(_result['red_flags']).isNotEmpty)
          _ListSection(
            icon: Icons.warning_rounded,
            color: VetColors.red,
            title: widget.translate(
              'Danger signs',
              'علامات الخطر',
              'Alarmsignalen',
            ),
            items: _strings(_result['red_flags']),
          ),
        _ListSection(
          icon: Icons.biotech_outlined,
          color: VetColors.purple,
          title: widget.translate(
            'How to confirm',
            'إزاي نتأكد؟',
            'Hoe te bevestigen',
          ),
          items: _strings(_result['confirmation_plan']),
        ),
        if ((_result['food_animal_medicine_note'] ?? '')
            .toString()
            .trim()
            .isNotEmpty)
          _KeyValueSection(
            icon: Icons.gpp_maybe_outlined,
            color: VetColors.history,
            title: widget.translate(
              'Medicine safety note',
              'تنبيه مهم بخصوص الأدوية',
              'Veiligheidsnotitie medicijnen',
            ),
            text: _result['food_animal_medicine_note'].toString(),
          ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: verified ? VetColors.softGreen : VetColors.surface2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: verified ? VetColors.green : VetColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                verified ? Icons.verified_rounded : Icons.fact_check_outlined,
                color: verified ? VetColors.green : VetColors.muted,
                size: 27,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  verified
                      ? widget.translate(
                          'Evidence cross-check completed using authoritative veterinary and regulatory sources. Website links are intentionally hidden from the customer report.',
                          'تمت مراجعة الحالة على مصادر بيطرية ورقابية موثوقة. روابط المواقع مش بتظهر في تقرير العميل عمدًا.',
                          'De casus is gecontroleerd aan de hand van gezaghebbende veterinaire en regelgevende bronnen. Websitelinks worden bewust verborgen in het klantverslag.',
                        )
                      : widget.translate(
                          'No external evidence verification flag was returned. Treat the report as provisional.',
                          'ماوصلش تأكيد مراجعة المصادر الخارجية، فاعتبر التقرير مبدئي لحد مراجعة طبيب.',
                          'Er is geen externe verificatie teruggekomen. Behandel het rapport als voorlopig.',
                        ),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
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
          label: Text(
            widget.translate(
              'Open / share PDF report',
              'فتح أو مشاركة تقرير PDF',
              'PDF-rapport openen / delen',
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          (_result['confidence_statement'] ?? '').toString(),
          style: const TextStyle(
            color: VetColors.muted,
            fontSize: 15,
            fontStyle: FontStyle.italic,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  static List<String> _strings(dynamic value) => value is List
      ? value
            .map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList()
      : <String>[];

  static List<Map<String, dynamic>> _maps(dynamic value) => value is List
      ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];
}

class _QuestionEditor extends StatelessWidget {
  const _QuestionEditor({
    required this.question,
    required this.controller,
    required this.translate,
    required this.onQuickAnswer,
  });
  final String question;
  final TextEditingController controller;
  final VetUiTranslate translate;
  final ValueChanged<String> onQuickAnswer;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: VetColors.surface2,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: VetColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            ActionChip(
              label: Text(translate('Yes', 'نعم', 'Ja')),
              onPressed: () => onQuickAnswer(translate('Yes', 'نعم', 'Ja')),
            ),
            ActionChip(
              label: Text(translate('No', 'لا', 'Nee')),
              onPressed: () => onQuickAnswer(translate('No', 'لا', 'Nee')),
            ),
            ActionChip(
              label: Text(translate('Unknown', 'غير معروف', 'Onbekend')),
              onPressed: () =>
                  onQuickAnswer(translate('Unknown', 'غير معروف', 'Onbekend')),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          minLines: 1,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: translate(
              'Type the answer, duration, date or extra detail…',
              'اكتب الإجابة أو المدة أو التاريخ أو تفاصيل إضافية…',
              'Typ het antwoord, de duur, datum of extra details…',
            ),
            prefixIcon: const Icon(Icons.edit_note_rounded),
          ),
        ),
      ],
    ),
  );
}

class _RiskLight extends StatelessWidget {
  const _RiskLight({
    required this.risk,
    required this.glow,
    required this.translate,
  });
  final String risk;
  final double glow;
  final VetUiTranslate translate;

  @override
  Widget build(BuildContext context) {
    final color = switch (risk) {
      'red' => VetColors.red,
      'orange' => VetColors.orange,
      'yellow' => VetColors.yellow,
      'none' => VetColors.green,
      _ => VetColors.muted,
    };
    return Container(
      width: 62,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: glow),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color, width: 1.6),
        boxShadow: [
          if (risk == 'red' || risk == 'orange')
            BoxShadow(
              color: color.withValues(alpha: glow),
              blurRadius: 18,
              spreadRadius: 2,
            ),
        ],
      ),
      child: Text(
        switch (risk) {
          'red' => translate('RED', 'أحمر', 'ROOD'),
          'orange' => translate('ORANGE', 'برتقالي', 'ORANJE'),
          'yellow' => translate('YELLOW', 'أصفر', 'GEEL'),
          'none' => translate('GREEN', 'أخضر', 'GROEN'),
          _ => translate('MORE DATA', 'بيانات ناقصة', 'MEER DATA'),
        },
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 10.5,
        ),
      ),
    );
  }
}

class _SummaryBox extends StatelessWidget {
  const _SummaryBox({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: VetColors.surface3,
      borderRadius: BorderRadius.circular(17),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        height: 1.55,
      ),
    ),
  );
}

class _KeyValueSection extends StatelessWidget {
  const _KeyValueSection({
    required this.icon,
    required this.color,
    required this.title,
    required this.text,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 29),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 19,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  text,
                  style: const TextStyle(fontSize: 16.5, height: 1.55),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ListSection extends StatelessWidget {
  const _ListSection({
    required this.icon,
    required this.color,
    required this.title,
    required this.items,
  });
  final IconData icon;
  final Color color;
  final String title;
  final List<String> items;
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 9),
                    child: Icon(Icons.circle, size: 8, color: color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(fontSize: 16.5, height: 1.52),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: VetColors.red.withValues(alpha: .11),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: VetColors.red),
    ),
    child: Text(text, style: const TextStyle(height: 1.4)),
  );
}

from pathlib import Path

path = Path('lib/health/animal_health_center.dart')
text = path.read_text(encoding='utf-8')

if "import 'package:image_picker/image_picker.dart';" not in text:
    text = text.replace(
        "import 'package:flutter/material.dart';\n",
        "import 'package:flutter/material.dart';\nimport 'package:image_picker/image_picker.dart';\n",
        1,
    )

if "import 'ai_followup_service.dart';" not in text:
    anchor = "import 'animal_health_service.dart';\n"
    if anchor not in text:
        raise SystemExit('V101 service import anchor not found')
    text = text.replace(anchor, anchor + "import 'ai_followup_service.dart';\n", 1)

text = text.replace('      length: 3,\n', '      length: 4,\n', 1)

followup_tab_marker = "text: _t(context, 'Follow-up', 'المتابعة', 'Follow-up')"
if followup_tab_marker not in text:
    anchor = """              Tab(
                icon: const Icon(Icons.medication_rounded),
                text: _t(context, 'Care', 'العلاج', 'Zorg'),
              ),
"""
    replacement = anchor + """              Tab(
                icon: const Icon(Icons.timeline_rounded),
                text: _t(context, 'Follow-up', 'المتابعة', 'Follow-up'),
              ),
"""
    if anchor not in text:
        raise SystemExit('V101 tab anchor not found')
    text = text.replace(anchor, replacement, 1)

if '_FollowUpTab(farmId: farmId),' not in text:
    anchor = """            _OverviewTab(farmId: farmId),
            _AnimalsTab(farmId: farmId),
            _CareTab(farmId: farmId),
"""
    replacement = anchor + "            _FollowUpTab(farmId: farmId),\n"
    if anchor not in text:
        raise SystemExit('V101 TabBarView anchor not found')
    text = text.replace(anchor, replacement, 1)

if 'class _FollowUpTab extends StatefulWidget' not in text:
    anchor = 'class _EmptyCard extends StatelessWidget {'
    if anchor not in text:
        raise SystemExit('V101 follow-up class insertion anchor not found')
    followup_code = r'''class _FollowUpTab extends StatefulWidget {
  const _FollowUpTab({required this.farmId});

  final String farmId;

  @override
  State<_FollowUpTab> createState() => _FollowUpTabState();
}

class _FollowUpTabState extends State<_FollowUpTab> {
  bool loading = true;
  Object? error;
  List<Map<String, dynamic>> rows = const [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Map<String, dynamic> _nested(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  String _followupAnimal(Map<String, dynamic> row) {
    final animal = _nested(row['animals']);
    return _animalLabel(animal);
  }

  String _baselineSummary(Map<String, dynamic> row) {
    final assessment = _nested(row['assessments']);
    final ai = _nested(assessment['ai_analysis']);
    final summary = '${ai['summary'] ?? assessment['symptom_notes'] ?? ''}'.trim();
    return summary;
  }

  Future<void> load() async {
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final next = await AiFollowupService.instance.followups(widget.farmId);
      if (mounted) setState(() => rows = next);
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _trendLabel(BuildContext context, String value) {
    switch (value) {
      case 'better':
        return _t(context, 'Improving', 'يتحسن', 'Verbetering');
      case 'same':
        return _t(context, 'No clear change', 'بدون تغير واضح', 'Geen duidelijke verandering');
      case 'worse':
        return _t(context, 'Worsening', 'يتدهور', 'Verslechtering');
      default:
        return _t(context, 'Uncertain', 'غير مؤكد', 'Onzeker');
    }
  }

  Color _trendColor(BuildContext context, String value) {
    final scheme = Theme.of(context).colorScheme;
    if (value == 'worse') return scheme.error;
    if (value == 'better') return scheme.primary;
    return scheme.secondary;
  }

  Future<ImageSource?> _chooseSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: Text(_t(context, 'Take a new photo', 'التقط صورة جديدة', 'Nieuwe foto maken')),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: Text(_t(context, 'Choose from photos', 'اختر من الصور', 'Kies uit foto’s')),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startFollowup(Map<String, dynamic> row) async {
    final source = await _chooseSource();
    if (source == null || !mounted) return;

    final image = await ImagePicker().pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 1800,
    );
    if (image == null || !mounted) return;

    final notes = TextEditingController();
    final temperature = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t(context, 'AI follow-up', 'متابعة بالذكاء الاصطناعي', 'AI-follow-up')),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _t(
                    context,
                    'Vet AI will compare this photo with the original assessment image. Add current symptoms and temperature if available.',
                    'سيقوم Vet AI بمقارنة هذه الصورة بصورة التقييم الأصلية. أضف الأعراض الحالية ودرجة الحرارة إذا كانت متاحة.',
                    'Vet AI vergelijkt deze foto met de oorspronkelijke beoordelingsfoto. Voeg huidige symptomen en temperatuur toe indien beschikbaar.',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: temperature,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: _t(context, 'Temperature °C (optional)', 'درجة الحرارة °C (اختياري)', 'Temperatuur °C (optioneel)'),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notes,
                  minLines: 3,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: _t(context, 'Current symptoms / changes', 'الأعراض أو التغيرات الحالية', 'Huidige symptomen / veranderingen'),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_t(context, 'Cancel', 'إلغاء', 'Annuleren')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.auto_awesome_rounded),
            label: Text(_t(context, 'Compare now', 'قارن الآن', 'Nu vergelijken')),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      notes.dispose();
      temperature.dispose();
      return;
    }

    final bytes = await image.readAsBytes();
    final name = image.name.toLowerCase();
    final extension = name.contains('.') ? name.split('.').last : 'jpg';
    final language = Localizations.localeOf(context).languageCode;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(
              child: Text(_t(context, 'Comparing follow-up…', 'جاري مقارنة المتابعة…', 'Follow-up vergelijken…')),
            ),
          ],
        ),
      ),
    );

    try {
      final result = await AiFollowupService.instance.submitFollowup(
        followup: row,
        imageBytes: bytes,
        extension: extension,
        language: language,
        symptomNotes: notes.text,
        temperatureC: double.tryParse(temperature.text.replaceAll(',', '.')),
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await _showResult(result);
      await load();
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        _showError(context, e);
      }
    } finally {
      notes.dispose();
      temperature.dispose();
    }
  }

  Future<void> _showResult(Map<String, dynamic> result) {
    final trend = '${result['trend'] ?? 'uncertain'}';
    final redFlags = result['red_flags'] is List ? List.from(result['red_flags'] as List) : const [];
    final actions = result['next_actions'] is List ? List.from(result['next_actions'] as List) : const [];
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.auto_awesome_rounded, color: _trendColor(context, trend)),
            const SizedBox(width: 8),
            Expanded(child: Text(_trendLabel(context, trend))),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if ('${result['visual_change_summary'] ?? ''}'.trim().isNotEmpty)
                  Text('${result['visual_change_summary']}'),
                if ('${result['symptom_change_summary'] ?? ''}'.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('${result['symptom_change_summary']}'),
                ],
                if ('${result['temperature_interpretation'] ?? ''}'.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('${result['temperature_interpretation']}'),
                ],
                if (redFlags.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    _t(context, 'Red flags', 'علامات الخطر', 'Alarmsignalen'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  ...redFlags.map((item) => Text('• $item')),
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    _t(context, 'Next actions', 'الخطوات التالية', 'Volgende stappen'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  ...actions.map((item) => Text('• $item')),
                ],
                if (result['urgent_vet_review'] == true) ...[
                  const SizedBox(height: 14),
                  Text(
                    _t(context, 'Veterinary review is recommended.', 'يوصى بمراجعة طبيب بيطري.', 'Controle door een dierenarts wordt aanbevolen.'),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_t(context, 'Done', 'تم', 'Gereed')),
          ),
        ],
      ),
    );
  }

  Future<void> _skip(Map<String, dynamic> row) async {
    try {
      await AiFollowupService.instance.skipFollowup(row);
      await load();
    } catch (e) {
      if (mounted) _showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) return _ErrorPane(message: '$error', onRetry: load);

    final pending = rows.where((row) => row['status'] == 'pending').toList();
    final completed = rows.where((row) => row['status'] == 'completed').toList().reversed.toList();

    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.auto_awesome_rounded),
              title: Text(
                _t(context, '12 / 24 / 48 hour AI follow-up', 'متابعة AI بعد 12 / 24 / 48 ساعة', 'AI-follow-up na 12 / 24 / 48 uur'),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(
                _t(
                  context,
                  'After an AI assessment, Vet AI schedules three follow-ups and compares the new photo, symptoms and temperature with the original case.',
                  'بعد تقييم AI يقوم Vet AI بجدولة ثلاث متابعات ويقارن الصورة الجديدة والأعراض ودرجة الحرارة بالحالة الأصلية.',
                  'Na een AI-beoordeling plant Vet AI drie follow-ups en vergelijkt de nieuwe foto, symptomen en temperatuur met de oorspronkelijke casus.',
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _t(context, 'Pending follow-ups', 'المتابعات المطلوبة', 'Openstaande follow-ups'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          if (pending.isEmpty)
            _EmptyCard(
              text: _t(context, 'No follow-up is due right now.', 'لا توجد متابعة مطلوبة حاليًا.', 'Er is nu geen follow-up nodig.'),
            )
          else
            ...pending.map((row) {
              final due = _parseDate(row['due_at']);
              final overdue = due != null && due.isBefore(DateTime.now());
              final summary = _baselineSummary(row);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          child: Text('${row['offset_hours'] ?? '?'}h'),
                        ),
                        title: Text(_followupAnimal(row), style: const TextStyle(fontWeight: FontWeight.w900)),
                        subtitle: Text([
                          if (due != null) '${_t(context, 'Due', 'الموعد', 'Vervalt')}: ${_dateLabel(due)}',
                          if (summary.isNotEmpty) summary,
                        ].join('\n'), maxLines: 3, overflow: TextOverflow.ellipsis),
                        trailing: overdue
                            ? Icon(Icons.notification_important_rounded, color: Theme.of(context).colorScheme.error)
                            : const Icon(Icons.schedule_rounded),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: () => _startFollowup(row),
                            icon: const Icon(Icons.photo_camera_rounded),
                            label: Text(_t(context, 'Start follow-up', 'ابدأ المتابعة', 'Start follow-up')),
                          ),
                          TextButton(
                            onPressed: () => _skip(row),
                            child: Text(_t(context, 'Skip', 'تخطي', 'Overslaan')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          if (completed.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text(
              _t(context, 'Completed comparisons', 'المقارنات المكتملة', 'Voltooide vergelijkingen'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            ...completed.take(20).map((row) {
              final comparison = _nested(row['ai_comparison']);
              final trend = '${row['outcome'] ?? comparison['trend'] ?? 'uncertain'}';
              final summary = '${comparison['visual_change_summary'] ?? comparison['symptom_change_summary'] ?? ''}'.trim();
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(Icons.compare_rounded, color: _trendColor(context, trend)),
                  ),
                  title: Text(_followupAnimal(row), style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text(summary.isEmpty ? _trendLabel(context, trend) : summary, maxLines: 3, overflow: TextOverflow.ellipsis),
                  trailing: Chip(label: Text(_trendLabel(context, trend))),
                  onTap: comparison.isEmpty ? null : () => _showResult(comparison),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

'''
    text = text.replace(anchor, followup_code + anchor, 1)

for marker in [
    "import 'package:image_picker/image_picker.dart';",
    "import 'ai_followup_service.dart';",
    'length: 4,',
    '_FollowUpTab(farmId: farmId),',
    'class _FollowUpTab extends StatefulWidget',
    'AiFollowupService.instance.submitFollowup',
    '12 / 24 / 48 hour AI follow-up',
]:
    if marker not in text:
        raise SystemExit(f'V101 marker missing: {marker}')

path.write_text(text, encoding='utf-8')
print('V101 AI follow-up UI applied')

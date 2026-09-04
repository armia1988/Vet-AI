import 'package:flutter/material.dart';

import '../i18n/vet_locale.dart';
import '../services/vet_backend.dart';
import '../services/vet_operations.dart';
import '../theme/app_theme.dart';

String _rt(BuildContext context, String en, String ar, String nl) => VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

class SensorAlertRulesScreen extends StatefulWidget {
  const SensorAlertRulesScreen({super.key, required this.farmId});
  final String farmId;

  @override
  State<SensorAlertRulesScreen> createState() => _SensorAlertRulesScreenState();
}

class _SensorAlertRulesScreenState extends State<SensorAlertRulesScreen> {
  late Future<List<Map<String, dynamic>>> future;

  @override
  void initState() {
    super.initState();
    future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() {
    return VetBackend.instance.sensorAlertRules(widget.farmId).timeout(const Duration(seconds: 12));
  }

  Future<void> refresh() async {
    setState(() => future = _load());
    try {
      await future;
    } catch (_) {
      // FutureBuilder presents the recoverable error state.
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(_rt(context, 'Real sensor alert rules', 'قواعد إنذارات الحساسات الحقيقية', 'Echte sensorwaarschuwingsregels')),
          actions: [IconButton(onPressed: () => _editRule(), icon: const Icon(Icons.add_circle_outline_rounded))],
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_rounded, size: 54, color: VetColors.red),
                      const SizedBox(height: 12),
                      Text(_rt(context, 'Could not load sensor alert rules', 'تعذر تحميل قواعد إنذارات الحساسات', 'Sensorwaarschuwingsregels konden niet worden geladen'), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                      const SizedBox(height: 8),
                      Text(_rt(context, 'Vet AI stopped the request instead of leaving an endless loader. Try again.', 'Vet AI أوقف الطلب بدل ما يفضل التحميل شغال للأبد. جرّب تاني.', 'Vet AI heeft het verzoek gestopt in plaats van eindeloos te laden. Probeer opnieuw.'), textAlign: TextAlign.center, style: const TextStyle(color: VetColors.muted, height: 1.4)),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(onPressed: refresh, icon: const Icon(Icons.refresh_rounded), label: Text(_rt(context, 'Retry', 'إعادة المحاولة', 'Opnieuw proberen'))),
                    ],
                  ),
                ),
              );
            }
            final rows = snapshot.data ?? const <Map<String, dynamic>>[];
            return RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                children: [
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(color: VetColors.softBlue, borderRadius: BorderRadius.circular(17), border: Border.all(color: VetColors.blue.withValues(alpha: .25))),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.rule_folder_outlined, color: VetColors.blue, size: 30),
                      const SizedBox(width: 11),
                      Expanded(child: Text(_rt(context, 'Rules are evaluated only when a real connected sensor writes a new reading. Vet AI does not insert universal medical thresholds automatically; configure limits for the species, age, environment and device placement with your veterinarian/device protocol.', 'القواعد بتتراجع فقط لما حساس حقيقي متوصل يبعت قراءة جديدة. Vet AI ما بيحطش حدود طبية عامة من نفسه؛ اضبط الحدود حسب نوع الحيوان والعمر والبيئة ومكان الجهاز مع الطبيب أو بروتوكول الجهاز.', 'Regels worden alleen beoordeeld wanneer een echt gekoppelde sensor een nieuwe meting schrijft. Vet AI plaatst geen universele medische drempels automatisch; stel grenzen in voor soort, leeftijd, omgeving en plaatsing samen met dierenarts/apparaatprotocol.'), style: const TextStyle(height: 1.5, fontWeight: FontWeight.w700))),
                    ]),
                  ),
                  const SizedBox(height: 15),
                  if (rows.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(children: [
                          const Icon(Icons.notifications_off_outlined, size: 52, color: VetColors.muted),
                          const SizedBox(height: 10),
                          Text(_rt(context, 'No sensor thresholds configured yet', 'لسه مفيش حدود إنذار متضبطة', 'Nog geen sensordrempels ingesteld'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                          const SizedBox(height: 7),
                          Text(_rt(context, 'Add a rule when you know the correct operational or veterinary limit for this farm.', 'ضيف قاعدة لما تكون عارف الحد التشغيلي أو البيطري الصحيح للمزرعة دي.', 'Voeg een regel toe wanneer de juiste operationele/veterinaire grens voor deze boerderij bekend is.'), textAlign: TextAlign.center, style: const TextStyle(color: VetColors.muted, height: 1.4)),
                          const SizedBox(height: 14),
                          FilledButton.icon(onPressed: () => _editRule(), icon: const Icon(Icons.add_rounded), label: Text(_rt(context, 'Add first rule', 'إضافة أول قاعدة', 'Eerste regel toevoegen'))),
                        ]),
                      ),
                    ),
                  for (final row in rows) _RuleCard(row: row, onEdit: () => _editRule(row), onDelete: () => _delete(row)),
                ],
              ),
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(onPressed: () => _editRule(), icon: const Icon(Icons.add_rounded), label: Text(_rt(context, 'Add rule', 'إضافة قاعدة', 'Regel toevoegen'))),
      );

  Future<void> _delete(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(_rt(context, 'Delete this alert rule?', 'حذف قاعدة الإنذار دي؟', 'Deze waarschuwingsregel verwijderen?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(_rt(context, 'Cancel', 'إلغاء', 'Annuleren'))),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(_rt(context, 'Delete', 'حذف', 'Verwijderen'))),
        ],
      ),
    );
    if (ok != true) return;
    await VetBackend.instance.deleteSensorAlertRule(row['id'].toString());
    await refresh();
  }

  Future<void> _editRule([Map<String, dynamic>? row]) async {
    final result = await showModalBottomSheet<_RuleDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _RuleEditor(initial: row),
    );
    if (result == null) return;
    await VetBackend.instance.saveSensorAlertRule(
      id: row?['id']?.toString(),
      farmId: widget.farmId,
      metric: result.metric,
      minValue: result.min,
      maxValue: result.max,
      severity: result.severity,
      label: result.label,
      cooldownMinutes: result.cooldown,
      enabled: result.enabled,
    );
    await refresh();
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({required this.row, required this.onEdit, required this.onDelete});
  final Map<String, dynamic> row;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  Color get color => switch (row['severity']?.toString()) {
        'red' => VetColors.red,
        'orange' => VetColors.orange,
        _ => VetColors.history,
      };

  @override
  Widget build(BuildContext context) {
    final metric = row['metric']?.toString() ?? '';
    final min = row['min_value'];
    final max = row['max_value'];
    final limits = [if (min != null) '${_rt(context, 'Below', 'أقل من', 'Onder')} $min', if (max != null) '${_rt(context, 'Above', 'أعلى من', 'Boven')} $max'].join(' • ');
    return Card(
      margin: const EdgeInsets.only(bottom: 11),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 13, 9, 13),
        child: Row(children: [
          Container(width: 46, height: 46, decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(14)), child: Icon(_metricIcon(metric), color: color)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((row['label']?.toString().trim().isNotEmpty ?? false) ? row['label'].toString() : _metricLabel(context, metric), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 4),
            Text('$limits\n${row['severity']} • ${row['cooldown_minutes']} min', style: const TextStyle(color: VetColors.muted, height: 1.35)),
          ])),
          IconButton(onPressed: onEdit, icon: const Icon(Icons.edit_outlined)),
          IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline_rounded, color: VetColors.red)),
        ]),
      ),
    );
  }
}

class _RuleEditor extends StatefulWidget {
  const _RuleEditor({this.initial});
  final Map<String, dynamic>? initial;

  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  static const metrics = ['body_temperature_c', 'ambient_temperature_c', 'humidity_percent', 'activity_index', 'steps', 'distance_from_herd_m', 'lying_minutes', 'feeding_minutes', 'rumination_minutes'];
  late String metric;
  late String severity;
  late bool enabled;
  late final TextEditingController min;
  late final TextEditingController max;
  late final TextEditingController label;
  late final TextEditingController cooldown;

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    metric = r?['metric']?.toString() ?? metrics.first;
    severity = r?['severity']?.toString() ?? 'yellow';
    enabled = r?['enabled'] != false;
    min = TextEditingController(text: r?['min_value']?.toString() ?? '');
    max = TextEditingController(text: r?['max_value']?.toString() ?? '');
    label = TextEditingController(text: r?['label']?.toString() ?? '');
    cooldown = TextEditingController(text: r?['cooldown_minutes']?.toString() ?? '30');
  }

  @override
  void dispose() {
    min.dispose(); max.dispose(); label.dispose(); cooldown.dispose();
    super.dispose();
  }

  double? number(String value) => value.trim().isEmpty ? null : double.tryParse(value.trim().replaceAll(',', '.'));

  void save() {
    final lo = number(min.text);
    final hi = number(max.text);
    if (lo == null && hi == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_rt(context, 'Enter a minimum or maximum threshold.', 'اكتب حد أدنى أو أعلى على الأقل.', 'Vul minimaal een onder- of bovengrens in.'))));
      return;
    }
    if (lo != null && hi != null && lo >= hi) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_rt(context, 'Minimum must be lower than maximum.', 'الحد الأدنى لازم يكون أقل من الأعلى.', 'Minimum moet lager zijn dan maximum.'))));
      return;
    }
    final cool = int.tryParse(cooldown.text.trim()) ?? 30;
    Navigator.pop(context, _RuleDraft(metric, lo, hi, severity, label.text.trim(), cool.clamp(1, 1440), enabled));
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(18, 16, 18, MediaQuery.viewInsetsOf(context).bottom + 18),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_rt(context, widget.initial == null ? 'Add real sensor alert rule' : 'Edit sensor alert rule', widget.initial == null ? 'إضافة قاعدة إنذار حساس حقيقية' : 'تعديل قاعدة إنذار الحساس', widget.initial == null ? 'Echte sensorwaarschuwingsregel toevoegen' : 'Sensorwaarschuwingsregel wijzigen'), style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(initialValue: metric, decoration: InputDecoration(labelText: _rt(context, 'Metric', 'المؤشر', 'Meting')), items: metrics.map((m) => DropdownMenuItem(value: m, child: Text(_metricLabel(context, m)))).toList(), onChanged: (v) => setState(() => metric = v ?? metric)),
            const SizedBox(height: 11),
            TextField(controller: label, decoration: InputDecoration(labelText: _rt(context, 'Alert label', 'اسم الإنذار', 'Meldingsnaam'), prefixIcon: const Icon(Icons.label_outline_rounded))),
            const SizedBox(height: 11),
            Row(children: [
              Expanded(child: TextField(controller: min, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: InputDecoration(labelText: _rt(context, 'Minimum', 'الحد الأدنى', 'Minimum')))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: max, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: InputDecoration(labelText: _rt(context, 'Maximum', 'الحد الأعلى', 'Maximum')))),
            ]),
            const SizedBox(height: 11),
            SegmentedButton<String>(segments: [
              ButtonSegment(value: 'yellow', label: Text(_rt(context, 'Yellow', 'أصفر', 'Geel')), icon: const Icon(Icons.circle, color: VetColors.history)),
              ButtonSegment(value: 'orange', label: Text(_rt(context, 'Orange', 'برتقالي', 'Oranje')), icon: const Icon(Icons.circle, color: VetColors.orange)),
              ButtonSegment(value: 'red', label: Text(_rt(context, 'Red', 'أحمر', 'Rood')), icon: const Icon(Icons.circle, color: VetColors.red)),
            ], selected: {severity}, onSelectionChanged: (v) => setState(() => severity = v.first)),
            const SizedBox(height: 11),
            TextField(controller: cooldown, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _rt(context, 'Repeat cooldown (minutes)', 'منع تكرار نفس الإنذار بالدقائق', 'Herhaalblokkering (minuten)'), prefixIcon: const Icon(Icons.timer_outlined))),
            const SizedBox(height: 8),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(_rt(context, 'Rule enabled', 'القاعدة مفعلة', 'Regel actief')), value: enabled, onChanged: (v) => setState(() => enabled = v)),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: save, icon: const Icon(Icons.save_outlined), label: Text(_rt(context, 'Save real alert rule', 'حفظ قاعدة الإنذار الحقيقية', 'Echte waarschuwingsregel opslaan'))),
          ]),
        ),
      );
}

class _RuleDraft {
  const _RuleDraft(this.metric, this.min, this.max, this.severity, this.label, this.cooldown, this.enabled);
  final String metric;
  final double? min;
  final double? max;
  final String severity;
  final String label;
  final int cooldown;
  final bool enabled;
}

String _metricLabel(BuildContext context, String metric) => switch (metric) {
      'body_temperature_c' => _rt(context, 'Body temperature °C', 'حرارة جسم الحيوان °م', 'Lichaamstemperatuur °C'),
      'ambient_temperature_c' => _rt(context, 'Barn temperature °C', 'حرارة العنبر °م', 'Staltemperatuur °C'),
      'humidity_percent' => _rt(context, 'Humidity %', 'الرطوبة %', 'Luchtvochtigheid %'),
      'activity_index' => _rt(context, 'Activity index', 'مؤشر النشاط', 'Activiteitsindex'),
      'steps' => _rt(context, 'Steps', 'الخطوات', 'Stappen'),
      'distance_from_herd_m' => _rt(context, 'Distance from herd (m)', 'البعد عن القطيع (م)', 'Afstand tot kudde (m)'),
      'lying_minutes' => _rt(context, 'Lying / resting minutes', 'دقائق الرقاد / الراحة', 'Lig-/rustminuten'),
      'feeding_minutes' => _rt(context, 'Feeding minutes', 'دقائق الأكل', 'Voerminuten'),
      'rumination_minutes' => _rt(context, 'Rumination minutes', 'دقائق الاجترار', 'Herkauwminuten'),
      _ => metric,
    };

IconData _metricIcon(String metric) => switch (metric) {
      'body_temperature_c' || 'ambient_temperature_c' => Icons.thermostat_rounded,
      'humidity_percent' => Icons.water_drop_outlined,
      'activity_index' => Icons.directions_run_rounded,
      'steps' => Icons.directions_walk_rounded,
      'distance_from_herd_m' => Icons.social_distance_rounded,
      'lying_minutes' => Icons.bedtime_outlined,
      'feeding_minutes' => Icons.restaurant_rounded,
      'rumination_minutes' => Icons.autorenew_rounded,
      _ => Icons.sensors_rounded,
    };

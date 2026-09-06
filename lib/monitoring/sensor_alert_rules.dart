import 'package:flutter/material.dart';

import '../i18n/vet_locale.dart';
import '../services/vet_backend.dart';
import '../services/vet_operations.dart';
import '../theme/app_theme.dart';

String _rt(BuildContext context, String en, String ar, String nl) =>
    VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

class _MetricSpec {
  const _MetricSpec({
    required this.metric,
    required this.sensor,
    required this.unit,
    required this.mode,
    required this.valueKind,
    required this.icon,
    required this.color,
    required this.en,
    required this.ar,
    required this.nl,
  });
  final String metric;
  final String sensor;
  final String unit;
  final String mode;
  final String valueKind;
  final IconData icon;
  final Color color;
  final String en;
  final String ar;
  final String nl;
}

const _specs = <_MetricSpec>[
  _MetricSpec(metric: 'ambient_temperature_c', sensor: 'SHT40', unit: '°C', mode: 'outside_range', valueKind: 'direct', icon: Icons.device_thermostat_rounded, color: VetColors.orange, en: 'Barn temperature', ar: 'حرارة العنبر', nl: 'Staltemperatuur'),
  _MetricSpec(metric: 'humidity_percent', sensor: 'SHT40', unit: '%RH', mode: 'outside_range', valueKind: 'direct', icon: Icons.water_drop_outlined, color: VetColors.blue, en: 'Relative humidity', ar: 'الرطوبة النسبية', nl: 'Relatieve luchtvochtigheid'),
  _MetricSpec(metric: 'oxygen_percent', sensor: 'SC4-O2', unit: '%O₂', mode: 'outside_range', valueKind: 'direct', icon: Icons.air_rounded, color: VetColors.blue, en: 'Oxygen level', ar: 'نسبة الأكسجين', nl: 'Zuurstofniveau'),
  _MetricSpec(metric: 'current_amp', sensor: 'SCT-013', unit: 'A', mode: 'outside_range', valueKind: 'direct', icon: Icons.electric_bolt_rounded, color: VetColors.orange, en: 'Electrical current', ar: 'التيار الكهربائي', nl: 'Elektrische stroom'),
  _MetricSpec(metric: 'battery_percent', sensor: 'Battery monitor', unit: '%', mode: 'outside_range', valueKind: 'direct', icon: Icons.battery_3_bar_rounded, color: VetColors.green, en: 'Battery level', ar: 'نسبة البطارية', nl: 'Batterijniveau'),
  _MetricSpec(metric: 'activity_index', sensor: 'MPU6050', unit: 'index', mode: 'outside_range', valueKind: 'derived', icon: Icons.directions_run_rounded, color: VetColors.green, en: 'Activity index', ar: 'مؤشر النشاط', nl: 'Activiteitsindex'),
  _MetricSpec(metric: 'steps', sensor: 'MPU6050', unit: 'steps', mode: 'outside_range', valueKind: 'derived', icon: Icons.directions_walk_rounded, color: VetColors.history, en: 'Steps', ar: 'الخطوات', nl: 'Stappen'),
  _MetricSpec(metric: 'lying_minutes', sensor: 'MPU6050', unit: 'min', mode: 'outside_range', valueKind: 'derived', icon: Icons.bedtime_outlined, color: VetColors.blue, en: 'Lying / resting time', ar: 'دقائق الرقاد / الراحة', nl: 'Lig-/rusttijd'),
  _MetricSpec(metric: 'feeding_minutes', sensor: 'MPU6050', unit: 'min', mode: 'outside_range', valueKind: 'derived', icon: Icons.restaurant_rounded, color: VetColors.green, en: 'Feeding time', ar: 'دقائق الأكل', nl: 'Voertijd'),
  _MetricSpec(metric: 'rumination_minutes', sensor: 'MPU6050', unit: 'min', mode: 'outside_range', valueKind: 'derived', icon: Icons.autorenew_rounded, color: VetColors.purple, en: 'Rumination time', ar: 'دقائق الاجترار', nl: 'Herkauwtijd'),
];

_MetricSpec _spec(String metric) => _specs.firstWhere(
      (e) => e.metric == metric,
      orElse: () => _specs.first,
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

  Future<List<Map<String, dynamic>>> _load() => VetBackend.instance
      .sensorAlertRules(widget.farmId)
      .timeout(const Duration(seconds: 12));

  Future<void> refresh() async {
    setState(() => future = _load());
    try { await future; } catch (_) {}
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final draft = await showModalBottomSheet<_RuleDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (_) => _RuleEditor(initial: row),
    );
    if (draft == null) return;
    final s = _spec(draft.metric);
    await VetBackend.instance.saveSensorAlertRule(
      id: row?['id']?.toString(),
      farmId: widget.farmId,
      metric: draft.metric,
      minValue: draft.min,
      maxValue: draft.max,
      severity: draft.severity,
      label: draft.label,
      cooldownMinutes: draft.cooldown,
      enabled: draft.enabled,
      unit: s.unit,
      sensorModel: s.sensor,
      valueKind: s.valueKind,
      comparisonMode: s.mode,
    );
    await refresh();
  }

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

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(_rt(context, 'Sensor alerts', 'إنذارات الحساسات', 'Sensorwaarschuwingen')),
          actions: [IconButton(onPressed: () => _edit(), icon: const Icon(Icons.add_circle_outline_rounded))],
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError) {
              return _CenteredError(onRetry: refresh);
            }
            final rows = snapshot.data ?? const <Map<String, dynamic>>[];
            return RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                children: [
                  _InfoCard(),
                  const SizedBox(height: 14),
                  _HardwareStrip(),
                  const SizedBox(height: 16),
                  if (rows.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(children: [
                          const Icon(Icons.notifications_off_outlined, size: 50, color: VetColors.muted),
                          const SizedBox(height: 10),
                          Text(_rt(context, 'No real sensor rules yet', 'لسه مفيش قواعد حساس حقيقية', 'Nog geen echte sensorregels'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                          const SizedBox(height: 7),
                          Text(_rt(context, 'Choose the sensor metric first; Vet AI will show the correct unit and only the threshold fields that make sense for it.', 'اختار قراءة الحساس الأول؛ Vet AI هيظهر الوحدة الصح وحقول الحدود المناسبة للقراءة دي فقط.', 'Kies eerst de sensormeting; Vet AI toont daarna de juiste eenheid en alleen de relevante drempelvelden.'), textAlign: TextAlign.center, style: const TextStyle(color: VetColors.muted, height: 1.45)),
                          const SizedBox(height: 14),
                          FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add_rounded), label: Text(_rt(context, 'Add rule', 'إضافة قاعدة', 'Regel toevoegen'))),
                        ]),
                      ),
                    ),
                  for (final row in rows) _RuleCard(row: row, onEdit: () => _edit(row), onDelete: () => _delete(row)),
                ],
              ),
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add_rounded), label: Text(_rt(context, 'Add rule', 'إضافة قاعدة', 'Regel toevoegen'))),
      );
}

class _InfoCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: VetColors.softBlue, borderRadius: BorderRadius.circular(18), border: Border.all(color: VetColors.blue.withValues(alpha: .2))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.verified_user_outlined, color: VetColors.blue, size: 29),
          const SizedBox(width: 11),
          Expanded(child: Text(_rt(context, 'Rules run only on real readings received from the connected ESP32-C3. No demo values are inserted. Set veterinary/operational limits for the animal, age and barn protocol you actually use.', 'القواعد بتشتغل فقط على قراءات حقيقية جاية من ESP32-C3 المتوصل. مفيش أرقام تجريبية. اضبط الحدود البيطرية/التشغيلية حسب الحيوان والعمر وبروتوكول العنبر عندك.', 'Regels werken alleen op echte metingen van de gekoppelde ESP32-C3. Er worden geen demowaarden ingevoerd. Stel de grenzen in voor het dier, de leeftijd en het stalprotocol dat je echt gebruikt.'), style: const TextStyle(height: 1.5, fontWeight: FontWeight.w700))),
        ]),
      );
}

class _HardwareStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 7,
        runSpacing: 7,
        children: const ['MPU6050', 'SHT40', 'SC4-O2', 'SCT-013', 'Battery'].map((x) => Chip(label: Text(x))).toList(),
      );
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({required this.row, required this.onEdit, required this.onDelete});
  final Map<String, dynamic> row;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final s = _spec(row['metric']?.toString() ?? '');
    final min = row['min_value'];
    final max = row['max_value'];
    final unit = (row['unit']?.toString().trim().isNotEmpty ?? false) ? row['unit'].toString() : s.unit;
    final threshold = '${_rt(context, 'Must not fall below', 'لا يقل عن', 'Niet lager dan')} ${min ?? '—'} $unit • ${_rt(context, 'Must not exceed', 'لا يزيد عن', 'Niet hoger dan')} ${max ?? '—'} $unit';
    final color = switch (row['severity']?.toString()) {'red' => VetColors.red, 'orange' => VetColors.orange, _ => VetColors.history};
    return Card(
      margin: const EdgeInsets.only(bottom: 11),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 7, 13),
        child: Row(children: [
          Container(width: 50, height: 50, decoration: BoxDecoration(color: s.color.withValues(alpha: .1), borderRadius: BorderRadius.circular(15)), child: Icon(s.icon, color: s.color)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((row['label']?.toString().trim().isNotEmpty ?? false) ? row['label'].toString() : _rt(context, s.en, s.ar, s.nl), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 4),
            Text('$threshold\n${s.sensor} • ${s.valueKind == 'derived' ? _rt(context, 'derived', 'مشتق من الحركة', 'afgeleid') : _rt(context, 'direct sensor', 'قراءة مباشرة', 'directe sensor')}', style: const TextStyle(color: VetColors.muted, height: 1.35)),
          ])),
          Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
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
  late String metric;
  late String severity;
  late bool enabled;
  late final TextEditingController min;
  late final TextEditingController max;
  late final TextEditingController label;
  late final TextEditingController cooldown;

  _MetricSpec get s => _spec(metric);

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    metric = r?['metric']?.toString() ?? _specs.first.metric;
    severity = r?['severity']?.toString() ?? 'yellow';
    enabled = r?['enabled'] != false;
    min = TextEditingController(text: r?['min_value']?.toString() ?? '');
    max = TextEditingController(text: r?['max_value']?.toString() ?? '');
    label = TextEditingController(text: r?['label']?.toString() ?? '');
    cooldown = TextEditingController(text: r?['cooldown_minutes']?.toString() ?? '30');
  }

  @override
  void dispose() { min.dispose(); max.dispose(); label.dispose(); cooldown.dispose(); super.dispose(); }
  double? _n(String v) => v.trim().isEmpty ? null : double.tryParse(v.trim().replaceAll(',', '.'));

  void _save() {
    final lo = _n(min.text), hi = _n(max.text);
    if (lo == null || hi == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_rt(context, 'Enter both the minimum and maximum thresholds.', 'اكتب الحدين: لا يقل عن ولا يزيد عن.', 'Vul zowel de minimum- als maximumgrens in.'))));
      return;
    }
    if (lo >= hi) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_rt(context, 'Minimum must be lower than maximum.', 'قيمة لا يقل عن لازم تكون أقل من قيمة لا يزيد عن.', 'Minimum moet lager zijn dan maximum.'))));
      return;
    }
    final cool = int.tryParse(cooldown.text.trim()) ?? 30;
    Navigator.pop(context, _RuleDraft(metric, lo, hi, severity, label.text.trim(), cool.clamp(1, 1440), enabled));
  }

  Widget _thresholdField(TextEditingController c, String en, String ar, String nl) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        decoration: InputDecoration(labelText: _rt(context, en, ar, nl), suffixText: s.unit, prefixIcon: Icon(s.icon)),
      );

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(18, 16, 18, MediaQuery.viewInsetsOf(context).bottom + 18),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_rt(context, widget.initial == null ? 'Add sensor rule' : 'Edit sensor rule', widget.initial == null ? 'إضافة قاعدة حساس' : 'تعديل قاعدة الحساس', widget.initial == null ? 'Sensorregel toevoegen' : 'Sensorregel wijzigen'), style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
            const SizedBox(height: 15),
            DropdownButtonFormField<String>(
              initialValue: metric,
              decoration: InputDecoration(labelText: _rt(context, 'Sensor metric', 'قراءة الحساس', 'Sensormeting')),
              items: _specs.map((x) => DropdownMenuItem(value: x.metric, child: Text('${_rt(context, x.en, x.ar, x.nl)} • ${x.sensor}'))).toList(),
              onChanged: (v) { if (v == null) return; setState(() { metric = v; min.clear(); max.clear(); }); },
            ),
            const SizedBox(height: 10),
            Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: s.color.withValues(alpha: .08), borderRadius: BorderRadius.circular(14)), child: Text('${s.sensor} • ${s.unit} • ${s.valueKind == 'derived' ? _rt(context, 'Derived from calibrated movement analysis', 'قيمة مشتقة من تحليل حركة مُعاير', 'Afgeleid uit gekalibreerde bewegingsanalyse') : _rt(context, 'Direct sensor reading', 'قراءة مباشرة من الحساس', 'Directe sensormeting')}', style: const TextStyle(fontWeight: FontWeight.w800))),
            const SizedBox(height: 10),
            TextField(controller: label, decoration: InputDecoration(labelText: _rt(context, 'Alert name (optional)', 'اسم الإنذار (اختياري)', 'Naam waarschuwing (optioneel)'), prefixIcon: const Icon(Icons.label_outline_rounded))),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _thresholdField(min, 'Must not fall below', 'لا يقل عن', 'Niet lager dan')),
              const SizedBox(width: 10),
              Expanded(child: _thresholdField(max, 'Must not exceed', 'لا يزيد عن', 'Niet hoger dan')),
            ]),
            const SizedBox(height: 12),
            SegmentedButton<String>(segments: [
              ButtonSegment(value: 'yellow', label: Text(_rt(context, 'Yellow', 'أصفر', 'Geel')), icon: const Icon(Icons.circle, color: VetColors.history)),
              ButtonSegment(value: 'orange', label: Text(_rt(context, 'Orange', 'برتقالي', 'Oranje')), icon: const Icon(Icons.circle, color: VetColors.orange)),
              ButtonSegment(value: 'red', label: Text(_rt(context, 'Red', 'أحمر', 'Rood')), icon: const Icon(Icons.circle, color: VetColors.red)),
            ], selected: {severity}, onSelectionChanged: (v) => setState(() => severity = v.first)),
            const SizedBox(height: 11),
            TextField(controller: cooldown, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _rt(context, 'Repeat cooldown', 'منع تكرار نفس الإنذار', 'Herhaalblokkering'), suffixText: _rt(context, 'min', 'دقيقة', 'min'), prefixIcon: const Icon(Icons.timer_outlined))),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(_rt(context, 'Rule enabled', 'القاعدة مفعلة', 'Regel actief')), value: enabled, onChanged: (v) => setState(() => enabled = v)),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: Text(_rt(context, 'Save real sensor rule', 'حفظ قاعدة الحساس الحقيقية', 'Echte sensorregel opslaan')))),
          ]),
        ),
      );
}

class _RuleDraft {
  const _RuleDraft(this.metric, this.min, this.max, this.severity, this.label, this.cooldown, this.enabled);
  final String metric; final double? min; final double? max; final String severity; final String label; final int cooldown; final bool enabled;
}

class _CenteredError extends StatelessWidget {
  const _CenteredError({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_rounded, size: 54, color: VetColors.red),
        const SizedBox(height: 10),
        Text(_rt(context, 'Could not load sensor rules', 'تعذر تحميل قواعد الحساسات', 'Sensorregels konden niet worden geladen'), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: Text(_rt(context, 'Retry', 'إعادة المحاولة', 'Opnieuw proberen'))),
      ])));
}

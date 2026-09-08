import 'package:flutter/material.dart';

import '../i18n/vet_locale.dart';
import '../theme/app_theme.dart';
import 'admin_service.dart';

String _st(BuildContext context, String en, String ar, String nl) =>
    VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

class VetAdminSensorCenter extends StatefulWidget {
  const VetAdminSensorCenter({super.key});

  @override
  State<VetAdminSensorCenter> createState() => _VetAdminSensorCenterState();
}

class _VetAdminSensorCenterState extends State<VetAdminSensorCenter> {
  final admin = VetAdminService.instance;
  late Future<_SensorCenterData> future = _load();

  Future<_SensorCenterData> _load() async {
    final values = await Future.wait([
      admin.sensors(),
      admin.farms(),
      admin.sensorRules(),
      admin.client
          .from('sensor_readings')
          .select()
          .order('recorded_at', ascending: false)
          .limit(500),
      admin.client
          .from('sensor_hardware_catalog')
          .select()
          .order('category')
          .limit(500),
    ]);
    return _SensorCenterData(
      sensors: values[0] as List<Map<String, dynamic>>,
      farms: values[1] as List<Map<String, dynamic>>,
      rules: values[2] as List<Map<String, dynamic>>,
      readings: (values[3] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      hardware: (values[4] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
  }

  void reload() => setState(() => future = _load());

  bool _online(Map<String, dynamic> row) {
    if (row['active'] != true) return false;
    final seen = DateTime.tryParse('${row['last_seen_at'] ?? ''}');
    if (seen == null) return false;
    return DateTime.now().toUtc().difference(seen.toUtc()) <
        const Duration(minutes: 10);
  }

  Future<void> _editDevice(
    Map<String, dynamic> row,
    List<Map<String, dynamic>> farms,
  ) async {
    final name = TextEditingController(text: '${row['display_name'] ?? ''}');
    final section = TextEditingController(text: '${row['section_name'] ?? ''}');
    final firmware = TextEditingController(text: '${row['firmware_version'] ?? ''}');
    final notes = TextEditingController(text: '${row['admin_notes'] ?? ''}');
    var farmId = row['farm_id']?.toString();
    var active = row['active'] == true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(_st(context, 'Edit sensor device', 'تعديل جهاز الحساس', 'Sensorapparaat bewerken')),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: farmId,
                    decoration: InputDecoration(labelText: _st(context, 'Company / farm', 'الشركة / المزرعة', 'Bedrijf / boerderij')),
                    items: [
                      for (final farm in farms)
                        DropdownMenuItem(
                          value: farm['id'].toString(),
                          child: Text('${farm['company_name'] ?? ''} / ${farm['farm_name'] ?? ''}'),
                        ),
                    ],
                    onChanged: (value) => setLocal(() => farmId = value),
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: name, decoration: InputDecoration(labelText: _st(context, 'Device name', 'اسم الجهاز', 'Apparaatnaam'))),
                  const SizedBox(height: 10),
                  TextField(controller: section, decoration: InputDecoration(labelText: _st(context, 'Section / barn', 'القسم / الحظيرة', 'Afdeling / stal'))),
                  const SizedBox(height: 10),
                  TextField(controller: firmware, decoration: const InputDecoration(labelText: 'Firmware')),
                  const SizedBox(height: 10),
                  TextField(controller: notes, minLines: 2, maxLines: 5, decoration: InputDecoration(labelText: _st(context, 'Admin notes', 'ملاحظات الإدارة', 'Adminnotities'))),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    value: active,
                    onChanged: (value) => setLocal(() => active = value),
                    title: Text(_st(context, 'Allow sensor to send readings', 'السماح للحساس بإرسال القراءات', 'Sensor mag metingen verzenden')),
                    subtitle: Text(active
                        ? _st(context, 'Device is enabled', 'الجهاز مفعّل', 'Apparaat is ingeschakeld')
                        : _st(context, 'Device is blocked at the server', 'الجهاز مفصول من السيرفر', 'Apparaat is op de server geblokkeerd')),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_st(context, 'Cancel', 'إلغاء', 'Annuleren'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_st(context, 'Save changes', 'حفظ التعديلات', 'Wijzigingen opslaan'))),
          ],
        ),
      ),
    );

    if (ok != true || farmId == null) return;
    await admin.updateSensor(row['id'].toString(), {
      'farm_id': farmId,
      'display_name': name.text.trim(),
      'section_name': section.text.trim(),
      'firmware_version': firmware.text.trim(),
      'admin_notes': notes.text.trim(),
      'active': active,
      'admin_disabled_reason': active ? null : 'Disabled from Vet AI Admin',
    });
    reload();
  }

  Future<void> _editRule(Map<String, dynamic> row) async {
    final minValue = TextEditingController(text: '${row['min_value'] ?? ''}');
    final maxValue = TextEditingController(text: '${row['max_value'] ?? ''}');
    final label = TextEditingController(text: '${row['label'] ?? ''}');
    final cooldown = TextEditingController(text: '${row['cooldown_minutes'] ?? 0}');
    var enabled = row['enabled'] == true;
    var severity = '${row['severity'] ?? 'orange'}';

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('${row['metric'] ?? ''} • ${_st(context, 'Alert rule', 'قاعدة الإنذار', 'Meldingsregel')}'),
          content: SizedBox(
            width: 540,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: label, decoration: InputDecoration(labelText: _st(context, 'Rule name', 'اسم القاعدة', 'Regelnaam'))),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: minValue, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: InputDecoration(labelText: _st(context, 'Minimum', 'الحد الأدنى', 'Minimum')))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: maxValue, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: InputDecoration(labelText: _st(context, 'Maximum', 'الحد الأقصى', 'Maximum')))),
                ]),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: severity,
                  decoration: InputDecoration(labelText: _st(context, 'Severity', 'درجة الخطورة', 'Ernst')),
                  items: const [
                    DropdownMenuItem(value: 'orange', child: Text('Orange')),
                    DropdownMenuItem(value: 'red', child: Text('Red')),
                  ],
                  onChanged: (value) => setLocal(() => severity = value ?? 'orange'),
                ),
                const SizedBox(height: 10),
                TextField(controller: cooldown, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _st(context, 'Cooldown minutes', 'مدة منع تكرار الإنذار بالدقائق', 'Cooldown minuten'))),
                SwitchListTile(value: enabled, onChanged: (value) => setLocal(() => enabled = value), title: Text(_st(context, 'Rule enabled', 'القاعدة مفعّلة', 'Regel ingeschakeld'))),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_st(context, 'Cancel', 'إلغاء', 'Annuleren'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_st(context, 'Save', 'حفظ', 'Opslaan'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await admin.updateSensorRule(row['id'].toString(), {
      'label': label.text.trim(),
      'min_value': minValue.text.trim().isEmpty ? null : double.tryParse(minValue.text.trim()),
      'max_value': maxValue.text.trim().isEmpty ? null : double.tryParse(maxValue.text.trim()),
      'severity': severity,
      'cooldown_minutes': int.tryParse(cooldown.text.trim()) ?? 0,
      'enabled': enabled,
    });
    reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_SensorCenterData>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(30), child: Text('${snapshot.error}', style: const TextStyle(color: VetColors.red))));
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!;
          final farmNames = {
            for (final farm in data.farms)
              farm['id'].toString(): '${farm['company_name'] ?? ''} / ${farm['farm_name'] ?? ''}',
          };
          return DefaultTabController(
            length: 4,
            child: Column(
              children: [
                Material(
                  color: VetColors.surface2,
                  child: TabBar(
                    isScrollable: true,
                    tabs: [
                      Tab(icon: const Icon(Icons.domain_rounded), text: _st(context, 'Companies', 'الشركات', 'Bedrijven')),
                      Tab(icon: const Icon(Icons.sensors_rounded), text: _st(context, 'Devices', 'الأجهزة', 'Apparaten')),
                      Tab(icon: const Icon(Icons.rule_rounded), text: _st(context, 'Alert rules', 'قواعد الإنذار', 'Meldingsregels')),
                      Tab(icon: const Icon(Icons.monitor_heart_rounded), text: _st(context, 'Live readings', 'القراءات', 'Metingen')),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(children: [
                    _companySummary(context, data, farmNames),
                    _devices(context, data, farmNames),
                    _rules(context, data, farmNames),
                    _readings(context, data, farmNames),
                  ]),
                ),
              ],
            ),
          );
        },
      );

  Widget _companySummary(BuildContext context, _SensorCenterData data, Map<String, String> farmNames) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final sensor in data.sensors) {
      grouped.putIfAbsent(sensor['farm_id'].toString(), () => []).add(sensor);
    }
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(_st(context, 'Sensor fleet by company', 'أسطول الحساسات حسب كل شركة', 'Sensorvloot per bedrijf'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 14),
        for (final entry in grouped.entries)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.domain_rounded, color: VetColors.green),
                  const SizedBox(width: 9),
                  Expanded(child: Text(farmNames[entry.key] ?? entry.key, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
                ]),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  Chip(label: Text('${entry.value.length} ${_st(context, 'devices', 'جهاز', 'apparaten')}')),
                  Chip(avatar: const Icon(Icons.circle, size: 10, color: VetColors.green), label: Text('${entry.value.where(_online).length} ${_st(context, 'online', 'متصل', 'online')}')),
                  Chip(avatar: const Icon(Icons.circle, size: 10, color: VetColors.red), label: Text('${entry.value.where((e) => e['active'] == true && !_online(e)).length} ${_st(context, 'offline', 'غير متصل', 'offline')}')),
                  Chip(label: Text('${entry.value.where((e) => e['active'] != true).length} ${_st(context, 'disabled', 'مفصول', 'uitgeschakeld')}')),
                ]),
                const SizedBox(height: 10),
                Text('${_st(context, 'Sections', 'الأقسام', 'Afdelingen')}: ${entry.value.map((e) => '${e['section_name'] ?? ''}').where((e) => e.trim().isNotEmpty).toSet().join(' • ').isEmpty ? '-' : entry.value.map((e) => '${e['section_name'] ?? ''}').where((e) => e.trim().isNotEmpty).toSet().join(' • ')}', style: const TextStyle(color: VetColors.muted)),
              ]),
            ),
          ),
        if (grouped.isEmpty)
          Center(child: Padding(padding: const EdgeInsets.all(40), child: Text(_st(context, 'No sensor devices are registered yet.', 'لا توجد أجهزة حساسات مسجلة حتى الآن.', 'Er zijn nog geen sensoren geregistreerd.')))),
      ],
    );
  }

  Widget _devices(BuildContext context, _SensorCenterData data, Map<String, String> farmNames) => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          for (final row in data.sensors)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _online(row) ? VetColors.softGreen : VetColors.surface3,
                  child: Icon(_online(row) ? Icons.sensors_rounded : Icons.sensors_off_rounded, color: _online(row) ? VetColors.green : VetColors.red),
                ),
                title: Text('${row['display_name'] ?? row['device_uid'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w900)),
                subtitle: Text('${farmNames[row['farm_id'].toString()] ?? row['farm_id']}\n${row['section_name'] ?? _st(context, 'No section', 'بدون قسم', 'Geen afdeling')} • ${row['device_type'] ?? ''}\n${_st(context, 'Last seen', 'آخر اتصال', 'Laatst gezien')}: ${row['last_seen_at'] ?? '-'}'),
                isThreeLine: true,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Chip(label: Text(row['active'] != true ? _st(context, 'Blocked', 'مفصول', 'Geblokkeerd') : _online(row) ? _st(context, 'Online', 'متصل', 'Online') : _st(context, 'Offline', 'غير متصل', 'Offline'))),
                  IconButton(onPressed: () => _editDevice(row, data.farms), icon: const Icon(Icons.tune_rounded)),
                ]),
                onTap: () => _editDevice(row, data.farms),
              ),
            ),
        ],
      );

  Widget _rules(BuildContext context, _SensorCenterData data, Map<String, String> farmNames) => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          for (final row in data.rules)
            Card(
              child: ListTile(
                leading: CircleAvatar(backgroundColor: '${row['severity']}' == 'red' ? VetColors.red.withValues(alpha: .12) : VetColors.history.withValues(alpha: .12), child: Icon(Icons.rule_rounded, color: '${row['severity']}' == 'red' ? VetColors.red : VetColors.history)),
                title: Text('${row['label'] ?? row['metric'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w900)),
                subtitle: Text('${farmNames[row['farm_id'].toString()] ?? row['farm_id']}\n${row['metric']} • min ${row['min_value'] ?? '-'} • max ${row['max_value'] ?? '-'} ${row['unit'] ?? ''}\n${row['severity']} • ${row['enabled'] == true ? _st(context, 'enabled', 'مفعّل', 'ingeschakeld') : _st(context, 'disabled', 'متوقف', 'uitgeschakeld')}'),
                isThreeLine: true,
                trailing: IconButton(onPressed: () => _editRule(row), icon: const Icon(Icons.edit_rounded)),
                onTap: () => _editRule(row),
              ),
            ),
          if (data.rules.isEmpty)
            Center(child: Padding(padding: const EdgeInsets.all(40), child: Text(_st(context, 'No alert rules configured.', 'لا توجد قواعد إنذار مضبوطة.', 'Geen meldingsregels ingesteld.')))),
        ],
      );

  Widget _readings(BuildContext context, _SensorCenterData data, Map<String, String> farmNames) {
    final deviceNames = {for (final d in data.sensors) d['id'].toString(): '${d['display_name'] ?? d['device_uid'] ?? d['id']}'};
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text('${_st(context, 'Latest readings', 'أحدث القراءات', 'Laatste metingen')} • ${data.readings.length}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        for (final row in data.readings)
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.monitor_heart_rounded, color: VetColors.green),
              title: Text('${deviceNames[row['device_id'].toString()] ?? row['device_id']}', style: const TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text('${farmNames[row['farm_id'].toString()] ?? row['farm_id']} • ${row['recorded_at'] ?? ''}'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _ReadingChip('Temp', row['ambient_temperature_c'], '°C'),
                  _ReadingChip('Humidity', row['humidity_percent'], '%'),
                  _ReadingChip('O₂', row['oxygen_percent'], '%'),
                  _ReadingChip('Battery', row['battery_percent'], '%'),
                  _ReadingChip('Activity', row['activity_index'], ''),
                  _ReadingChip('Steps', row['steps'], ''),
                  _ReadingChip('Rumination', row['rumination_minutes'], 'm'),
                  _ReadingChip('Feeding', row['feeding_minutes'], 'm'),
                  _ReadingChip('Current', row['current_amp'], 'A'),
                ]),
              ],
            ),
          ),
      ],
    );
  }
}

class _ReadingChip extends StatelessWidget {
  const _ReadingChip(this.label, this.value, this.unit);
  final String label;
  final dynamic value;
  final String unit;

  @override
  Widget build(BuildContext context) => Chip(label: Text('$label: ${value ?? '-'}$unit'));
}

class _SensorCenterData {
  const _SensorCenterData({required this.sensors, required this.farms, required this.rules, required this.readings, required this.hardware});
  final List<Map<String, dynamic>> sensors;
  final List<Map<String, dynamic>> farms;
  final List<Map<String, dynamic>> rules;
  final List<Map<String, dynamic>> readings;
  final List<Map<String, dynamic>> hardware;
}

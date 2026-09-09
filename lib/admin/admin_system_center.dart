import 'package:flutter/material.dart';

import '../i18n/vet_locale.dart';
import '../services/vet_backend.dart';
import '../theme/app_theme.dart';
import 'admin_service.dart';

String _yt(BuildContext context, String en, String ar, String nl) =>
    VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

class VetAdminSystemCenter extends StatefulWidget {
  const VetAdminSystemCenter({super.key});

  @override
  State<VetAdminSystemCenter> createState() => _VetAdminSystemCenterState();
}

class _VetAdminSystemCenterState extends State<VetAdminSystemCenter> {
  final admin = VetAdminService.instance;
  late Future<List<Map<String, dynamic>>> future = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await admin.client
        .from('admin_system_settings')
        .select()
        .order('key');
    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  void reload() => setState(() => future = _load());

  Future<void> _set(String key, dynamic value) async {
    await admin.client.from('admin_system_settings').update({'value': value}).eq('key', key);
    reload();
  }

  Future<void> _editValue(Map<String, dynamic> row, {required bool number}) async {
    final current = row['value'];
    final controller = TextEditingController(text: '$current'.replaceAll('"', ''));
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${_yt(context, 'Edit setting', 'تعديل الإعداد', 'Instelling bewerken')} • ${row['key']}'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
            keyboardType: number ? const TextInputType.numberWithOptions(decimal: false) : TextInputType.text,
            decoration: InputDecoration(labelText: _yt(context, 'Value', 'القيمة', 'Waarde')),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_yt(context, 'Cancel', 'إلغاء', 'Annuleren'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_yt(context, 'Save', 'حفظ', 'Opslaan'))),
        ],
      ),
    );
    if (ok != true) return;
    final value = number ? int.tryParse(controller.text.trim()) ?? current : controller.text.trim();
    await _set(row['key'].toString(), value);
  }

  String _title(BuildContext context, String key) => switch (key) {
        'maintenance_mode' => _yt(context, 'Maintenance mode', 'وضع الصيانة', 'Onderhoudsmodus'),
        'customer_signup_enabled' => _yt(context, 'Customer signup', 'تسجيل عملاء جدد', 'Klantregistratie'),
        'sensor_ingest_enabled' => _yt(context, 'Sensor data ingestion', 'استقبال بيانات الحساسات', 'Sensor-data-inname'),
        'sensor_alert_push_enabled' => _yt(context, 'Sensor alert push', 'إشعارات إنذارات الحساسات', 'Sensoralarm-push'),
        'admin_broadcast_push_enabled' => _yt(context, 'Admin broadcast push', 'إشعارات الإدارة العامة', 'Admin-broadcast push'),
        'support_push_enabled' => _yt(context, 'Support push to admins', 'إشعارات الدعم للإدارة', 'Support-push naar admins'),
        'default_currency' => _yt(context, 'Default currency', 'العملة الافتراضية', 'Standaardvaluta'),
        'default_trial_days' => _yt(context, 'Default trial days', 'أيام التجربة الافتراضية', 'Standaard proefdagen'),
        'sensor_offline_minutes' => _yt(context, 'Sensor offline timeout', 'مدة اعتبار الحساس غير متصل', 'Sensor offline-time-out'),
        'support_sla_hours' => _yt(context, 'Support SLA hours', 'ساعات الاستجابة للدعم', 'Support-SLA uren'),
        _ => key,
      };

  IconData _icon(String key) => switch (key) {
        'maintenance_mode' => Icons.build_circle_rounded,
        'customer_signup_enabled' => Icons.person_add_alt_1_rounded,
        'sensor_ingest_enabled' => Icons.sensors_rounded,
        'sensor_alert_push_enabled' => Icons.crisis_alert_rounded,
        'admin_broadcast_push_enabled' => Icons.campaign_rounded,
        'support_push_enabled' => Icons.support_agent_rounded,
        'default_currency' => Icons.currency_exchange_rounded,
        'default_trial_days' => Icons.timer_rounded,
        'sensor_offline_minutes' => Icons.sensors_off_rounded,
        'support_sla_hours' => Icons.schedule_rounded,
        _ => Icons.settings_rounded,
      };

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('${snapshot.error}', style: const TextStyle(color: VetColors.red)));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final rows = snapshot.data!;
          final booleans = rows.where((e) => e['value'] is bool).toList();
          final values = rows.where((e) => e['value'] is! bool).toList();
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(_yt(context, 'Global Vet AI system controls', 'التحكم العام في نظام Vet AI', 'Globale Vet AI-systeembediening'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 5),
              Text(_yt(context, 'These switches are stored on the server and are used by the production services, not just by this screen.', 'هذه المفاتيح محفوظة على السيرفر وتتحكم في خدمات الإنتاج نفسها، وليست مجرد شكل في الشاشة.', 'Deze schakelaars staan op de server en worden door productiediensten gebruikt, niet alleen door dit scherm.'), style: const TextStyle(color: VetColors.muted)),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    const CircleAvatar(child: Icon(Icons.verified_user_rounded, color: VetColors.green)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_yt(context, 'Server-enforced administrator controls', 'صلاحيات الإدارة محمية من السيرفر', 'Server-afgedwongen beheer'), style: const TextStyle(fontWeight: FontWeight.w900)),
                      Text(_yt(context, 'Every change is protected by admin RLS and written to the audit trail.', 'كل تغيير محمي بصلاحيات الإدارة ويتم تسجيله في سجل العمليات.', 'Elke wijziging is beschermd door admin-RLS en wordt gelogd in de audittrail.'), style: const TextStyle(color: VetColors.muted)),
                    ])),
                    IconButton.filledTonal(onPressed: reload, icon: const Icon(Icons.refresh_rounded)),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              Text(_yt(context, 'Production switches', 'مفاتيح التشغيل', 'Productieschakelaars'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              for (final row in booleans)
                Card(
                  child: SwitchListTile(
                    value: row['value'] == true,
                    onChanged: (value) => _set(row['key'].toString(), value),
                    secondary: Icon(_icon(row['key'].toString()), color: row['value'] == true ? VetColors.green : VetColors.red),
                    title: Text(_title(context, row['key'].toString()), style: const TextStyle(fontWeight: FontWeight.w900)),
                    subtitle: Text('${row['description'] ?? ''}\n${_yt(context, 'Last update', 'آخر تحديث', 'Laatste update')}: ${row['updated_at'] ?? '-'}'),
                    isThreeLine: true,
                  ),
                ),
              const SizedBox(height: 14),
              Text(_yt(context, 'Defaults & limits', 'القيم الافتراضية والحدود', 'Standaarden & limieten'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              for (final row in values)
                Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Icon(_icon(row['key'].toString()))),
                    title: Text(_title(context, row['key'].toString()), style: const TextStyle(fontWeight: FontWeight.w900)),
                    subtitle: Text('${row['description'] ?? ''}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Chip(label: Text('${row['value']}')),
                      const SizedBox(width: 6),
                      const Icon(Icons.edit_rounded),
                    ]),
                    onTap: () => _editValue(row, number: row['value'] is num),
                  ),
                ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.language_rounded),
                  title: Text(_yt(context, 'Dashboard language', 'لغة لوحة التحكم', 'Dashboardtaal')),
                  subtitle: Text(_yt(context, 'Uses the complete Vet AI language system.', 'تستخدم نظام لغات Vet AI الكامل.', 'Gebruikt het volledige Vet AI-taalsysteem.')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showVetLanguagePicker(context),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.logout_rounded, color: VetColors.red),
                  title: Text(_yt(context, 'Sign out', 'تسجيل الخروج', 'Uitloggen')),
                  onTap: () => VetBackend.instance.signOut(),
                ),
              ),
              const SizedBox(height: 40),
            ],
          );
        },
      );
}

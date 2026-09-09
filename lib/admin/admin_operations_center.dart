import 'package:flutter/material.dart';

import '../i18n/vet_locale.dart';
import '../theme/app_theme.dart';
import 'admin_service.dart';

String _ot(BuildContext context, String en, String ar, String nl) =>
    VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

class VetAdminOperationsCenter extends StatefulWidget {
  const VetAdminOperationsCenter({super.key});

  @override
  State<VetAdminOperationsCenter> createState() => _VetAdminOperationsCenterState();
}

class _VetAdminOperationsCenterState extends State<VetAdminOperationsCenter> {
  final admin = VetAdminService.instance;
  late Future<Map<String, dynamic>> future = _load();

  Future<Map<String, dynamic>> _load() async {
    final value = await admin.client.rpc('admin_operations_health');
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  void reload() => setState(() => future = _load());

  int _n(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  bool _setting(Map<String, dynamic> data, String key, {bool fallback = true}) {
    final settings = data['system_settings'];
    if (settings is Map && settings.containsKey(key)) return settings[key] == true;
    return fallback;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline_rounded, size: 54, color: VetColors.red),
                  const SizedBox(height: 10),
                  Text(
                    _ot(context, 'Operations data could not be loaded.', 'تعذر تحميل بيانات التشغيل.', 'Operationele gegevens konden niet worden geladen.'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(onPressed: reload, icon: const Icon(Icons.refresh_rounded), label: Text(_ot(context, 'Retry', 'إعادة المحاولة', 'Opnieuw'))),
                ]),
              ),
            );
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final d = snapshot.data!;

          final red = _n(d, 'alerts_red_open');
          final orange = _n(d, 'alerts_orange_open');
          final offline = _n(d, 'sensors_offline');
          final urgentSupport = _n(d, 'support_urgent');
          final pastDue = _n(d, 'subscriptions_past_due');
          final failedPayments = _n(d, 'payments_failed');
          final pushFailures = _n(d, 'customer_push_failures_24h');
          final suspended = _n(d, 'customers_suspended');
          final closed = _n(d, 'customers_closed');

          final maintenance = _setting(d, 'maintenance_mode', fallback: false);
          final signup = _setting(d, 'customer_signup_enabled');
          final ingest = _setting(d, 'sensor_ingest_enabled');
          final sensorPush = _setting(d, 'sensor_alert_push_enabled');
          final broadcastPush = _setting(d, 'admin_broadcast_push_enabled');
          final supportPush = _setting(d, 'support_push_enabled');

          final attention = <_AttentionItem>[
            if (red > 0) _AttentionItem(Icons.crisis_alert_rounded, '$red', _ot(context, 'Open red alerts', 'إنذارات حمراء مفتوحة', 'Open rode alarmen'), VetColors.red),
            if (offline > 0) _AttentionItem(Icons.sensors_off_rounded, '$offline', _ot(context, 'Sensors offline', 'حساسات غير متصلة', 'Sensoren offline'), VetColors.red),
            if (urgentSupport > 0) _AttentionItem(Icons.support_agent_rounded, '$urgentSupport', _ot(context, 'Urgent support threads', 'رسائل دعم عاجلة', 'Urgente supportgesprekken'), VetColors.history),
            if (pastDue > 0) _AttentionItem(Icons.money_off_csred_rounded, '$pastDue', _ot(context, 'Past-due subscriptions', 'اشتراكات متأخرة', 'Achterstallige abonnementen'), VetColors.red),
            if (failedPayments > 0) _AttentionItem(Icons.payment_rounded, '$failedPayments', _ot(context, 'Failed payments', 'مدفوعات فاشلة', 'Mislukte betalingen'), VetColors.red),
            if (pushFailures > 0) _AttentionItem(Icons.notifications_off_rounded, '$pushFailures', _ot(context, 'Push failures in 24h', 'فشل Push خلال 24 ساعة', 'Push-fouten in 24u'), VetColors.history),
          ];

          final metrics = <_OpsMetric>[
            _OpsMetric(Icons.people_alt_rounded, _ot(context, 'Customers', 'العملاء', 'Klanten'), _n(d, 'customers_total'), VetColors.blue),
            _OpsMetric(Icons.domain_rounded, _ot(context, 'Farms', 'المزارع', 'Boerderijen'), _n(d, 'farms_total'), VetColors.green),
            _OpsMetric(Icons.pets_rounded, _ot(context, 'Active animals', 'الحيوانات النشطة', 'Actieve dieren'), _n(d, 'animals_active'), VetColors.history),
            _OpsMetric(Icons.sensors_rounded, _ot(context, 'Active sensors', 'الحساسات النشطة', 'Actieve sensoren'), _n(d, 'sensors_active'), VetColors.green),
            _OpsMetric(Icons.sensors_off_rounded, _ot(context, 'Offline sensors', 'الحساسات غير المتصلة', 'Offline sensoren'), offline, offline > 0 ? VetColors.red : VetColors.green),
            _OpsMetric(Icons.crisis_alert_rounded, _ot(context, 'Red alerts', 'الإنذارات الحمراء', 'Rode alarmen'), red, red > 0 ? VetColors.red : VetColors.green),
            _OpsMetric(Icons.warning_amber_rounded, _ot(context, 'Orange alerts', 'الإنذارات البرتقالية', 'Oranje alarmen'), orange, orange > 0 ? VetColors.history : VetColors.green),
            _OpsMetric(Icons.support_agent_rounded, _ot(context, 'Open support', 'الدعم المفتوح', 'Open support'), _n(d, 'support_open'), VetColors.blue),
            _OpsMetric(Icons.workspace_premium_rounded, _ot(context, 'Active subscriptions', 'الاشتراكات الفعالة', 'Actieve abonnementen'), _n(d, 'subscriptions_active'), VetColors.green),
            _OpsMetric(Icons.pending_actions_rounded, _ot(context, 'Pending payments', 'مدفوعات معلقة', 'Openstaande betalingen'), _n(d, 'payments_pending'), VetColors.history),
            _OpsMetric(Icons.notifications_active_rounded, _ot(context, 'Customer push devices', 'أجهزة Push للعملاء', 'Push-apparaten klanten'), _n(d, 'customer_push_devices_enabled'), VetColors.blue),
            _OpsMetric(Icons.history_rounded, _ot(context, 'Admin changes 24h', 'تغييرات الإدارة 24س', 'Adminwijzigingen 24u'), _n(d, 'audit_events_24h'), VetColors.history),
          ];

          return RefreshIndicator(
            onRefresh: () async => reload(),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _OperationsHero(
                  maintenance: maintenance,
                  generatedAt: '${d['generated_at'] ?? ''}',
                  onRefresh: reload,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _ServiceChip(label: _ot(context, 'Customer signup', 'تسجيل العملاء', 'Klantregistratie'), enabled: signup),
                    _ServiceChip(label: _ot(context, 'Sensor ingestion', 'استقبال الحساسات', 'Sensorinname'), enabled: ingest),
                    _ServiceChip(label: _ot(context, 'Sensor alert push', 'Push إنذارات الحساسات', 'Sensoralarm-push'), enabled: sensorPush),
                    _ServiceChip(label: _ot(context, 'Admin broadcast', 'إشعارات الإدارة', 'Admin-broadcast'), enabled: broadcastPush),
                    _ServiceChip(label: _ot(context, 'Support push', 'Push الدعم', 'Support-push'), enabled: supportPush),
                  ],
                ),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, c) {
                    final w = c.maxWidth;
                    final cardWidth = w >= 1200 ? (w - 48) / 4 : w >= 760 ? (w - 32) / 3 : w >= 500 ? (w - 16) / 2 : w;
                    return Wrap(spacing: 16, runSpacing: 16, children: [for (final m in metrics) SizedBox(width: cardWidth, child: _OpsMetricCard(m))]);
                  },
                ),
                const SizedBox(height: 20),
                Text(_ot(context, 'Needs attention', 'يحتاج تدخل', 'Aandacht vereist'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                if (attention.isEmpty)
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(backgroundColor: VetColors.softGreen, child: Icon(Icons.check_circle_rounded, color: VetColors.green)),
                      title: Text(_ot(context, 'No critical operational issues right now', 'لا توجد مشاكل تشغيل حرجة الآن', 'Geen kritieke operationele problemen op dit moment'), style: const TextStyle(fontWeight: FontWeight.w900)),
                      subtitle: Text(_ot(context, 'Vet AI production services look healthy from the admin control plane.', 'خدمات Vet AI تبدو مستقرة من لوحة الإدارة.', 'Vet AI-productiediensten lijken gezond vanuit het beheercentrum.')),
                    ),
                  )
                else
                  for (final item in attention)
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(backgroundColor: item.color.withValues(alpha: .12), child: Icon(item.icon, color: item.color)),
                        title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                        trailing: Text(item.value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: item.color)),
                      ),
                    ),
                const SizedBox(height: 18),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      spacing: 22,
                      runSpacing: 12,
                      children: [
                        _MiniStatus(label: _ot(context, 'Suspended customers', 'عملاء موقوفون', 'Geschorste klanten'), value: suspended),
                        _MiniStatus(label: _ot(context, 'Closed accounts', 'حسابات مغلقة', 'Gesloten accounts'), value: closed),
                        _MiniStatus(label: _ot(context, 'Disabled sensors', 'حساسات متوقفة', 'Uitgeschakelde sensoren'), value: _n(d, 'sensors_disabled')),
                        _MiniStatus(label: _ot(context, 'Admin push devices', 'أجهزة Push للإدارة', 'Admin push-apparaten'), value: _n(d, 'admin_push_devices_enabled')),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          );
        },
      );
}

class _OperationsHero extends StatelessWidget {
  const _OperationsHero({required this.maintenance, required this.generatedAt, required this.onRefresh});
  final bool maintenance;
  final String generatedAt;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: VetColors.surface2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: maintenance ? VetColors.red.withValues(alpha: .35) : VetColors.green.withValues(alpha: .28)),
        ),
        child: Row(children: [
          CircleAvatar(
            radius: 27,
            backgroundColor: maintenance ? VetColors.red.withValues(alpha: .12) : VetColors.softGreen,
            child: Icon(maintenance ? Icons.build_circle_rounded : Icons.health_and_safety_rounded, color: maintenance ? VetColors.red : VetColors.green, size: 31),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_ot(context, 'Vet AI Global Operations', 'تشغيل Vet AI العالمي', 'Vet AI Global Operations'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(
              maintenance
                  ? _ot(context, 'MAINTENANCE MODE is active. Customer farm access is blocked by the server.', 'وضع الصيانة مفعّل. وصول العملاء لبيانات المزارع موقوف من السيرفر.', 'ONDERHOUDSMODUS is actief. Klanttoegang tot boerderijen is server-side geblokkeerd.')
                  : _ot(context, 'Live control-plane health across customers, farms, sensors, alerts, support, billing and push delivery.', 'مراقبة مباشرة للعملاء والمزارع والحساسات والإنذارات والدعم والفواتير وPush.', 'Live control-plane status voor klanten, boerderijen, sensoren, alarmen, support, facturering en push.'),
              style: const TextStyle(color: VetColors.muted, height: 1.4),
            ),
            if (generatedAt.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text('${_ot(context, 'Server snapshot', 'آخر قراءة من السيرفر', 'Servermomentopname')}: $generatedAt', style: const TextStyle(fontSize: 11, color: VetColors.muted)),
            ],
          ])),
          IconButton.filledTonal(onPressed: onRefresh, icon: const Icon(Icons.refresh_rounded)),
        ]),
      );
}

class _ServiceChip extends StatelessWidget {
  const _ServiceChip({required this.label, required this.enabled});
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Chip(
        avatar: Icon(enabled ? Icons.check_circle_rounded : Icons.pause_circle_rounded, size: 18, color: enabled ? VetColors.green : VetColors.red),
        label: Text('$label • ${enabled ? _ot(context, 'ON', 'يعمل', 'AAN') : _ot(context, 'OFF', 'متوقف', 'UIT')}'),
      );
}

class _OpsMetric {
  const _OpsMetric(this.icon, this.label, this.value, this.color);
  final IconData icon;
  final String label;
  final int value;
  final Color color;
}

class _OpsMetricCard extends StatelessWidget {
  const _OpsMetricCard(this.metric);
  final _OpsMetric metric;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: metric.color.withValues(alpha: .12), borderRadius: BorderRadius.circular(13)), child: Icon(metric.icon, color: metric.color)),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${metric.value}', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
              Text(metric.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: VetColors.muted, fontWeight: FontWeight.w700, fontSize: 12)),
            ])),
          ]),
        ),
      );
}

class _AttentionItem {
  const _AttentionItem(this.icon, this.value, this.title, this.color);
  final IconData icon;
  final String value;
  final String title;
  final Color color;
}

class _MiniStatus extends StatelessWidget {
  const _MiniStatus({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$value', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: VetColors.muted, fontWeight: FontWeight.w700)),
      ]);
}

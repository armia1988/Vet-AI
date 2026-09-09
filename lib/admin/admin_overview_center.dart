import 'package:flutter/material.dart';

import '../i18n/vet_locale.dart';
import '../theme/app_theme.dart';
import 'admin_service.dart';

String _ovt(BuildContext context, String en, String ar, String nl) =>
    VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

class VetAdminOverviewCenter extends StatefulWidget {
  const VetAdminOverviewCenter({super.key});

  @override
  State<VetAdminOverviewCenter> createState() => _VetAdminOverviewCenterState();
}

class _VetAdminOverviewCenterState extends State<VetAdminOverviewCenter> {
  final admin = VetAdminService.instance;
  late Future<_OverviewData> future = _load();

  Future<_OverviewData> _load() async {
    final healthValue = await admin.client.rpc('admin_operations_health');
    final health = healthValue is Map
        ? Map<String, dynamic>.from(healthValue)
        : <String, dynamic>{};
    final values = await Future.wait<List<Map<String, dynamic>>>([
      admin.alerts(),
      admin.supportThreads(),
      admin.sensors(),
      admin.payments(),
    ]);
    return _OverviewData(
      health: health,
      alerts: values[0],
      support: values[1],
      sensors: values[2],
      payments: values[3],
    );
  }

  void reload() => setState(() => future = _load());

  dynamic _setting(Map<String, dynamic> health, String key) {
    final settings = health['system_settings'];
    if (settings is Map) return settings[key];
    return null;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_OverviewData>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text('${snapshot.error}', style: const TextStyle(color: VetColors.red)),
              ),
            );
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!;
          final h = data.health;
          final maintenance = _setting(h, 'maintenance_mode') == true;
          final ingest = _setting(h, 'sensor_ingest_enabled') != false;
          final push = _setting(h, 'sensor_alert_push_enabled') != false;
          final supportPush = _setting(h, 'support_push_enabled') != false;
          final broadcast = _setting(h, 'admin_broadcast_push_enabled') != false;
          final signup = _setting(h, 'customer_signup_enabled') != false;

          final recentRed = data.alerts
              .where((e) => e['risk'] == 'red' && '${e['admin_status'] ?? 'open'}' == 'open')
              .take(5)
              .toList();
          final urgentSupport = data.support
              .where((e) => e['status'] != 'closed' && e['priority'] == 'urgent')
              .take(5)
              .toList();
          final offlineSensors = data.sensors
              .where((e) => e['active'] == true && _isOffline(e['last_seen_at'], _setting(h, 'sensor_offline_minutes')))
              .take(8)
              .toList();
          final failedPayments = data.payments
              .where((e) => e['status'] == 'failed' || e['status'] == 'pending')
              .take(6)
              .toList();

          return RefreshIndicator(
            onRefresh: () async => reload(),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        _ovt(context, 'Vet AI Global Operations', 'مركز العمليات العالمي لـ Vet AI', 'Vet AI wereldwijde operaties'),
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _ovt(context, 'Live health, customers, farms, sensors, alerts, support, billing and delivery status from one command center.', 'صحة النظام والعملاء والمزارع والحساسات والإنذارات والدعم والفوترة وحالة الإرسال مباشرة من مركز قيادة واحد.', 'Live systeemgezondheid, klanten, boerderijen, sensoren, alarmen, support, facturering en bezorgstatus vanuit één controlecentrum.'),
                        style: const TextStyle(color: VetColors.muted),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filledTonal(onPressed: reload, icon: const Icon(Icons.refresh_rounded)),
                ]),
                const SizedBox(height: 16),
                _SystemBanner(
                  maintenance: maintenance,
                  ingest: ingest,
                  push: push,
                  supportPush: supportPush,
                  broadcast: broadcast,
                  signup: signup,
                ),
                const SizedBox(height: 16),
                LayoutBuilder(builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final cardWidth = width >= 1200
                      ? (width - 36) / 4
                      : width >= 760
                          ? (width - 24) / 3
                          : width >= 500
                              ? (width - 12) / 2
                              : width;
                  final metrics = [
                    _Metric(Icons.people_alt_rounded, _ovt(context, 'Customers', 'العملاء', 'Klanten'), '${h['customers_total'] ?? 0}', VetColors.blue),
                    _Metric(Icons.domain_rounded, _ovt(context, 'Farms', 'المزارع', 'Boerderijen'), '${h['farms_total'] ?? 0}', VetColors.green),
                    _Metric(Icons.pets_rounded, _ovt(context, 'Active animals', 'الحيوانات النشطة', 'Actieve dieren'), '${h['animals_active'] ?? 0}', VetColors.green),
                    _Metric(Icons.sensors_rounded, _ovt(context, 'Active sensors', 'الحساسات النشطة', 'Actieve sensoren'), '${h['sensors_active'] ?? 0}', VetColors.green),
                    _Metric(Icons.sensors_off_rounded, _ovt(context, 'Offline sensors', 'حساسات غير متصلة', 'Offline sensoren'), '${h['sensors_offline'] ?? 0}', VetColors.red),
                    _Metric(Icons.crisis_alert_rounded, _ovt(context, 'Open red alerts', 'إنذارات حمراء مفتوحة', 'Open rode alarmen'), '${h['alerts_red_open'] ?? 0}', VetColors.red),
                    _Metric(Icons.warning_amber_rounded, _ovt(context, 'Open orange alerts', 'إنذارات برتقالية مفتوحة', 'Open oranje alarmen'), '${h['alerts_orange_open'] ?? 0}', VetColors.history),
                    _Metric(Icons.support_agent_rounded, _ovt(context, 'Open support', 'دعم مفتوح', 'Open support'), '${h['support_open'] ?? 0}', VetColors.blue),
                    _Metric(Icons.workspace_premium_rounded, _ovt(context, 'Active subscriptions', 'اشتراكات نشطة', 'Actieve abonnementen'), '${h['subscriptions_active'] ?? 0}', VetColors.green),
                    _Metric(Icons.money_off_csred_rounded, _ovt(context, 'Past due', 'اشتراكات متأخرة', 'Achterstallig'), '${h['subscriptions_past_due'] ?? 0}', VetColors.red),
                    _Metric(Icons.notifications_active_rounded, _ovt(context, 'Customer push devices', 'أجهزة إشعار العملاء', 'Klant-pushapparaten'), '${h['customer_push_devices_enabled'] ?? 0}', VetColors.blue),
                    _Metric(Icons.history_rounded, _ovt(context, 'Admin actions 24h', 'عمليات الإدارة 24س', 'Adminacties 24u'), '${h['audit_events_24h'] ?? 0}', VetColors.history),
                  ];
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [for (final m in metrics) SizedBox(width: cardWidth, child: _MetricCard(metric: m))],
                  );
                }),
                const SizedBox(height: 18),
                _SectionTitle(icon: Icons.crisis_alert_rounded, title: _ovt(context, 'Critical attention', 'أهم الحالات التي تحتاج تدخل', 'Kritieke aandacht')),
                const SizedBox(height: 8),
                _AttentionGrid(
                  redAlerts: recentRed,
                  urgentSupport: urgentSupport,
                  offlineSensors: offlineSensors,
                  failedPayments: failedPayments,
                ),
                const SizedBox(height: 18),
                _SectionTitle(icon: Icons.health_and_safety_rounded, title: _ovt(context, 'Platform health', 'صحة المنصة', 'Platformgezondheid')),
                const SizedBox(height: 8),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  _HealthChip(label: _ovt(context, 'Sensor ingestion', 'استقبال الحساسات', 'Sensorinname'), ok: ingest),
                  _HealthChip(label: _ovt(context, 'Sensor alerts', 'إشعارات الحساسات', 'Sensoralarmen'), ok: push),
                  _HealthChip(label: _ovt(context, 'Admin broadcast', 'الإشعار العام', 'Admin-broadcast'), ok: broadcast),
                  _HealthChip(label: _ovt(context, 'Support push', 'إشعارات الدعم', 'Support-push'), ok: supportPush),
                  _HealthChip(label: _ovt(context, 'Customer signup', 'تسجيل العملاء', 'Klantregistratie'), ok: signup),
                  _HealthChip(label: _ovt(context, 'Customer access', 'دخول العملاء', 'Klanttoegang'), ok: !maintenance),
                  _HealthChip(label: _ovt(context, 'Customer APNs 24h', 'إرسال APNs للعملاء 24س', 'Klant-APNs 24u'), ok: (num.tryParse('${h['customer_push_failures_24h'] ?? 0}') ?? 0) == 0),
                ]),
                const SizedBox(height: 10),
                Text(
                  '${_ovt(context, 'Snapshot generated', 'وقت تحديث البيانات', 'Snapshot gemaakt')}: ${h['generated_at'] ?? '-'}',
                  style: const TextStyle(color: VetColors.muted, fontSize: 11),
                ),
                const SizedBox(height: 48),
              ],
            ),
          );
        },
      );

  bool _isOffline(dynamic lastSeen, dynamic threshold) {
    if (lastSeen == null) return true;
    final date = DateTime.tryParse('$lastSeen');
    if (date == null) return true;
    final minutes = threshold is num ? threshold.toInt() : int.tryParse('$threshold') ?? 10;
    return DateTime.now().toUtc().difference(date.toUtc()).inMinutes >= minutes;
  }
}

class _SystemBanner extends StatelessWidget {
  const _SystemBanner({required this.maintenance, required this.ingest, required this.push, required this.supportPush, required this.broadcast, required this.signup});
  final bool maintenance;
  final bool ingest;
  final bool push;
  final bool supportPush;
  final bool broadcast;
  final bool signup;

  @override
  Widget build(BuildContext context) {
    final allGood = !maintenance && ingest && push && supportPush && broadcast && signup;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: (allGood ? VetColors.green : VetColors.history).withValues(alpha: .08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: (allGood ? VetColors.green : VetColors.history).withValues(alpha: .35)),
      ),
      child: Row(children: [
        CircleAvatar(
          backgroundColor: (allGood ? VetColors.green : VetColors.history).withValues(alpha: .13),
          child: Icon(allGood ? Icons.check_circle_rounded : Icons.warning_amber_rounded, color: allGood ? VetColors.green : VetColors.history),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            allGood
                ? _ovt(context, 'Core platform services are enabled', 'الخدمات الأساسية للمنصة تعمل', 'Kernplatformdiensten zijn ingeschakeld')
                : _ovt(context, 'One or more platform controls are limited', 'يوجد إعداد أو أكثر يحد من تشغيل المنصة', 'Eén of meer platforminstellingen zijn beperkt'),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 3),
          Text(
            maintenance
                ? _ovt(context, 'Maintenance mode is currently blocking normal customer farm access.', 'وضع الصيانة يمنع حاليًا وصول العملاء العادي للمزارع.', 'Onderhoudsmodus blokkeert momenteel normale klanttoegang tot boerderijen.')
                : _ovt(context, 'Server controls are live and protected by administrator permissions.', 'مفاتيح السيرفر تعمل ومحمية بصلاحيات الإدارة.', 'Serverinstellingen zijn actief en beschermd door beheerdersrechten.'),
            style: const TextStyle(color: VetColors.muted),
          ),
        ])),
      ]),
    );
  }
}

class _Metric {
  const _Metric(this.icon, this.title, this.value, this.color);
  final IconData icon;
  final String title;
  final String value;
  final Color color;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});
  final _Metric metric;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(children: [
            CircleAvatar(backgroundColor: metric.color.withValues(alpha: .12), child: Icon(metric.icon, color: metric.color)),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(metric.value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(metric.title, style: const TextStyle(color: VetColors.muted, fontSize: 12)),
            ])),
          ]),
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 20),
        const SizedBox(width: 7),
        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
      ]);
}

class _AttentionGrid extends StatelessWidget {
  const _AttentionGrid({required this.redAlerts, required this.urgentSupport, required this.offlineSensors, required this.failedPayments});
  final List<Map<String, dynamic>> redAlerts;
  final List<Map<String, dynamic>> urgentSupport;
  final List<Map<String, dynamic>> offlineSensors;
  final List<Map<String, dynamic>> failedPayments;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 850;
        final width = wide ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          SizedBox(width: width, child: _AttentionCard(icon: Icons.crisis_alert_rounded, title: _ovt(context, 'Open red alerts', 'إنذارات حمراء مفتوحة', 'Open rode alarmen'), color: VetColors.red, rows: redAlerts, line: (r) => '${r['title'] ?? '-'} • ${r['metric'] ?? r['source'] ?? '-'}')),
          SizedBox(width: width, child: _AttentionCard(icon: Icons.support_agent_rounded, title: _ovt(context, 'Urgent support', 'دعم عاجل', 'Urgente support'), color: VetColors.history, rows: urgentSupport, line: (r) => '${r['subject'] ?? '-'} • ${r['status'] ?? '-'}')),
          SizedBox(width: width, child: _AttentionCard(icon: Icons.sensors_off_rounded, title: _ovt(context, 'Offline sensors', 'حساسات غير متصلة', 'Offline sensoren'), color: VetColors.red, rows: offlineSensors, line: (r) => '${r['display_name'] ?? r['device_uid'] ?? '-'} • ${r['last_seen_at'] ?? _ovt(context, 'Never seen', 'لم يتصل', 'Nooit gezien')}')),
          SizedBox(width: width, child: _AttentionCard(icon: Icons.payments_rounded, title: _ovt(context, 'Payments needing attention', 'مدفوعات تحتاج مراجعة', 'Betalingen met aandacht'), color: VetColors.history, rows: failedPayments, line: (r) => '${r['invoice_number'] ?? '-'} • ${r['currency'] ?? ''} ${r['amount'] ?? ''} • ${r['status']}')),
        ]);
      });
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({required this.icon, required this.title, required this.color, required this.rows, required this.line});
  final IconData icon;
  final String title;
  final Color color;
  final List<Map<String, dynamic>> rows;
  final String Function(Map<String, dynamic>) line;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(icon, color: color), const SizedBox(width: 8), Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900))), Chip(label: Text('${rows.length}'))]),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              Row(children: [const Icon(Icons.check_circle_rounded, size: 18, color: VetColors.green), const SizedBox(width: 6), Text(_ovt(context, 'Nothing urgent here.', 'لا توجد حالة عاجلة هنا.', 'Niets urgents hier.'), style: const TextStyle(color: VetColors.muted))])
            else
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.circle, size: 7, color: color),
                    const SizedBox(width: 7),
                    Expanded(child: Text(line(row), maxLines: 2, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
          ]),
        ),
      );
}

class _HealthChip extends StatelessWidget {
  const _HealthChip({required this.label, required this.ok});
  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) => Chip(
        avatar: Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded, size: 17, color: ok ? VetColors.green : VetColors.red),
        label: Text(label),
      );
}

class _OverviewData {
  const _OverviewData({required this.health, required this.alerts, required this.support, required this.sensors, required this.payments});
  final Map<String, dynamic> health;
  final List<Map<String, dynamic>> alerts;
  final List<Map<String, dynamic>> support;
  final List<Map<String, dynamic>> sensors;
  final List<Map<String, dynamic>> payments;
}

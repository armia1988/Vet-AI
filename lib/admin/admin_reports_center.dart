import 'package:flutter/material.dart';

import '../i18n/vet_locale.dart';
import '../theme/app_theme.dart';
import 'admin_service.dart';

String _rt(BuildContext context, String en, String ar, String nl) =>
    VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

class VetAdminReportsCenter extends StatefulWidget {
  const VetAdminReportsCenter({super.key});

  @override
  State<VetAdminReportsCenter> createState() => _VetAdminReportsCenterState();
}

class _VetAdminReportsCenterState extends State<VetAdminReportsCenter> {
  final admin = VetAdminService.instance;
  int days = 30;
  late Future<Map<String, dynamic>> future = _load();

  Future<Map<String, dynamic>> _load() async {
    final raw = await admin.client.rpc(
      'admin_reports_snapshot',
      params: {'p_days': days},
    );
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  void reload() => setState(() => future = _load());

  int n(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  double d(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  List<Map<String, dynamic>> rows(dynamic value) {
    if (value is! List) return const [];
    return value.map((e) => Map<String, dynamic>.from(e as Map)).toList();
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
                  const Icon(Icons.error_outline_rounded, size: 52, color: VetColors.red),
                  const SizedBox(height: 10),
                  Text(_rt(context, 'Reports could not be loaded.', 'تعذر تحميل التقارير.', 'Rapporten konden niet worden geladen.'), style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  FilledButton.icon(onPressed: reload, icon: const Icon(Icons.refresh_rounded), label: Text(_rt(context, 'Retry', 'إعادة المحاولة', 'Opnieuw'))),
                ]),
              ),
            );
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!;
          final summary = data['summary'] is Map
              ? Map<String, dynamic>.from(data['summary'] as Map)
              : <String, dynamic>{};
          final daily = rows(data['daily']);
          final revenue = rows(data['revenue_by_currency']);
          final subscriptions = rows(data['subscription_statuses']);
          final languages = rows(data['customer_languages']);
          final fleet = rows(data['sensor_fleet']);
          final topFarms = rows(data['top_alert_farms']);
          final maxAlerts = daily.fold<int>(0, (m, e) => n(e['alerts']) > m ? n(e['alerts']) : m);

          final cards = <_ReportMetric>[
            _ReportMetric(Icons.person_add_alt_1_rounded, _rt(context, 'New customers', 'عملاء جدد', 'Nieuwe klanten'), n(summary['new_customers']), VetColors.blue),
            _ReportMetric(Icons.add_business_rounded, _rt(context, 'New farms', 'مزارع جديدة', 'Nieuwe boerderijen'), n(summary['new_farms']), VetColors.green),
            _ReportMetric(Icons.pets_rounded, _rt(context, 'New animals', 'حيوانات جديدة', 'Nieuwe dieren'), n(summary['new_animals']), VetColors.history),
            _ReportMetric(Icons.warning_amber_rounded, _rt(context, 'Alerts', 'الإنذارات', 'Alarmen'), n(summary['alerts_total']), VetColors.history),
            _ReportMetric(Icons.crisis_alert_rounded, _rt(context, 'Red alerts', 'إنذارات حمراء', 'Rode alarmen'), n(summary['red_alerts']), VetColors.red),
            _ReportMetric(Icons.support_agent_rounded, _rt(context, 'New support', 'رسائل دعم جديدة', 'Nieuwe support'), n(summary['support_new']), VetColors.blue),
            _ReportMetric(Icons.sensors_rounded, _rt(context, 'Sensors online now', 'حساسات متصلة الآن', 'Sensoren online'), n(summary['sensors_online_now']), VetColors.green),
            _ReportMetric(Icons.sensors_off_rounded, _rt(context, 'Sensors offline now', 'حساسات غير متصلة', 'Sensoren offline'), n(summary['sensors_offline_now']), n(summary['sensors_offline_now']) > 0 ? VetColors.red : VetColors.green),
            _ReportMetric(Icons.workspace_premium_rounded, _rt(context, 'Active subscriptions', 'اشتراكات فعالة', 'Actieve abonnementen'), n(summary['active_subscriptions']), VetColors.green),
            _ReportMetric(Icons.money_off_rounded, _rt(context, 'Past due', 'اشتراكات متأخرة', 'Achterstallig'), n(summary['past_due_subscriptions']), n(summary['past_due_subscriptions']) > 0 ? VetColors.red : VetColors.green),
            _ReportMetric(Icons.check_circle_rounded, _rt(context, 'Paid payments', 'مدفوعات ناجحة', 'Betaalde betalingen'), n(summary['payments_paid_count']), VetColors.green),
            _ReportMetric(Icons.error_rounded, _rt(context, 'Failed payments', 'مدفوعات فاشلة', 'Mislukte betalingen'), n(summary['payments_failed_count']), n(summary['payments_failed_count']) > 0 ? VetColors.red : VetColors.green),
          ];

          return RefreshIndicator(
            onRefresh: () async => reload(),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_rt(context, 'Reports & analytics', 'التقارير والتحليلات', 'Rapporten & analyse'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 5),
                    Text(_rt(context, 'Commercial, customer, sensor, alert and support performance from the production database.', 'تحليلات العملاء والحساسات والإنذارات والدعم والاشتراكات والمدفوعات من قاعدة الإنتاج.', 'Commerciële, klant-, sensor-, alarm- en supportanalyse uit de productiedatabase.'), style: const TextStyle(color: VetColors.muted)),
                  ])),
                  IconButton.filledTonal(onPressed: reload, icon: const Icon(Icons.refresh_rounded)),
                ]),
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final value in [7, 30, 90, 180])
                    ChoiceChip(
                      selected: days == value,
                      onSelected: (_) {
                        if (days == value) return;
                        setState(() {
                          days = value;
                          future = _load();
                        });
                      },
                      label: Text('$value ${_rt(context, 'days', 'يوم', 'dagen')}'),
                    ),
                ]),
                const SizedBox(height: 16),
                LayoutBuilder(builder: (context, c) {
                  final width = c.maxWidth >= 1200
                      ? (c.maxWidth - 48) / 4
                      : c.maxWidth >= 760
                          ? (c.maxWidth - 32) / 3
                          : c.maxWidth >= 500
                              ? (c.maxWidth - 16) / 2
                              : c.maxWidth;
                  return Wrap(spacing: 16, runSpacing: 16, children: [for (final item in cards) SizedBox(width: width, child: _ReportMetricCard(item))]);
                }),
                const SizedBox(height: 20),
                _section(context, Icons.account_balance_wallet_rounded, _rt(context, 'Revenue by currency', 'الإيرادات حسب العملة', 'Omzet per valuta'), [
                  if (revenue.isEmpty)
                    _empty(context)
                  else
                    for (final row in revenue)
                      ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.payments_rounded)),
                        title: Text('${row['currency'] ?? ''} ${d(row['amount']).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w900)),
                        subtitle: Text('${n(row['count'])} ${_rt(context, 'paid transactions', 'عملية مدفوعة', 'betaalde transacties')}'),
                      ),
                ]),
                const SizedBox(height: 14),
                _section(context, Icons.timeline_rounded, _rt(context, 'Daily activity', 'النشاط اليومي', 'Dagelijkse activiteit'), [
                  if (daily.isEmpty)
                    _empty(context)
                  else
                    for (final row in daily.reversed.take(days > 30 ? 30 : days))
                      _DailyActivityRow(
                        date: '${row['date'] ?? ''}',
                        alerts: n(row['alerts']),
                        red: n(row['red_alerts']),
                        orange: n(row['orange_alerts']),
                        support: n(row['support_new']),
                        customers: n(row['new_customers']),
                        maxAlerts: maxAlerts,
                      ),
                ]),
                const SizedBox(height: 14),
                LayoutBuilder(builder: (context, c) {
                  final wide = c.maxWidth >= 900;
                  final width = wide ? (c.maxWidth - 14) / 2 : c.maxWidth;
                  return Wrap(spacing: 14, runSpacing: 14, children: [
                    SizedBox(width: width, child: _section(context, Icons.workspace_premium_rounded, _rt(context, 'Subscription status', 'حالات الاشتراك', 'Abonnementsstatus'), [
                      if (subscriptions.isEmpty) _empty(context) else for (final row in subscriptions) _CountRow(label: '${row['status'] ?? '-'}', value: n(row['count']))
                    ])),
                    SizedBox(width: width, child: _section(context, Icons.language_rounded, _rt(context, 'Customer languages', 'لغات العملاء', 'Klanttalen'), [
                      if (languages.isEmpty) _empty(context) else for (final row in languages.take(12)) _CountRow(label: '${row['language'] ?? '-'}', value: n(row['count']))
                    ])),
                    SizedBox(width: width, child: _section(context, Icons.sensors_rounded, _rt(context, 'Sensor fleet', 'أسطول الحساسات', 'Sensorvloot'), [
                      if (fleet.isEmpty)
                        _empty(context)
                      else
                        for (final row in fleet)
                          ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.sensors_rounded)),
                            title: Text('${row['device_type'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w900)),
                            subtitle: Text('${_rt(context, 'Online', 'متصل', 'Online')}: ${n(row['online'])} • ${_rt(context, 'Offline', 'غير متصل', 'Offline')}: ${n(row['offline'])} • ${_rt(context, 'Disabled', 'موقوف', 'Uitgeschakeld')}: ${n(row['disabled'])}'),
                            trailing: Text('${n(row['total'])}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                          ),
                    ])),
                    SizedBox(width: width, child: _section(context, Icons.domain_rounded, _rt(context, 'Farms with most alerts', 'المزارع الأكثر إنذارات', 'Boerderijen met meeste alarmen'), [
                      if (topFarms.isEmpty)
                        _empty(context)
                      else
                        for (final row in topFarms)
                          ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.domain_rounded)),
                            title: Text('${row['company'] ?? ''} / ${row['farm'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w900)),
                            trailing: Text('${n(row['alerts'])}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: VetColors.red)),
                          ),
                    ])),
                  ]);
                }),
                const SizedBox(height: 40),
              ],
            ),
          );
        },
      );

  Widget _section(BuildContext context, IconData icon, String title, List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(icon, color: VetColors.green), const SizedBox(width: 8), Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)))]),
            const SizedBox(height: 8),
            ...children,
          ]),
        ),
      );

  Widget _empty(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(_rt(context, 'No data in this period.', 'لا توجد بيانات في هذه الفترة.', 'Geen gegevens in deze periode.'), style: const TextStyle(color: VetColors.muted)),
      );
}

class _ReportMetric {
  const _ReportMetric(this.icon, this.label, this.value, this.color);
  final IconData icon;
  final String label;
  final int value;
  final Color color;
}

class _ReportMetricCard extends StatelessWidget {
  const _ReportMetricCard(this.item);
  final _ReportMetric item;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: item.color.withValues(alpha: .12), borderRadius: BorderRadius.circular(13)), child: Icon(item.icon, color: item.color)),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${item.value}', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
              Text(item.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: VetColors.muted, fontSize: 12, fontWeight: FontWeight.w700)),
            ])),
          ]),
        ),
      );
}

class _CountRow extends StatelessWidget {
  const _CountRow({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        trailing: Text('$value', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      );
}

class _DailyActivityRow extends StatelessWidget {
  const _DailyActivityRow({required this.date, required this.alerts, required this.red, required this.orange, required this.support, required this.customers, required this.maxAlerts});
  final String date;
  final int alerts;
  final int red;
  final int orange;
  final int support;
  final int customers;
  final int maxAlerts;

  @override
  Widget build(BuildContext context) {
    final ratio = maxAlerts <= 0 ? 0.0 : (alerts / maxAlerts).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SizedBox(width: 92, child: Text(date, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
          Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: ratio, minHeight: 7))),
          const SizedBox(width: 10),
          SizedBox(width: 42, child: Text('$alerts', textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w900))),
        ]),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 92),
          child: Text(
            '${_rt(context, 'Red', 'أحمر', 'Rood')} $red • ${_rt(context, 'Orange', 'برتقالي', 'Oranje')} $orange • ${_rt(context, 'Support', 'دعم', 'Support')} $support • ${_rt(context, 'New customers', 'عملاء جدد', 'Nieuwe klanten')} $customers',
            style: const TextStyle(fontSize: 10.5, color: VetColors.muted),
          ),
        ),
      ]),
    );
  }
}

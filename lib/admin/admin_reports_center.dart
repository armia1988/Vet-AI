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

  Future<void> reload() async {
    final next = _load();
    if (mounted) setState(() => future = next);
    await next;
  }

  int n(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  double? number(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  String value(dynamic raw, {int decimals = 1, String suffix = ''}) {
    final v = number(raw);
    if (v == null) return '—';
    return '${v.toStringAsFixed(decimals)}$suffix';
  }

  List<Map<String, dynamic>> rows(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
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
                  const Icon(Icons.error_outline_rounded,
                      size: 52, color: VetColors.red),
                  const SizedBox(height: 10),
                  Text(
                    _rt(context, 'Intelligence reports could not be loaded.',
                        'تعذر تحميل مركز التحليلات الذكية.',
                        'Intelligente rapporten konden niet worden geladen.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: reload,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(_rt(context, 'Retry', 'إعادة المحاولة', 'Opnieuw')),
                  ),
                ]),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!;
          final summary = data['summary'] is Map
              ? Map<String, dynamic>.from(data['summary'] as Map)
              : <String, dynamic>{};
          final liveSensors = rows(data['latest_sensor_telemetry']);
          final farmHealth = rows(data['farm_health']);
          final aiModels = rows(data['ai_models']);
          final riskMix = rows(data['assessment_risk']);
          final metricQuality = rows(data['metric_quality']);
          final daily = rows(data['daily']);
          final revenue = rows(data['revenue_by_currency']);
          final topFarms = rows(data['top_alert_farms']);
          final sensorFleet = rows(data['sensor_fleet']);
          final generatedAt = '${data['generated_at'] ?? ''}';

          final sensorCount = n(summary['sensors_total']);
          final readingCount = n(summary['sensor_readings']);
          final hasTelemetry = sensorCount > 0 && readingCount > 0;
          final aiTotal = n(summary['assessments_total']);
          final aiGenerated = n(summary['ai_assessments']);
          final aiCoverage = aiTotal <= 0 ? 0 : ((aiGenerated / aiTotal) * 100).round();

          final metrics = <_IntelMetric>[
            _IntelMetric(Icons.sensors_rounded,
                _rt(context, 'Sensors', 'إجمالي الحساسات', 'Sensoren'),
                '$sensorCount', VetColors.green),
            _IntelMetric(Icons.wifi_rounded,
                _rt(context, 'Online now', 'متصل الآن', 'Nu online'),
                '${n(summary['sensors_online_now'])}', VetColors.green),
            _IntelMetric(Icons.wifi_off_rounded,
                _rt(context, 'Offline now', 'غير متصل الآن', 'Nu offline'),
                '${n(summary['sensors_offline_now'])}',
                n(summary['sensors_offline_now']) > 0 ? VetColors.red : VetColors.green),
            _IntelMetric(Icons.data_usage_rounded,
                _rt(context, 'Telemetry samples', 'قراءات الحساسات', 'Telemetriemetingen'),
                '$readingCount', VetColors.blue),
            _IntelMetric(Icons.thermostat_rounded,
                _rt(context, 'Avg body temp', 'متوسط حرارة الجسم', 'Gem. lichaamstemp.'),
                value(summary['avg_body_temperature_c'], decimals: 1, suffix: '°C'), VetColors.history),
            _IntelMetric(Icons.device_thermostat_rounded,
                _rt(context, 'Avg ambient temp', 'متوسط حرارة الجو', 'Gem. omgevingstemp.'),
                value(summary['avg_ambient_temperature_c'], decimals: 1, suffix: '°C'), VetColors.history),
            _IntelMetric(Icons.water_drop_rounded,
                _rt(context, 'Avg humidity', 'متوسط الرطوبة', 'Gem. luchtvochtigheid'),
                value(summary['avg_humidity_percent'], decimals: 1, suffix: '%'), VetColors.blue),
            _IntelMetric(Icons.battery_alert_rounded,
                _rt(context, 'Low-battery readings', 'قراءات بطارية منخفضة', 'Lage-batterijmetingen'),
                '${n(summary['low_battery_readings'])}',
                n(summary['low_battery_readings']) > 0 ? VetColors.red : VetColors.green),
            _IntelMetric(Icons.psychology_alt_rounded,
                _rt(context, 'Assessments', 'إجمالي التحليلات', 'Beoordelingen'),
                '$aiTotal', VetColors.blue),
            _IntelMetric(Icons.auto_awesome_rounded,
                _rt(context, 'AI analyses', 'تحليلات الذكاء الاصطناعي', 'AI-analyses'),
                '$aiGenerated', VetColors.green),
            _IntelMetric(Icons.crisis_alert_rounded,
                _rt(context, 'Red alerts', 'إنذارات حمراء', 'Rode alarmen'),
                '${n(summary['red_alerts'])}', VetColors.red),
            _IntelMetric(Icons.medical_services_rounded,
                _rt(context, 'Urgent vet review', 'مراجعة بيطرية عاجلة', 'Spoed dierenarts'),
                '${n(summary['urgent_vet_review'])}',
                n(summary['urgent_vet_review']) > 0 ? VetColors.red : VetColors.green),
          ];

          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                MediaQuery.sizeOf(context).width < 600 ? 12 : 20,
                14,
                MediaQuery.sizeOf(context).width < 600 ? 12 : 20,
                60,
              ),
              children: [
                _hero(context, generatedAt, hasTelemetry, aiCoverage),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final period in [7, 30, 90, 180])
                      ChoiceChip(
                        selected: days == period,
                        label: Text('$period ${_rt(context, 'days', 'يوم', 'dagen')}'),
                        onSelected: (_) {
                          if (days == period) return;
                          setState(() {
                            days = period;
                            future = _load();
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _metricGrid(metrics),
                const SizedBox(height: 18),
                if (!hasTelemetry)
                  _noTelemetry(context)
                else
                  _section(
                    context,
                    icon: Icons.monitor_heart_rounded,
                    title: _rt(context, 'Live sensor telemetry — all customers',
                        'القراءات الحية للحساسات — كل العملاء',
                        'Live sensortelemetrie — alle klanten'),
                    subtitle: _rt(
                      context,
                      'Latest production reading from every registered customer sensor. Values are never invented.',
                      'آخر قراءة حقيقية لكل حساس مسجل عند العملاء. لا يتم إنشاء أو تخمين أي قيمة.',
                      'Laatste echte productiemeting van elke klantsensor. Waarden worden nooit verzonnen.',
                    ),
                    children: [
                      LayoutBuilder(builder: (context, c) {
                        final columns = c.maxWidth >= 1200 ? 3 : c.maxWidth >= 720 ? 2 : 1;
                        final gap = 12.0;
                        final width = (c.maxWidth - gap * (columns - 1)) / columns;
                        return Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: [
                            for (final sensor in liveSensors)
                              SizedBox(width: width, child: _sensorCard(context, sensor)),
                          ],
                        );
                      }),
                    ],
                  ),
                const SizedBox(height: 16),
                _section(
                  context,
                  icon: Icons.agriculture_rounded,
                  title: _rt(context, 'Customer & farm intelligence',
                      'ذكاء وتحليل المزارع والعملاء', 'Klant- en boerderij-intelligentie'),
                  subtitle: _rt(
                    context,
                    'Operational risk, sensor coverage and veterinary workload by farm, calculated from production records.',
                    'المخاطر التشغيلية وتغطية الحساسات وعبء المراجعة البيطرية لكل مزرعة محسوبة من بيانات الإنتاج.',
                    'Operationeel risico, sensordekking en veterinaire werklast per boerderij uit productiegegevens.',
                  ),
                  children: [
                    if (farmHealth.isEmpty)
                      _empty(context)
                    else
                      for (final farm in farmHealth) _farmRow(context, farm),
                  ],
                ),
                const SizedBox(height: 16),
                _section(
                  context,
                  icon: Icons.auto_awesome_rounded,
                  title: _rt(context, 'AI + veterinary decision intelligence',
                      'ذكاء اصطناعي + دعم القرار البيطري', 'AI + veterinaire beslissingsintelligentie'),
                  subtitle: _rt(
                    context,
                    'Real assessment usage, model mix, risk mix and safety escalations. AI supports veterinary decisions and does not replace a veterinarian.',
                    'استخدام حقيقي للتحليلات ونماذج الذكاء ومستويات الخطورة والتصعيد الطبي. الذكاء الاصطناعي يدعم القرار البيطري ولا يستبدل الطبيب البيطري.',
                    'Werkelijk gebruik, modelmix, risicomix en veiligheidsescalaties. AI ondersteunt de dierenarts en vervangt deze niet.',
                  ),
                  children: [
                    _aiSummary(context, summary, aiCoverage),
                    const SizedBox(height: 12),
                    LayoutBuilder(builder: (context, c) {
                      final width = c.maxWidth >= 760 ? (c.maxWidth - 12) / 2 : c.maxWidth;
                      return Wrap(spacing: 12, runSpacing: 12, children: [
                        SizedBox(width: width, child: _subPanel(
                          context,
                          _rt(context, 'AI model usage', 'استخدام نماذج الذكاء', 'AI-modelgebruik'),
                          aiModels.isEmpty
                              ? [_empty(context)]
                              : [for (final row in aiModels) _countRow('${row['model'] ?? '-'}', n(row['count']))],
                        )),
                        SizedBox(width: width, child: _subPanel(
                          context,
                          _rt(context, 'Assessment risk mix', 'توزيع مستويات الخطورة', 'Risicomix beoordelingen'),
                          riskMix.isEmpty
                              ? [_empty(context)]
                              : [for (final row in riskMix) _riskRow(context, '${row['risk'] ?? '-'}', n(row['count']))],
                        )),
                      ]);
                    }),
                  ],
                ),
                const SizedBox(height: 16),
                _section(
                  context,
                  icon: Icons.fact_check_rounded,
                  title: _rt(context, 'Telemetry quality & credibility',
                      'جودة ومصداقية بيانات الحساسات', 'Telemetriekwaliteit & betrouwbaarheid'),
                  subtitle: _rt(
                    context,
                    'Sample count and measured range for each metric. A zero sample count means Vet AI has no production evidence for that metric yet.',
                    'عدد العينات والمدى المقاس لكل مؤشر. صفر عينة يعني أن Vet AI لا يملك بيانات إنتاج حقيقية لهذا المؤشر حتى الآن.',
                    'Aantal monsters en gemeten bereik per metriek. Nul monsters betekent dat er nog geen productiegegevens zijn.',
                  ),
                  children: [
                    if (metricQuality.isEmpty)
                      _empty(context)
                    else
                      LayoutBuilder(builder: (context, c) {
                        final columns = c.maxWidth >= 900 ? 3 : c.maxWidth >= 560 ? 2 : 1;
                        final gap = 10.0;
                        final width = (c.maxWidth - gap * (columns - 1)) / columns;
                        return Wrap(spacing: gap, runSpacing: gap, children: [
                          for (final metric in metricQuality)
                            SizedBox(width: width, child: _qualityCard(context, metric)),
                        ]);
                      }),
                  ],
                ),
                const SizedBox(height: 16),
                LayoutBuilder(builder: (context, c) {
                  final width = c.maxWidth >= 880 ? (c.maxWidth - 14) / 2 : c.maxWidth;
                  return Wrap(spacing: 14, runSpacing: 14, children: [
                    SizedBox(width: width, child: _section(
                      context,
                      icon: Icons.sensors_rounded,
                      title: _rt(context, 'Sensor fleet', 'أسطول الحساسات', 'Sensorvloot'),
                      children: sensorFleet.isEmpty
                          ? [_empty(context)]
                          : [for (final row in sensorFleet) ListTile(
                              dense: true,
                              leading: const Icon(Icons.sensors_rounded, color: VetColors.green),
                              title: Text('${row['device_type'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w900)),
                              subtitle: Text('${_rt(context, 'Online', 'متصل', 'Online')}: ${n(row['online'])} • ${_rt(context, 'Offline', 'غير متصل', 'Offline')}: ${n(row['offline'])}'),
                              trailing: Text('${n(row['total'])}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                            )],
                    )),
                    SizedBox(width: width, child: _section(
                      context,
                      icon: Icons.crisis_alert_rounded,
                      title: _rt(context, 'Farms with most alerts', 'المزارع الأكثر إنذارات', 'Boerderijen met meeste alarmen'),
                      children: topFarms.isEmpty
                          ? [_empty(context)]
                          : [for (final row in topFarms.take(10)) ListTile(
                              dense: true,
                              title: Text('${row['company'] ?? ''} / ${row['farm'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w900)),
                              subtitle: Text('${_rt(context, 'Red', 'أحمر', 'Rood')}: ${n(row['red'])} • ${_rt(context, 'Orange', 'برتقالي', 'Oranje')}: ${n(row['orange'])}'),
                              trailing: Text('${n(row['alerts'])}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: VetColors.red)),
                            )],
                    )),
                  ]);
                }),
                const SizedBox(height: 16),
                _section(
                  context,
                  icon: Icons.timeline_rounded,
                  title: _rt(context, 'Daily intelligence activity', 'النشاط التحليلي اليومي', 'Dagelijkse intelligentie-activiteit'),
                  children: daily.isEmpty
                      ? [_empty(context)]
                      : [for (final row in daily.reversed.take(days > 30 ? 30 : days))
                          _dailyRow(context, row)],
                ),
                if (revenue.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _section(
                    context,
                    icon: Icons.account_balance_wallet_rounded,
                    title: _rt(context, 'Recorded revenue', 'الإيرادات المسجلة', 'Geregistreerde omzet'),
                    children: [for (final row in revenue) ListTile(
                      dense: true,
                      leading: const Icon(Icons.payments_rounded, color: VetColors.green),
                      title: Text('${row['currency'] ?? ''} ${value(row['amount'], decimals: 2)}', style: const TextStyle(fontWeight: FontWeight.w900)),
                      trailing: Text('${n(row['count'])}'),
                    )],
                  ),
                ],
              ],
            ),
          );
        },
      );

  Widget _hero(BuildContext context, String generatedAt, bool hasTelemetry, int aiCoverage) =>
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: VetColors.surface2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: VetColors.green.withValues(alpha: .28)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(color: VetColors.softGreen, borderRadius: BorderRadius.circular(15)),
              child: const Icon(Icons.insights_rounded, color: VetColors.green, size: 29),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_rt(context, 'Vet AI Intelligence & Telemetry', 'مركز Vet AI للذكاء والتحليلات والحساسات', 'Vet AI Intelligence & Telemetrie'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text(_rt(context, 'One live production view for sensor telemetry, animal-health risk, AI analysis and farm operations.', 'صورة واحدة حية من بيانات الإنتاج للحساسات ومخاطر صحة الحيوان وتحليلات الذكاء وتشغيل المزارع.', 'Eén live productieoverzicht voor sensoren, diergezondheidsrisico, AI-analyse en boerderijoperaties.'), style: const TextStyle(color: VetColors.muted, height: 1.35)),
            ])),
            IconButton.filledTonal(onPressed: reload, icon: const Icon(Icons.refresh_rounded)),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _statusChip(context, hasTelemetry ? _rt(context, 'Live telemetry connected', 'القياسات الحية متصلة', 'Live telemetrie verbonden') : _rt(context, 'Waiting for sensor telemetry', 'بانتظار قراءات الحساسات', 'Wachten op sensortelemetrie'), hasTelemetry),
            Chip(avatar: const Icon(Icons.auto_awesome_rounded, size: 18, color: VetColors.green), label: Text('${_rt(context, 'AI assessment coverage', 'تغطية التحليل بالذكاء', 'AI-dekking')}: $aiCoverage%')),
            if (generatedAt.isNotEmpty) Chip(avatar: const Icon(Icons.schedule_rounded, size: 18), label: Text(generatedAt, overflow: TextOverflow.ellipsis)),
          ]),
        ]),
      );

  Widget _statusChip(BuildContext context, String label, bool ok) => Chip(
        avatar: Icon(ok ? Icons.check_circle_rounded : Icons.info_rounded,
            color: ok ? VetColors.green : VetColors.history, size: 18),
        label: Text(label),
      );

  Widget _metricGrid(List<_IntelMetric> metrics) => LayoutBuilder(builder: (context, c) {
        final columns = c.maxWidth >= 1200 ? 4 : c.maxWidth >= 760 ? 3 : 2;
        const gap = 10.0;
        final width = (c.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final metric in metrics) SizedBox(width: width, child: _IntelMetricCard(metric)),
        ]);
      });

  Widget _noTelemetry(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: VetColors.history.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: VetColors.history.withValues(alpha: .28)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.sensors_off_rounded, color: VetColors.history, size: 32),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_rt(context, 'No production sensor telemetry has arrived yet', 'لا توجد قراءات حساسات إنتاج حقيقية حتى الآن', 'Er is nog geen productiesensortelemetrie ontvangen'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 5),
            Text(_rt(context, 'Vet AI will never show a made-up temperature. As soon as customer sensors send readings, this page fills automatically with body temperature, ambient temperature, humidity, activity, battery, data age and quality.', 'Vet AI لن يعرض درجة حرارة وهمية. بمجرد أن ترسل حساسات العملاء قراءات، ستظهر هنا تلقائيًا حرارة الجسم وحرارة الجو والرطوبة والنشاط والبطارية وعمر القراءة وجودتها.', 'Vet AI toont nooit verzonnen temperaturen. Zodra sensoren data sturen verschijnen lichaamstemperatuur, omgevingstemperatuur, vochtigheid, activiteit, batterij, leeftijd en kwaliteit automatisch.'), style: const TextStyle(color: VetColors.muted, height: 1.4)),
          ])),
        ]),
      );

  Widget _section(BuildContext context,
          {required IconData icon,
          required String title,
          String? subtitle,
          required List<Widget> children}) =>
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: VetColors.green),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
            ]),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(color: VetColors.muted, height: 1.35, fontSize: 12.5)),
            ],
            const SizedBox(height: 10),
            ...children,
          ]),
        ),
      );

  Widget _sensorCard(BuildContext context, Map<String, dynamic> s) {
    final online = s['online'] == true;
    final temp = value(s['body_temperature_c'], decimals: 1, suffix: '°C');
    final ambient = value(s['ambient_temperature_c'], decimals: 1, suffix: '°C');
    final quality = value(s['telemetry_quality_percent'], decimals: 0, suffix: '%');
    return Card(
      elevation: 0,
      color: VetColors.surface2,
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(backgroundColor: (online ? VetColors.green : VetColors.red).withValues(alpha: .12), child: Icon(Icons.sensors_rounded, color: online ? VetColors.green : VetColors.red)),
            const SizedBox(width: 9),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${s['display_name'] ?? s['device_uid'] ?? '-'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
              Text('${s['company'] ?? '-'} / ${s['farm'] ?? '-'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: VetColors.muted, fontSize: 11.5)),
            ])),
            _tinyStatus(online ? _rt(context, 'Online', 'متصل', 'Online') : _rt(context, 'Offline', 'غير متصل', 'Offline'), online),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _sensorValue(Icons.thermostat_rounded, _rt(context, 'Body', 'الجسم', 'Lichaam'), temp),
            _sensorValue(Icons.device_thermostat_rounded, _rt(context, 'Ambient', 'الجو', 'Omgeving'), ambient),
            _sensorValue(Icons.water_drop_rounded, _rt(context, 'Humidity', 'الرطوبة', 'Vocht'), value(s['humidity_percent'], decimals: 0, suffix: '%')),
            _sensorValue(Icons.directions_run_rounded, _rt(context, 'Activity', 'النشاط', 'Activiteit'), value(s['activity_index'], decimals: 1)),
            _sensorValue(Icons.battery_std_rounded, _rt(context, 'Battery', 'البطارية', 'Batterij'), value(s['battery_percent'], decimals: 0, suffix: '%')),
            _sensorValue(Icons.verified_rounded, _rt(context, 'Data quality', 'جودة البيانات', 'Datakwaliteit'), quality),
          ]),
          const SizedBox(height: 9),
          Text('${_rt(context, 'Last reading', 'آخر قراءة', 'Laatste meting')}: ${s['recorded_at'] ?? '—'}', style: const TextStyle(color: VetColors.muted, fontSize: 10.5)),
          if (s['recent_risk'] != null) ...[
            const SizedBox(height: 4),
            Text('${_rt(context, 'Recent sensor risk', 'آخر خطورة من الحساس', 'Recent sensorrisico')}: ${s['recent_risk']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5)),
          ],
        ]),
      ),
    );
  }

  Widget _sensorValue(IconData icon, String label, String valueText) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(color: VetColors.surface3, borderRadius: BorderRadius.circular(10), border: Border.all(color: VetColors.border)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: VetColors.green),
          const SizedBox(width: 5),
          Text('$label ', style: const TextStyle(fontSize: 10.5, color: VetColors.muted)),
          Text(valueText, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900)),
        ]),
      );

  Widget _tinyStatus(String text, bool ok) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(color: (ok ? VetColors.green : VetColors.red).withValues(alpha: .1), borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(color: ok ? VetColors.green : VetColors.red, fontWeight: FontWeight.w900, fontSize: 10)),
      );

  Widget _farmRow(BuildContext context, Map<String, dynamic> f) => Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: VetColors.surface2, borderRadius: BorderRadius.circular(14), border: Border.all(color: VetColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.domain_rounded, color: VetColors.green),
            const SizedBox(width: 7),
            Expanded(child: Text('${f['company'] ?? '-'} / ${f['farm'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w900))),
            if (n(f['red_alerts']) > 0) _tinyStatus('${n(f['red_alerts'])} RED', false),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _fact(_rt(context, 'Sensors', 'حساسات', 'Sensoren'), '${n(f['sensors_total'])}'),
            _fact(_rt(context, 'Online', 'متصل', 'Online'), '${n(f['sensors_online'])}'),
            _fact(_rt(context, 'Body temp', 'حرارة الجسم', 'Lichaamstemp.'), value(f['avg_body_temperature_c'], decimals: 1, suffix: '°C')),
            _fact(_rt(context, 'Ambient', 'حرارة الجو', 'Omgeving'), value(f['avg_ambient_temperature_c'], decimals: 1, suffix: '°C')),
            _fact(_rt(context, 'Alerts', 'إنذارات', 'Alarmen'), '${n(f['alerts'])}'),
            _fact(_rt(context, 'AI analyses', 'تحليلات AI', 'AI-analyses'), '${n(f['ai_assessments'])}'),
            _fact(_rt(context, 'Urgent vet', 'طبيب عاجل', 'Spoed dierenarts'), '${n(f['urgent_vet_review'])}'),
          ]),
        ]),
      );

  Widget _fact(String label, String valueText) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(color: VetColors.surface3, borderRadius: BorderRadius.circular(9)),
        child: Text('$label: $valueText', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
      );

  Widget _aiSummary(BuildContext context, Map<String, dynamic> s, int coverage) =>
      LayoutBuilder(builder: (context, c) {
        final columns = c.maxWidth >= 780 ? 4 : 2;
        const gap = 9.0;
        final width = (c.maxWidth - gap * (columns - 1)) / columns;
        final items = <(String, String)>[
          (_rt(context, 'AI coverage', 'تغطية AI', 'AI-dekking'), '$coverage%'),
          (_rt(context, 'Urgent vet', 'مراجعة عاجلة', 'Spoed dierenarts'), '${n(s['urgent_vet_review'])}'),
          (_rt(context, 'Isolation advised', 'عزل موصى به', 'Isolatie geadviseerd'), '${n(s['isolation_recommended'])}'),
          (_rt(context, 'Lab confirmation', 'تأكيد معملي', 'Labbevestiging'), '${n(s['lab_confirmation_required'])}'),
        ];
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final item in items)
            SizedBox(width: width, child: Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(color: VetColors.surface2, borderRadius: BorderRadius.circular(12), border: Border.all(color: VetColors.border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.$2, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(item.$1, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: VetColors.muted, fontSize: 10.5, fontWeight: FontWeight.w700)),
              ]),
            )),
        ]);
      });

  Widget _subPanel(BuildContext context, String title, List<Widget> children) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: VetColors.surface2, borderRadius: BorderRadius.circular(14), border: Border.all(color: VetColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          ...children,
        ]),
      );

  Widget _countRow(String label, int count) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Text('$count', style: const TextStyle(fontWeight: FontWeight.w900)),
        ]),
      );

  Widget _riskRow(BuildContext context, String risk, int count) {
    final red = risk == 'red';
    final orange = risk == 'orange';
    final color = red ? VetColors.red : orange ? VetColors.history : VetColors.blue;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 7),
        Expanded(child: Text(risk)),
        Text('$count', style: TextStyle(fontWeight: FontWeight.w900, color: color)),
      ]),
    );
  }

  Widget _qualityCard(BuildContext context, Map<String, dynamic> row) {
    final samples = n(row['samples']);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: VetColors.surface2, borderRadius: BorderRadius.circular(13), border: Border.all(color: VetColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${row['metric'] ?? '-'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
        const SizedBox(height: 7),
        Row(children: [
          Expanded(child: Text('${_rt(context, 'Samples', 'عينات', 'Monsters')}: $samples', style: const TextStyle(fontSize: 11))),
          Icon(samples > 0 ? Icons.verified_rounded : Icons.hourglass_empty_rounded, size: 17, color: samples > 0 ? VetColors.green : VetColors.history),
        ]),
        const SizedBox(height: 5),
        Text('${_rt(context, 'Avg', 'متوسط', 'Gem.')}: ${value(row['avg'], decimals: 2)}  •  ${_rt(context, 'Min', 'أقل', 'Min')}: ${value(row['min'], decimals: 2)}  •  ${_rt(context, 'Max', 'أعلى', 'Max')}: ${value(row['max'], decimals: 2)}', style: const TextStyle(color: VetColors.muted, fontSize: 10.5)),
      ]),
    );
  }

  Widget _dailyRow(BuildContext context, Map<String, dynamic> row) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            SizedBox(width: 92, child: Text('${row['date'] ?? ''}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800))),
            Expanded(child: Wrap(spacing: 8, runSpacing: 5, children: [
              Text('${_rt(context, 'Alerts', 'إنذارات', 'Alarmen')} ${n(row['alerts'])}', style: const TextStyle(fontSize: 11)),
              Text('AI ${n(row['ai_assessments'])}', style: const TextStyle(fontSize: 11)),
              Text('${_rt(context, 'Assessments', 'تحليلات', 'Beoordelingen')} ${n(row['assessments'])}', style: const TextStyle(fontSize: 11)),
              Text('${_rt(context, 'Readings', 'قراءات', 'Metingen')} ${n(row['sensor_readings'])}', style: const TextStyle(fontSize: 11)),
            ])),
          ]),
          const Divider(height: 12),
        ]),
      );

  Widget _empty(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(_rt(context, 'No production data in this period.', 'لا توجد بيانات إنتاج حقيقية في هذه الفترة.', 'Geen productiegegevens in deze periode.'), style: const TextStyle(color: VetColors.muted)),
      );
}

class _IntelMetric {
  const _IntelMetric(this.icon, this.label, this.value, this.color);
  final IconData icon;
  final String label;
  final String value;
  final Color color;
}

class _IntelMetricCard extends StatelessWidget {
  const _IntelMetricCard(this.metric);
  final _IntelMetric metric;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 32, height: 32, decoration: BoxDecoration(color: metric.color.withValues(alpha: .11), borderRadius: BorderRadius.circular(9)), child: Icon(metric.icon, size: 18, color: metric.color)),
              const Spacer(),
            ]),
            const SizedBox(height: 8),
            FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(metric.value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
            const SizedBox(height: 2),
            Text(metric.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: VetColors.muted, fontSize: 10.5, fontWeight: FontWeight.w700)),
          ]),
        ),
      );
}

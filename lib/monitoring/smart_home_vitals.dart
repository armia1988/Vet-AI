import 'package:flutter/material.dart';

import '../services/vet_backend.dart';
import '../theme/app_theme.dart';

typedef VetHomeTranslate = String Function(String en, String ar, String nl);

class SmartHomeVitals extends StatefulWidget {
  const SmartHomeVitals({super.key, required this.farmId, required this.translate});
  final String farmId;
  final VetHomeTranslate translate;

  @override
  State<SmartHomeVitals> createState() => _SmartHomeVitalsState();
}

class _SmartHomeVitalsState extends State<SmartHomeVitals> {
  late Future<_MonitoringSnapshot> future;

  @override
  void initState() {
    super.initState();
    future = _load();
  }

  Future<_MonitoringSnapshot> _load() async {
    final results = await Future.wait([
      VetBackend.instance.sensorDevices(widget.farmId),
      VetBackend.instance.latestSensorReadings(widget.farmId),
    ]).timeout(const Duration(seconds: 12));
    return _MonitoringSnapshot(
      devices: results[0],
      readings: results[1],
    );
  }

  Future<void> _refresh() async {
    setState(() => future = _load());
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_MonitoringSnapshot>(
      future: future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: VetColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(color: VetColors.softPurple, borderRadius: BorderRadius.circular(14)),
                      child: const Icon(Icons.monitor_heart_rounded, color: VetColors.purple, size: 29),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.translate('Live animal & barn indicators', 'مؤشرات الحيوان والعنبر المباشرة', 'Live dier- en stalindicatoren'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 3),
                          Text(widget.translate('Real connected sensors only', 'قراءات من حساسات حقيقية متوصلة بس', 'Alleen echte gekoppelde sensoren'), style: const TextStyle(color: VetColors.muted, fontSize: 12.5)),
                        ],
                      ),
                    ),
                    IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded, color: VetColors.blue)),
                  ],
                ),
                const SizedBox(height: 16),
                if (snapshot.connectionState != ConnectionState.done)
                  const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
                if (snapshot.connectionState == ConnectionState.done && snapshot.hasError)
                  _EmptyState(
                    icon: Icons.cloud_off_rounded,
                    title: widget.translate('Monitoring data could not be loaded', 'تعذر تحميل بيانات المراقبة', 'Monitoringgegevens konden niet worden geladen'),
                    text: widget.translate('Vet AI stopped waiting after the request timeout. Use the refresh button to try again.', 'Vet AI وقف الانتظار بعد مهلة الطلب. استخدم زر التحديث وجرّب تاني.', 'Vet AI is na de aanvraagtime-out gestopt met wachten. Gebruik vernieuwen om opnieuw te proberen.'),
                  ),
                if (snapshot.connectionState == ConnectionState.done && !snapshot.hasError && data != null && data.devices.isEmpty)
                  _EmptyState(
                    icon: Icons.sensors_off_rounded,
                    title: widget.translate('No monitoring device connected yet', 'لسه مفيش جهاز مراقبة متوصل', 'Nog geen monitoringapparaat gekoppeld'),
                    text: widget.translate('This section will stay empty until a real Vet AI sensor device is provisioned.', 'القسم ده هيفضل فاضي لحد ما يتربط حساس Vet AI حقيقي. مش هنحط أرقام تجريبية.', 'Dit gedeelte blijft leeg totdat een echt Vet AI-sensorapparaat is ingericht.'),
                  ),
                if (snapshot.connectionState == ConnectionState.done && !snapshot.hasError && data != null && data.devices.isNotEmpty && data.readings.isEmpty)
                  _EmptyState(
                    icon: Icons.schedule_rounded,
                    title: widget.translate('Sensor connected — waiting for first reading', 'الحساس متوصل — مستنيين أول قراءة', 'Sensor gekoppeld — wachten op eerste meting'),
                    text: widget.translate('No fake values are shown while the device has not reported data.', 'مش هنعرض أي قيم وهمية قبل ما الجهاز يبعت بيانات فعلية.', 'Er worden geen nepwaarden getoond zolang het apparaat nog geen gegevens heeft gestuurd.'),
                  ),
                if (snapshot.connectionState == ConnectionState.done && !snapshot.hasError && data != null && data.readings.isNotEmpty)
                  _LiveContent(reading: data.readings.first, translate: widget.translate),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LiveContent extends StatelessWidget {
  const _LiveContent({required this.reading, required this.translate});
  final Map<String, dynamic> reading;
  final VetHomeTranslate translate;

  double? _n(String key) => (reading[key] as num?)?.toDouble();
  int? _i(String key) => (reading[key] as num?)?.toInt();

  String _num(double? value, {int decimals = 1}) => value == null ? '—' : value.toStringAsFixed(decimals);
  String _integer(int? value) => value == null ? '—' : value.toString();

  @override
  Widget build(BuildContext context) {
    final recordedAt = DateTime.tryParse(reading['recorded_at']?.toString() ?? '');
    final local = recordedAt?.toLocal();
    final lastUpdate = local == null
        ? translate('Unknown update time', 'وقت آخر تحديث غير معروف', 'Onbekende update-tijd')
        : '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _MetricTile(icon: Icons.thermostat_rounded, color: VetColors.red, label: translate('Body temp', 'حرارة الجسم', 'Lichaamstemp.'), value: '${_num(_n('body_temperature_c'))} °C'),
            _MetricTile(icon: Icons.device_thermostat_rounded, color: VetColors.orange, label: translate('Barn temp', 'حرارة العنبر', 'Staltemp.'), value: '${_num(_n('ambient_temperature_c'))} °C'),
            _MetricTile(icon: Icons.water_drop_outlined, color: VetColors.blue, label: translate('Humidity', 'الرطوبة', 'Luchtvochtigheid'), value: '${_num(_n('humidity_percent'), decimals: 0)} %'),
            _MetricTile(icon: Icons.directions_run_rounded, color: VetColors.green, label: translate('Activity', 'النشاط', 'Activiteit'), value: _num(_n('activity_index'), decimals: 2)),
          ],
        ),
        const SizedBox(height: 16),
        Text(translate('Behavior & feeding', 'السلوك والأكل', 'Gedrag & voeding'), style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        _BehaviorRow(icon: Icons.restaurant_rounded, color: VetColors.green, label: translate('Feeding', 'الأكل', 'Voeren'), value: '${_num(_n('feeding_minutes'), decimals: 0)} min'),
        _BehaviorRow(icon: Icons.autorenew_rounded, color: VetColors.purple, label: translate('Rumination', 'الاجترار', 'Herkauwen'), value: '${_num(_n('rumination_minutes'), decimals: 0)} min'),
        _BehaviorRow(icon: Icons.bedtime_outlined, color: VetColors.blue, label: translate('Lying/resting', 'الرقاد والراحة', 'Liggen/rusten'), value: '${_num(_n('lying_minutes'), decimals: 0)} min'),
        _BehaviorRow(icon: Icons.directions_walk_rounded, color: VetColors.history, label: translate('Steps', 'الخطوات', 'Stappen'), value: _integer(_i('steps'))),
        _BehaviorRow(icon: Icons.social_distance_rounded, color: VetColors.orange, label: translate('Distance from herd', 'البُعد عن القطيع', 'Afstand tot kudde'), value: '${_num(_n('distance_from_herd_m'))} m'),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: VetColors.softBlue, borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              const Icon(Icons.schedule_rounded, size: 20, color: VetColors.blue),
              const SizedBox(width: 8),
              Expanded(child: Text('${translate('Last sensor update', 'آخر تحديث للحساسات', 'Laatste sensorupdate')}: $lastUpdate', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.icon, required this.color, required this.label, required this.value});
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width - 86) / 2;
    return SizedBox(
      width: width.clamp(135, 190),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: .22))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 27),
            const SizedBox(height: 9),
            Text(value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
            const SizedBox(height: 3),
            Text(label, style: const TextStyle(color: VetColors.muted, fontSize: 12.5, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _BehaviorRow extends StatelessWidget {
  const _BehaviorRow({required this.icon, required this.color, required this.label, required this.value});
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Container(width: 36, height: 36, decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color, size: 21)),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: VetColors.surface2, borderRadius: BorderRadius.circular(16)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: VetColors.purple, size: 31),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(text, style: const TextStyle(color: VetColors.muted, height: 1.4)),
            ])),
          ],
        ),
      );
}

class _MonitoringSnapshot {
  const _MonitoringSnapshot({required this.devices, required this.readings});
  final List<Map<String, dynamic>> devices;
  final List<Map<String, dynamic>> readings;
}

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
  void initState() { super.initState(); future = _load(); }
  Future<_MonitoringSnapshot> _load() async {
    final r = await Future.wait([
      VetBackend.instance.sensorDevices(widget.farmId),
      VetBackend.instance.latestSensorReadings(widget.farmId),
    ]).timeout(const Duration(seconds: 12));
    return _MonitoringSnapshot(devices: r[0], readings: r[1]);
  }
  Future<void> _refresh() async { setState(() => future = _load()); try { await future; } catch (_) {} }

  @override
  Widget build(BuildContext context) => FutureBuilder<_MonitoringSnapshot>(
        future: future,
        builder: (context, snapshot) {
          final data = snapshot.data;
          return Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: VetColors.border)),
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 48, height: 48, decoration: BoxDecoration(color: VetColors.softPurple, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.sensors_rounded, color: VetColors.purple, size: 29)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.translate('Vet AI hardware monitoring', 'مراقبة هاردوير Vet AI', 'Vet AI-hardwaremonitoring'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 3),
                  Text(widget.translate('ESP32-C3 + real purchased sensors', 'ESP32-C3 + الحساسات الحقيقية المشتراة', 'ESP32-C3 + echte aangeschafte sensoren'), style: const TextStyle(color: VetColors.muted, fontSize: 12.5)),
                ])),
                IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded, color: VetColors.blue)),
              ]),
              const SizedBox(height: 15),
              if (snapshot.connectionState != ConnectionState.done) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
              if (snapshot.connectionState == ConnectionState.done && snapshot.hasError)
                _EmptyState(icon: Icons.cloud_off_rounded, title: widget.translate('Monitoring data could not be loaded', 'تعذر تحميل بيانات المراقبة', 'Monitoringgegevens konden niet worden geladen'), text: widget.translate('Use refresh to retry.', 'استخدم زر التحديث وحاول مرة أخرى.', 'Gebruik vernieuwen om opnieuw te proberen.')),
              if (snapshot.connectionState == ConnectionState.done && !snapshot.hasError && data != null) ...[
                _HardwareStatus(devices: data.devices, translate: widget.translate),
                const SizedBox(height: 14),
                if (data.devices.isEmpty)
                  _EmptyState(icon: Icons.sensors_off_rounded, title: widget.translate('No ESP32-C3 device provisioned yet', 'لسه مفيش ESP32-C3 متربط', 'Nog geen ESP32-C3 ingericht'), text: widget.translate('No fake values are shown. Pair the real controller first.', 'مش هنعرض أرقام وهمية. اربط وحدة التحكم الحقيقية الأول.', 'Er worden geen nepwaarden getoond. Koppel eerst de echte controller.'))
                else if (data.readings.isEmpty)
                  _EmptyState(icon: Icons.schedule_rounded, title: widget.translate('Controller connected — waiting for readings', 'وحدة التحكم متوصلة — مستنيين القراءات', 'Controller gekoppeld — wachten op metingen'), text: widget.translate('The dashboard appears only after real sensor data reaches the backend.', 'اللوحة هتظهر بعد وصول قراءة حقيقية للسيرفر.', 'Het dashboard verschijnt pas nadat echte sensordata de backend bereikt.'))
                else
                  _LiveContent(reading: data.readings.first, translate: widget.translate),
              ],
            ]),
          );
        },
      );
}

class _HardwareStatus extends StatelessWidget {
  const _HardwareStatus({required this.devices, required this.translate});
  final List<Map<String, dynamic>> devices;
  final VetHomeTranslate translate;
  @override
  Widget build(BuildContext context) {
    if (devices.isEmpty) return const SizedBox.shrink();
    final d = devices.first;
    final models = (d['sensor_models'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
    final last = DateTime.tryParse(d['last_seen_at']?.toString() ?? '')?.toLocal();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: VetColors.surface2, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.memory_rounded, color: VetColors.green),
          const SizedBox(width: 8),
          Expanded(child: Text('${d['controller_model'] ?? 'ESP32-C3 SuperMini'} • ${d['device_uid'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w900))),
          Container(width: 9, height: 9, decoration: const BoxDecoration(shape: BoxShape.circle, color: VetColors.green)),
        ]),
        if (models.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: models.map((m) => Chip(label: Text(m, style: const TextStyle(fontSize: 11.5)))).toList()),
        ],
        const SizedBox(height: 6),
        Text(last == null ? translate('No heartbeat yet', 'لسه مفيش اتصال حديث', 'Nog geen recente heartbeat') : '${translate('Last seen', 'آخر اتصال', 'Laatst gezien')}: ${last.hour.toString().padLeft(2, '0')}:${last.minute.toString().padLeft(2, '0')}', style: const TextStyle(color: VetColors.muted, fontSize: 12)),
      ]),
    );
  }
}

class _LiveContent extends StatelessWidget {
  const _LiveContent({required this.reading, required this.translate});
  final Map<String, dynamic> reading;
  final VetHomeTranslate translate;
  double? _n(String key) => (reading[key] as num?)?.toDouble();
  int? _i(String key) => (reading[key] as num?)?.toInt();
  String _num(double? v, {int d = 1}) => v == null ? '—' : v.toStringAsFixed(d);
  String _int(int? v) => v == null ? '—' : '$v';

  @override
  Widget build(BuildContext context) {
    final recorded = DateTime.tryParse(reading['recorded_at']?.toString() ?? '')?.toLocal();
    final last = recorded == null ? '—' : '${recorded.hour.toString().padLeft(2, '0')}:${recorded.minute.toString().padLeft(2, '0')}';
    final charging = reading['charging'] == true;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionTitle(icon: Icons.home_work_outlined, text: translate('Barn environment', 'بيئة العنبر', 'Stalomgeving')),
      const SizedBox(height: 9),
      Wrap(spacing: 9, runSpacing: 9, children: [
        _MetricTile(icon: Icons.device_thermostat_rounded, color: VetColors.orange, label: translate('Barn temperature • SHT40', 'حرارة العنبر • SHT40', 'Staltemperatuur • SHT40'), value: '${_num(_n('ambient_temperature_c'))} °C'),
        _MetricTile(icon: Icons.water_drop_outlined, color: VetColors.blue, label: translate('Relative humidity • SHT40', 'الرطوبة النسبية • SHT40', 'Relatieve vochtigheid • SHT40'), value: '${_num(_n('humidity_percent'), d: 0)} %RH'),
        _MetricTile(icon: Icons.air_rounded, color: VetColors.blue, label: translate('Oxygen • SC4-O2', 'الأكسجين • SC4-O2', 'Zuurstof • SC4-O2'), value: '${_num(_n('oxygen_percent'))} %O₂'),
        _MetricTile(icon: Icons.electric_bolt_rounded, color: VetColors.orange, label: translate('Power current • SCT-013', 'تيار الطاقة • SCT-013', 'Stroom • SCT-013'), value: '${_num(_n('current_amp'), d: 2)} A'),
      ]),
      const SizedBox(height: 17),
      _SectionTitle(icon: Icons.battery_charging_full_rounded, text: translate('Controller power', 'طاقة وحدة التحكم', 'Controller-voeding')),
      const SizedBox(height: 9),
      Wrap(spacing: 9, runSpacing: 9, children: [
        _MetricTile(icon: charging ? Icons.battery_charging_full_rounded : Icons.battery_4_bar_rounded, color: VetColors.green, label: translate('Battery estimate', 'تقدير البطارية', 'Batterijschatting'), value: '${_num(_n('battery_percent'), d: 0)} %'),
        _MetricTile(icon: Icons.bolt_rounded, color: VetColors.green, label: translate('Battery voltage', 'جهد البطارية', 'Batterijspanning'), value: '${_num(_n('battery_voltage_v'), d: 2)} V'),
      ]),
      const SizedBox(height: 17),
      _SectionTitle(icon: Icons.directions_run_rounded, text: translate('Wearable motion • MPU6050', 'حركة الحيوان • MPU6050', 'Draagbare beweging • MPU6050')),
      const SizedBox(height: 9),
      Wrap(spacing: 9, runSpacing: 9, children: [
        _MetricTile(icon: Icons.threed_rotation_rounded, color: VetColors.purple, label: 'X / Y / Z', value: '${_num(_n('accel_x_g'), d: 2)} / ${_num(_n('accel_y_g'), d: 2)} / ${_num(_n('accel_z_g'), d: 2)} g'),
        _MetricTile(icon: Icons.speed_rounded, color: VetColors.green, label: translate('Activity index', 'مؤشر النشاط', 'Activiteitsindex'), value: _num(_n('activity_index'), d: 3)),
        _MetricTile(icon: Icons.directions_walk_rounded, color: VetColors.history, label: translate('Steps', 'الخطوات', 'Stappen'), value: _int(_i('steps'))),
      ]),
      const SizedBox(height: 14),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: VetColors.softPurple, borderRadius: BorderRadius.circular(14)),
        child: Text(translate('Feeding, rumination and resting below are derived from movement patterns, not direct sensor channels. They must be calibrated for species, collar position and farm behavior before clinical use.', 'الأكل والاجترار والرقاد تحت قيم مشتقة من أنماط الحركة، وليست قنوات قياس مباشرة. لازم تتعاير حسب نوع الحيوان ومكان تركيب الجهاز وسلوك المزرعة قبل الاعتماد البيطري.', 'Voeren, herkauwen en rust hieronder zijn afgeleid uit bewegingspatronen en geen directe sensorkanalen. Ze moeten worden gekalibreerd voor soort, montagepositie en bedrijfsvoering.'), style: const TextStyle(height: 1.45, fontWeight: FontWeight.w700)),
      ),
      const SizedBox(height: 9),
      _BehaviorRow(icon: Icons.restaurant_rounded, color: VetColors.green, label: translate('Feeding estimate', 'تقدير الأكل', 'Voerinschatting'), value: '${_num(_n('feeding_minutes'), d: 0)} min'),
      _BehaviorRow(icon: Icons.autorenew_rounded, color: VetColors.purple, label: translate('Rumination estimate', 'تقدير الاجترار', 'Herkauwinschatting'), value: '${_num(_n('rumination_minutes'), d: 0)} min'),
      _BehaviorRow(icon: Icons.bedtime_outlined, color: VetColors.blue, label: translate('Lying/rest estimate', 'تقدير الرقاد/الراحة', 'Lig-/rustinschatting'), value: '${_num(_n('lying_minutes'), d: 0)} min'),
      const SizedBox(height: 11),
      Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(color: VetColors.softBlue, borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.schedule_rounded, size: 20, color: VetColors.blue), const SizedBox(width: 8), Expanded(child: Text('${translate('Last real reading', 'آخر قراءة حقيقية', 'Laatste echte meting')}: $last', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)))])),
    ]);
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.text});
  final IconData icon; final String text;
  @override
  Widget build(BuildContext context) => Row(children: [Icon(icon, size: 21, color: VetColors.primary), const SizedBox(width: 7), Text(text, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900))]);
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.icon, required this.color, required this.label, required this.value});
  final IconData icon; final Color color; final String label; final String value;
  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width - 86) / 2;
    return SizedBox(width: width.clamp(135, 195), child: Container(padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: .2))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: color, size: 26), const SizedBox(height: 8), Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)), const SizedBox(height: 3), Text(label, style: const TextStyle(color: VetColors.muted, fontSize: 11.8, fontWeight: FontWeight.w700))])));
  }
}

class _BehaviorRow extends StatelessWidget {
  const _BehaviorRow({required this.icon, required this.color, required this.label, required this.value});
  final IconData icon; final Color color; final String label; final String value;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [Container(width: 36, height: 36, decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color, size: 21)), const SizedBox(width: 10), Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))), Text(value, style: const TextStyle(fontWeight: FontWeight.w900))]));
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.text});
  final IconData icon; final String title; final String text;
  @override
  Widget build(BuildContext context) => Container(width: double.infinity, padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: VetColors.surface2, borderRadius: BorderRadius.circular(16)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: VetColors.purple, size: 31), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(text, style: const TextStyle(color: VetColors.muted, height: 1.4))]))]));
}

class _MonitoringSnapshot {
  const _MonitoringSnapshot({required this.devices, required this.readings});
  final List<Map<String, dynamic>> devices; final List<Map<String, dynamic>> readings;
}

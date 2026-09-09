import 'package:flutter/material.dart';

import '../i18n/vet_locale.dart';
import '../theme/app_theme.dart';
import 'admin_service.dart';

String _al(BuildContext context, String en, String ar, String nl) =>
    VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

class VetAdminAlertCenter extends StatefulWidget {
  const VetAdminAlertCenter({super.key});

  @override
  State<VetAdminAlertCenter> createState() => _VetAdminAlertCenterState();
}

class _VetAdminAlertCenterState extends State<VetAdminAlertCenter> {
  final admin = VetAdminService.instance;
  final search = TextEditingController();
  String risk = 'all';
  String status = 'all';
  late Future<_AlertData> future = _load();

  Future<_AlertData> _load() async {
    final values = await Future.wait([admin.alerts(), admin.farms(), admin.animals()]);
    return _AlertData(alerts: values[0], farms: values[1], animals: values[2]);
  }

  void reload() => setState(() => future = _load());

  Future<void> _changeStatus(Map<String, dynamic> row, String next) async {
    final notes = TextEditingController(text: '${row['admin_notes'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_al(context, 'Update alert status', 'تحديث حالة الإنذار', 'Alarmstatus bijwerken')),
        content: SizedBox(
          width: 540,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Align(alignment: AlignmentDirectional.centerStart, child: Text('${row['title'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w900))),
            const SizedBox(height: 12),
            TextField(controller: notes, minLines: 3, maxLines: 7, decoration: InputDecoration(labelText: _al(context, 'Admin investigation notes', 'ملاحظات التحقيق الإداري', 'Admin-onderzoeksnotities'))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_al(context, 'Cancel', 'إلغاء', 'Annuleren'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_al(context, 'Save', 'حفظ', 'Opslaan'))),
        ],
      ),
    );
    if (ok != true) return;
    await admin.client.rpc('admin_set_alert_status', params: {
      'p_alert_id': row['id'].toString(),
      'p_status': next,
      'p_notes': notes.text.trim(),
    });
    reload();
  }

  Future<void> _notifyOwner(Map<String, dynamic> row) async {
    final severity = ['orange', 'red'].contains('${row['risk']}') ? '${row['risk']}' : 'info';
    final title = TextEditingController(text: '${row['title'] ?? 'Vet AI alert'}');
    final body = TextEditingController(text: '${row['details'] ?? row['threshold_text'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_al(context, 'Notify farm owner', 'إشعار صاحب المزرعة', 'Boerderijeigenaar melden')),
        content: SizedBox(width: 560, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, decoration: InputDecoration(labelText: _al(context, 'Title', 'العنوان', 'Titel'))),
          const SizedBox(height: 10),
          TextField(controller: body, minLines: 3, maxLines: 7, decoration: InputDecoration(labelText: _al(context, 'Message', 'الرسالة', 'Bericht'))),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_al(context, 'Cancel', 'إلغاء', 'Annuleren'))),
          FilledButton.icon(onPressed: () => Navigator.pop(dialogContext, true), icon: const Icon(Icons.send_rounded), label: Text(_al(context, 'Send push', 'إرسال إشعار', 'Push versturen'))),
        ],
      ),
    );
    if (ok != true || title.text.trim().isEmpty || body.text.trim().isEmpty) return;
    await admin.sendNotification(
      targetScope: 'farm',
      farmId: row['farm_id'].toString(),
      title: title.text.trim(),
      body: body.text.trim(),
      severity: severity,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_al(context, 'Notification sent.', 'تم إرسال الإشعار.', 'Melding verzonden.'))));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_AlertData>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('${snapshot.error}', style: const TextStyle(color: VetColors.red)));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!;
          final farms = {for (final f in data.farms) f['id'].toString(): f};
          final animals = {for (final a in data.animals) a['id'].toString(): a};
          final needle = search.text.trim().toLowerCase();
          final rows = data.alerts.where((row) {
            if (risk != 'all' && '${row['risk']}' != risk) return false;
            final rowStatus = '${row['admin_status'] ?? (row['acknowledged_at'] == null ? 'open' : 'acknowledged')}';
            if (status != 'all' && rowStatus != status) return false;
            if (needle.isEmpty) return true;
            final farm = farms[row['farm_id'].toString()];
            final animal = animals[row['animal_id']?.toString()];
            final hay = '${row['title']} ${row['details']} ${row['source']} ${row['metric']} ${farm?['company_name']} ${farm?['farm_name']} ${animal?['name']} ${animal?['external_id']}'.toLowerCase();
            return hay.contains(needle);
          }).toList();
          final open = data.alerts.where((e) => '${e['admin_status'] ?? 'open'}' == 'open').length;
          final red = data.alerts.where((e) => '${e['risk']}' == 'red').length;
          final orange = data.alerts.where((e) => '${e['risk']}' == 'orange').length;
          final resolved = data.alerts.where((e) => '${e['admin_status']}' == 'resolved').length;

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(_al(context, 'Alerts command center', 'مركز قيادة الإنذارات', 'Alarm-commandocentrum'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 5),
              Text(_al(context, 'Investigate every farm alert, acknowledge or resolve it, add internal notes and contact the farm owner directly.', 'راجع كل إنذارات المزارع، واعترف بها أو أغلقها بعد الحل، وأضف ملاحظات داخلية وأرسل لصاحب المزرعة مباشرة.', 'Onderzoek elk boerderijalarm, bevestig of los het op, voeg interne notities toe en meld de eigenaar direct.'), style: const TextStyle(color: VetColors.muted)),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Chip(avatar: const Icon(Icons.warning_amber_rounded, size: 17), label: Text('$open ${_al(context, 'open', 'مفتوح', 'open')}')),
                Chip(avatar: const Icon(Icons.crisis_alert_rounded, size: 17, color: VetColors.red), label: Text('$red ${_al(context, 'red', 'أحمر', 'rood')}')),
                Chip(avatar: const Icon(Icons.warning_rounded, size: 17, color: VetColors.history), label: Text('$orange ${_al(context, 'orange', 'برتقالي', 'oranje')}')),
                Chip(avatar: const Icon(Icons.task_alt_rounded, size: 17, color: VetColors.green), label: Text('$resolved ${_al(context, 'resolved', 'تم حله', 'opgelost')}')),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 10, runSpacing: 10, children: [
                SizedBox(width: 420, child: TextField(controller: search, onChanged: (_) => setState(() {}), decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: _al(context, 'Search alert, company, animal or metric', 'ابحث بالإنذار أو الشركة أو الحيوان أو المؤشر', 'Zoek alarm, bedrijf, dier of metriek')))),
                SizedBox(width: 170, child: DropdownButtonFormField<String>(initialValue: risk, decoration: InputDecoration(labelText: _al(context, 'Risk', 'الخطورة', 'Risico')), items: const [DropdownMenuItem(value: 'all', child: Text('All')), DropdownMenuItem(value: 'red', child: Text('Red')), DropdownMenuItem(value: 'orange', child: Text('Orange')), DropdownMenuItem(value: 'yellow', child: Text('Yellow')), DropdownMenuItem(value: 'none', child: Text('None'))], onChanged: (v) => setState(() => risk = v ?? 'all'))),
                SizedBox(width: 190, child: DropdownButtonFormField<String>(initialValue: status, decoration: InputDecoration(labelText: _al(context, 'Case status', 'حالة الإنذار', 'Casestatus')), items: const [DropdownMenuItem(value: 'all', child: Text('All')), DropdownMenuItem(value: 'open', child: Text('Open')), DropdownMenuItem(value: 'acknowledged', child: Text('Acknowledged')), DropdownMenuItem(value: 'resolved', child: Text('Resolved')), DropdownMenuItem(value: 'hidden', child: Text('Hidden'))], onChanged: (v) => setState(() => status = v ?? 'all'))),
                IconButton.filledTonal(onPressed: reload, icon: const Icon(Icons.refresh_rounded)),
              ]),
              const SizedBox(height: 14),
              for (final row in rows)
                _AlertCard(
                  row: row,
                  farm: farms[row['farm_id'].toString()],
                  animal: animals[row['animal_id']?.toString()],
                  onStatus: (v) => _changeStatus(row, v),
                  onNotify: () => _notifyOwner(row),
                ),
              if (rows.isEmpty) Padding(padding: const EdgeInsets.all(38), child: Center(child: Text(_al(context, 'No alerts match these filters.', 'لا توجد إنذارات مطابقة للفلاتر.', 'Geen alarmen passen bij deze filters.')))),
            ],
          );
        },
      );
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.row, required this.farm, required this.animal, required this.onStatus, required this.onNotify});
  final Map<String, dynamic> row;
  final Map<String, dynamic>? farm;
  final Map<String, dynamic>? animal;
  final ValueChanged<String> onStatus;
  final VoidCallback onNotify;

  @override
  Widget build(BuildContext context) {
    final rowRisk = '${row['risk'] ?? 'none'}';
    final rowStatus = '${row['admin_status'] ?? (row['acknowledged_at'] == null ? 'open' : 'acknowledged')}';
    final riskColor = rowRisk == 'red' ? VetColors.red : rowRisk == 'orange' ? VetColors.history : rowRisk == 'yellow' ? VetColors.history : VetColors.muted;
    return Card(
      margin: const EdgeInsets.only(bottom: 11),
      child: ExpansionTile(
        leading: CircleAvatar(backgroundColor: riskColor.withValues(alpha: .12), child: Icon(rowRisk == 'red' ? Icons.crisis_alert_rounded : Icons.warning_amber_rounded, color: riskColor)),
        title: Text('${row['title'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text('${farm?['company_name'] ?? ''} / ${farm?['farm_name'] ?? row['farm_id']} • ${animal?['name'] ?? animal?['external_id'] ?? '-'}\n${rowRisk.toUpperCase()} • $rowStatus • ${row['created_at'] ?? ''}'),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        children: [
          Align(alignment: AlignmentDirectional.centerStart, child: Text('${row['details'] ?? ''}')),
          const SizedBox(height: 8),
          Align(alignment: AlignmentDirectional.centerStart, child: Wrap(spacing: 8, runSpacing: 8, children: [
            Chip(label: Text('${_al(context, 'Source', 'المصدر', 'Bron')}: ${row['source'] ?? '-'}')),
            Chip(label: Text('${_al(context, 'Metric', 'المؤشر', 'Metriek')}: ${row['metric'] ?? '-'}')),
            Chip(label: Text('${_al(context, 'Value', 'القراءة', 'Waarde')}: ${row['value_numeric'] ?? '-'}')),
            if ('${row['threshold_text'] ?? ''}'.isNotEmpty) Chip(label: Text('${_al(context, 'Threshold', 'الحد', 'Drempel')}: ${row['threshold_text']}')),
          ])),
          if ('${row['admin_notes'] ?? ''}'.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Align(alignment: AlignmentDirectional.centerStart, child: Text('${_al(context, 'Admin notes', 'ملاحظات الإدارة', 'Adminnotities')}: ${row['admin_notes']}', style: const TextStyle(color: VetColors.muted))),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(onPressed: onNotify, icon: const Icon(Icons.notifications_active_rounded), label: Text(_al(context, 'Notify owner', 'إشعار صاحب المزرعة', 'Eigenaar melden'))),
              PopupMenuButton<String>(
                onSelected: onStatus,
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'open', child: Text(_al(context, 'Reopen', 'إعادة فتح', 'Heropenen'))),
                  PopupMenuItem(value: 'acknowledged', child: Text(_al(context, 'Acknowledge', 'تمت المراجعة', 'Bevestigen'))),
                  PopupMenuItem(value: 'resolved', child: Text(_al(context, 'Resolve', 'تم الحل', 'Oplossen'))),
                  PopupMenuItem(value: 'hidden', child: Text(_al(context, 'Hide from operations', 'إخفاء من العمليات', 'Verbergen uit operaties'))),
                ],
                child: FilledButton.icon(onPressed: null, icon: const Icon(Icons.manage_history_rounded), label: Text(_al(context, 'Change status', 'تغيير الحالة', 'Status wijzigen'))),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _AlertData {
  const _AlertData({required this.alerts, required this.farms, required this.animals});
  final List<Map<String, dynamic>> alerts;
  final List<Map<String, dynamic>> farms;
  final List<Map<String, dynamic>> animals;
}

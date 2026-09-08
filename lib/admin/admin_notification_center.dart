import 'package:flutter/material.dart';

import '../i18n/vet_locale.dart';
import '../theme/app_theme.dart';
import 'admin_service.dart';

String _nt(BuildContext context, String en, String ar, String nl) =>
    VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

class VetAdminNotificationCenter extends StatefulWidget {
  const VetAdminNotificationCenter({super.key});

  @override
  State<VetAdminNotificationCenter> createState() => _VetAdminNotificationCenterState();
}

class _VetAdminNotificationCenterState extends State<VetAdminNotificationCenter> {
  final admin = VetAdminService.instance;
  late Future<_NotificationCenterData> future = _load();

  Future<_NotificationCenterData> _load() async {
    final values = await Future.wait([
      admin.notifications(),
      admin.farms(),
      admin.profiles(),
      admin.pushDevices(),
    ]);
    return _NotificationCenterData(
      notifications: values[0],
      farms: values[1],
      profiles: values[2],
      devices: values[3],
    );
  }

  void reload() => setState(() => future = _load());

  Future<void> _compose(_NotificationCenterData data) async {
    final title = TextEditingController();
    final body = TextEditingController();
    String scope = 'all';
    String severity = 'info';
    String? farmId;
    String? userId;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(_nt(context, 'Send push notification', 'إرسال إشعار Push', 'Pushmelding versturen')),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  initialValue: scope,
                  decoration: InputDecoration(labelText: _nt(context, 'Recipients', 'المستلمون', 'Ontvangers')),
                  items: [
                    DropdownMenuItem(value: 'all', child: Text(_nt(context, 'All registered customers', 'كل العملاء المسجلين', 'Alle geregistreerde klanten'))),
                    DropdownMenuItem(value: 'farm', child: Text(_nt(context, 'One company / farm', 'شركة / مزرعة واحدة', 'Eén bedrijf / boerderij'))),
                    DropdownMenuItem(value: 'user', child: Text(_nt(context, 'One customer', 'عميل واحد', 'Eén klant'))),
                  ],
                  onChanged: (value) => setLocal(() {
                    scope = value ?? 'all';
                    farmId = null;
                    userId = null;
                  }),
                ),
                if (scope == 'farm') ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: farmId,
                    decoration: InputDecoration(labelText: _nt(context, 'Company / farm', 'الشركة / المزرعة', 'Bedrijf / boerderij')),
                    items: [
                      for (final farm in data.farms)
                        DropdownMenuItem(value: farm['id'].toString(), child: Text('${farm['company_name'] ?? ''} / ${farm['farm_name'] ?? ''}')),
                    ],
                    onChanged: (value) => setLocal(() => farmId = value),
                  ),
                ],
                if (scope == 'user') ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: userId,
                    decoration: InputDecoration(labelText: _nt(context, 'Customer', 'العميل', 'Klant')),
                    items: [
                      for (final profile in data.profiles)
                        DropdownMenuItem(value: profile['id'].toString(), child: Text('${profile['full_name'] ?? profile['id']}')),
                    ],
                    onChanged: (value) => setLocal(() => userId = value),
                  ),
                ],
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: severity,
                  decoration: InputDecoration(labelText: _nt(context, 'Notification type / sound', 'نوع الإشعار / الصوت', 'Meldingstype / geluid')),
                  items: [
                    DropdownMenuItem(value: 'info', child: Text(_nt(context, 'Normal notification', 'إشعار عادي', 'Normale melding'))),
                    DropdownMenuItem(value: 'orange', child: Text(_nt(context, 'Orange warning sound', 'صوت التحذير البرتقالي', 'Oranje waarschuwingsgeluid'))),
                    DropdownMenuItem(value: 'red', child: Text(_nt(context, 'Red emergency sound', 'صوت الإنذار الأحمر', 'Rood alarmgeluid'))),
                  ],
                  onChanged: (value) => setLocal(() => severity = value ?? 'info'),
                ),
                const SizedBox(height: 10),
                TextField(controller: title, decoration: InputDecoration(labelText: _nt(context, 'Title', 'العنوان', 'Titel'))),
                const SizedBox(height: 10),
                TextField(controller: body, minLines: 4, maxLines: 8, decoration: InputDecoration(labelText: _nt(context, 'Message', 'الرسالة', 'Bericht'))),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_nt(context, 'Cancel', 'إلغاء', 'Annuleren'))),
            FilledButton.icon(onPressed: () => Navigator.pop(dialogContext, true), icon: const Icon(Icons.send_rounded), label: Text(_nt(context, 'Send now', 'إرسال الآن', 'Nu versturen'))),
          ],
        ),
      ),
    );

    if (ok != true || title.text.trim().isEmpty || body.text.trim().isEmpty) return;
    if (scope == 'farm' && farmId == null) return;
    if (scope == 'user' && userId == null) return;

    await admin.sendNotification(
      targetScope: scope,
      farmId: farmId,
      userId: userId,
      title: title.text,
      body: body.text,
      severity: severity,
    );
    reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_NotificationCenterData>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('${snapshot.error}', style: const TextStyle(color: VetColors.red)));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!;
          return DefaultTabController(
            length: 3,
            child: Column(children: [
              Material(
                color: VetColors.surface2,
                child: TabBar(
                  isScrollable: true,
                  tabs: [
                    Tab(icon: const Icon(Icons.send_rounded), text: _nt(context, 'Send', 'إرسال', 'Versturen')),
                    Tab(icon: const Icon(Icons.history_rounded), text: _nt(context, 'History', 'السجل', 'Geschiedenis')),
                    Tab(icon: const Icon(Icons.devices_rounded), text: _nt(context, 'Customer devices', 'أجهزة العملاء', 'Klantapparaten')),
                  ],
                ),
              ),
              Expanded(child: TabBarView(children: [
                _sendPage(context, data),
                _historyPage(context, data),
                _devicesPage(context, data),
              ])),
            ]),
          );
        },
      );

  Widget _sendPage(BuildContext context, _NotificationCenterData data) {
    final enabledDevices = data.devices.where((e) => e['enabled'] == true).length;
    final farmsWithPush = data.devices.where((e) => e['enabled'] == true).map((e) => e['farm_id']).toSet().length;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: VetColors.surface2, borderRadius: BorderRadius.circular(20), border: Border.all(color: VetColors.green.withValues(alpha: .25))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_nt(context, 'Customer notification command center', 'مركز التحكم في إشعارات العملاء', 'Commandocentrum klantmeldingen'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(_nt(context, 'Send a normal message, orange warning or red emergency alert to every customer, one farm/company or one customer.', 'ابعت رسالة عادية أو تحذير برتقالي أو إنذار أحمر لكل العملاء أو لشركة/مزرعة أو لعميل واحد.', 'Stuur een normale melding, oranje waarschuwing of rood alarm naar alle klanten, één bedrijf/boerderij of één klant.'), style: const TextStyle(color: VetColors.muted, height: 1.45)),
            const SizedBox(height: 18),
            FilledButton.icon(onPressed: () => _compose(data), icon: const Icon(Icons.add_alert_rounded), label: Text(_nt(context, 'Create notification', 'إنشاء إشعار', 'Melding maken'))),
          ]),
        ),
        const SizedBox(height: 18),
        Wrap(spacing: 12, runSpacing: 12, children: [
          _MiniStat(icon: Icons.phone_iphone_rounded, label: _nt(context, 'Enabled devices', 'الأجهزة المفعلة', 'Ingeschakelde apparaten'), value: '$enabledDevices'),
          _MiniStat(icon: Icons.domain_rounded, label: _nt(context, 'Farms with push', 'مزارع مرتبطة بالإشعارات', 'Boerderijen met push'), value: '$farmsWithPush'),
          _MiniStat(icon: Icons.notifications_rounded, label: _nt(context, 'Sent campaigns', 'حملات الإشعارات', 'Verzonden campagnes'), value: '${data.notifications.length}'),
        ]),
      ],
    );
  }

  Widget _historyPage(BuildContext context, _NotificationCenterData data) => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          for (final row in data.notifications)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: '${row['severity']}' == 'red' ? VetColors.red.withValues(alpha: .12) : '${row['severity']}' == 'orange' ? VetColors.history.withValues(alpha: .12) : VetColors.surface3,
                  child: Icon(Icons.notifications_active_rounded, color: '${row['severity']}' == 'red' ? VetColors.red : '${row['severity']}' == 'orange' ? VetColors.history : VetColors.blue),
                ),
                title: Text('${row['title'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w900)),
                subtitle: Text('${row['target_scope']} • ${row['status']} • ${row['severity']}\n${row['sent_count'] ?? 0} sent • ${row['failed_count'] ?? 0} failed\n${row['body'] ?? ''}'),
                isThreeLine: true,
              ),
            ),
          if (data.notifications.isEmpty) Center(child: Padding(padding: const EdgeInsets.all(40), child: Text(_nt(context, 'No notifications sent yet.', 'لم يتم إرسال إشعارات بعد.', 'Nog geen meldingen verstuurd.')))),
        ],
      );

  Widget _devicesPage(BuildContext context, _NotificationCenterData data) {
    final farmNames = {for (final f in data.farms) f['id'].toString(): '${f['company_name'] ?? ''} / ${f['farm_name'] ?? ''}'};
    final customerNames = {for (final p in data.profiles) p['id'].toString(): '${p['full_name'] ?? ''}'};
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        for (final row in data.devices)
          Card(
            child: SwitchListTile(
              value: row['enabled'] == true,
              onChanged: (value) async {
                await admin.setPushDeviceEnabled(row['id'].toString(), value);
                reload();
              },
              secondary: const CircleAvatar(child: Icon(Icons.phone_iphone_rounded)),
              title: Text(customerNames[row['user_id'].toString()]?.trim().isNotEmpty == true ? customerNames[row['user_id'].toString()]! : row['user_id'].toString(), style: const TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text('${farmNames[row['farm_id'].toString()] ?? row['farm_id']}\n${row['platform']} • ${row['environment']} • ${_nt(context, 'Last seen', 'آخر اتصال', 'Laatst gezien')}: ${row['last_seen_at'] ?? '-'}'),
              isThreeLine: true,
            ),
          ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        width: 210,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: VetColors.surface2, borderRadius: BorderRadius.circular(15), border: Border.all(color: VetColors.border)),
        child: Row(children: [
          Icon(icon, color: VetColors.green),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)), Text(label, style: const TextStyle(fontSize: 11, color: VetColors.muted))])),
        ]),
      );
}

class _NotificationCenterData {
  const _NotificationCenterData({required this.notifications, required this.farms, required this.profiles, required this.devices});
  final List<Map<String, dynamic>> notifications;
  final List<Map<String, dynamic>> farms;
  final List<Map<String, dynamic>> profiles;
  final List<Map<String, dynamic>> devices;
}

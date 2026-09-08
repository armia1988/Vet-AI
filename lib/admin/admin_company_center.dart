import 'package:flutter/material.dart';

import '../i18n/vet_locale.dart';
import '../theme/app_theme.dart';
import 'admin_service.dart';

String _ct(BuildContext context, String en, String ar, String nl) =>
    VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

class VetAdminCompanyCenter extends StatefulWidget {
  const VetAdminCompanyCenter({super.key});

  @override
  State<VetAdminCompanyCenter> createState() => _VetAdminCompanyCenterState();
}

class _VetAdminCompanyCenterState extends State<VetAdminCompanyCenter> {
  final admin = VetAdminService.instance;
  late Future<_CompanyData> future = _load();

  Future<_CompanyData> _load() async {
    final values = await Future.wait([
      admin.farms(),
      admin.profiles(),
      admin.sensors(),
      admin.animals(),
      admin.alerts(),
      admin.supportThreads(),
      admin.subscriptions(),
      admin.payments(),
    ]);
    return _CompanyData(
      farms: values[0],
      profiles: values[1],
      sensors: values[2],
      animals: values[3],
      alerts: values[4],
      support: values[5],
      subscriptions: values[6],
      payments: values[7],
    );
  }

  void reload() => setState(() => future = _load());

  Future<void> _editFarm(Map<String, dynamic> farm) async {
    final company = TextEditingController(text: '${farm['company_name'] ?? ''}');
    final name = TextEditingController(text: '${farm['farm_name'] ?? ''}');
    final country = TextEditingController(text: '${farm['country'] ?? ''}');
    final region = TextEditingController(text: '${farm['region'] ?? ''}');
    final workers = TextEditingController(text: '${farm['worker_count'] ?? 0}');
    final vets = TextEditingController(text: '${farm['veterinarian_count'] ?? 0}');
    final barns = TextEditingController(text: '${farm['barn_count'] ?? 0}');
    final area = TextEditingController(text: '${farm['total_indoor_area_m2'] ?? 0}');
    final vaccination = TextEditingController(text: '${farm['vaccination_notes'] ?? ''}');
    final diseases = TextEditingController(text: '${farm['disease_history'] ?? ''}');

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_ct(context, 'Edit company and farm', 'تعديل الشركة والمزرعة', 'Bedrijf en boerderij bewerken')),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(child: TextField(controller: company, decoration: InputDecoration(labelText: _ct(context, 'Company name', 'اسم الشركة', 'Bedrijfsnaam')))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: name, decoration: InputDecoration(labelText: _ct(context, 'Farm name', 'اسم المزرعة', 'Boerderijnaam')))),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: country, decoration: InputDecoration(labelText: _ct(context, 'Country', 'الدولة', 'Land')))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: region, decoration: InputDecoration(labelText: _ct(context, 'Region', 'المنطقة', 'Regio')))),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: workers, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _ct(context, 'Workers', 'العمال', 'Werknemers')))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: vets, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _ct(context, 'Veterinarians', 'الأطباء البيطريون', 'Dierenartsen')))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: barns, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _ct(context, 'Sections / barns', 'الأقسام / الحظائر', 'Afdelingen / stallen')))),
              ]),
              const SizedBox(height: 10),
              TextField(controller: area, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: _ct(context, 'Indoor area m²', 'المساحة الداخلية م²', 'Binnenoppervlak m²'))),
              const SizedBox(height: 10),
              TextField(controller: vaccination, minLines: 2, maxLines: 4, decoration: InputDecoration(labelText: _ct(context, 'Vaccination notes', 'ملاحظات التطعيم', 'Vaccinatienotities'))),
              const SizedBox(height: 10),
              TextField(controller: diseases, minLines: 2, maxLines: 4, decoration: InputDecoration(labelText: _ct(context, 'Disease history', 'التاريخ المرضي', 'Ziektegeschiedenis'))),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_ct(context, 'Cancel', 'إلغاء', 'Annuleren'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_ct(context, 'Save', 'حفظ', 'Opslaan'))),
        ],
      ),
    );
    if (ok != true) return;

    await admin.updateFarm(farm['id'].toString(), {
      'company_name': company.text.trim(),
      'farm_name': name.text.trim(),
      'country': country.text.trim(),
      'region': region.text.trim(),
      'worker_count': int.tryParse(workers.text) ?? 0,
      'veterinarian_count': int.tryParse(vets.text) ?? 0,
      'barn_count': int.tryParse(barns.text) ?? 0,
      'total_indoor_area_m2': double.tryParse(area.text) ?? 0,
      'vaccination_notes': vaccination.text.trim(),
      'disease_history': diseases.text.trim(),
    });
    reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_CompanyData>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('${snapshot.error}', style: const TextStyle(color: VetColors.red)));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!;
          final ownerNames = {for (final p in data.profiles) p['id'].toString(): '${p['full_name'] ?? ''}'};
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(_ct(context, 'Companies & farms control center', 'مركز التحكم في الشركات والمزارع', 'Controlecentrum bedrijven & boerderijen'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 5),
              Text(_ct(context, 'Open any company for a complete operational, sensor, alert, support, subscription and payment view.', 'افتح أي شركة لتشوف وتتحكم في التشغيل والحساسات والإنذارات والدعم والاشتراك والمدفوعات.', 'Open een bedrijf voor volledig inzicht in operatie, sensoren, meldingen, support, abonnement en betalingen.'), style: const TextStyle(color: VetColors.muted)),
              const SizedBox(height: 16),
              for (final farm in data.farms)
                _CompanyCard(
                  farm: farm,
                  ownerName: ownerNames[farm['owner_id'].toString()] ?? '',
                  sensorCount: data.sensors.where((e) => e['farm_id'] == farm['id']).length,
                  onlineSensors: data.sensors.where((e) => e['farm_id'] == farm['id'] && _isOnline(e)).length,
                  animalCount: data.animals.where((e) => e['farm_id'] == farm['id'] && e['active'] == true).length,
                  openAlerts: data.alerts.where((e) => e['farm_id'] == farm['id'] && e['acknowledged_at'] == null).length,
                  supportCount: data.support.where((e) => e['farm_id'] == farm['id'] && e['status'] != 'closed').length,
                  subscription: data.subscriptions.where((e) => e['farm_id'] == farm['id']).firstOrNull,
                  paidTotal: data.payments.where((e) => e['farm_id'] == farm['id'] && e['status'] == 'paid').fold<double>(0, (sum, e) => sum + (num.tryParse('${e['amount']}')?.toDouble() ?? 0)),
                  onEdit: () => _editFarm(farm),
                  onOpen: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VetAdminCompanyDetail(farm: farm, data: data, onFarmEdited: reload))),
                ),
            ],
          );
        },
      );

  static bool _isOnline(Map<String, dynamic> sensor) {
    if (sensor['active'] != true) return false;
    final lastSeen = DateTime.tryParse('${sensor['last_seen_at'] ?? ''}');
    if (lastSeen == null) return false;
    return DateTime.now().toUtc().difference(lastSeen.toUtc()) < const Duration(minutes: 10);
  }
}

class _CompanyCard extends StatelessWidget {
  const _CompanyCard({required this.farm, required this.ownerName, required this.sensorCount, required this.onlineSensors, required this.animalCount, required this.openAlerts, required this.supportCount, required this.subscription, required this.paidTotal, required this.onEdit, required this.onOpen});
  final Map<String, dynamic> farm;
  final String ownerName;
  final int sensorCount;
  final int onlineSensors;
  final int animalCount;
  final int openAlerts;
  final int supportCount;
  final Map<String, dynamic>? subscription;
  final double paidTotal;
  final VoidCallback onEdit;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 14),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(17),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const CircleAvatar(radius: 24, child: Icon(Icons.domain_rounded)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${farm['company_name'] ?? ''}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  Text('${farm['farm_name'] ?? ''} • ${farm['country'] ?? ''} • ${farm['region'] ?? ''}', style: const TextStyle(color: VetColors.muted)),
                  if (ownerName.trim().isNotEmpty) Text('${_ct(context, 'Owner', 'المالك', 'Eigenaar')}: $ownerName', style: const TextStyle(fontSize: 11.5, color: VetColors.muted)),
                ])),
                IconButton(onPressed: onEdit, icon: const Icon(Icons.edit_rounded)),
                const Icon(Icons.chevron_right_rounded),
              ]),
              const SizedBox(height: 13),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Chip(avatar: const Icon(Icons.sensors_rounded, size: 17), label: Text('$onlineSensors/$sensorCount ${_ct(context, 'sensors online', 'حساس متصل', 'sensoren online')}')),
                Chip(avatar: const Icon(Icons.pets_rounded, size: 17), label: Text('$animalCount ${_ct(context, 'animals', 'حيوان', 'dieren')}')),
                Chip(avatar: Icon(Icons.warning_rounded, size: 17, color: openAlerts > 0 ? VetColors.red : VetColors.green), label: Text('$openAlerts ${_ct(context, 'open alerts', 'إنذار مفتوح', 'open meldingen')}')),
                Chip(avatar: const Icon(Icons.support_agent_rounded, size: 17), label: Text('$supportCount ${_ct(context, 'support', 'دعم', 'support')}')),
                Chip(avatar: const Icon(Icons.workspace_premium_rounded, size: 17), label: Text('${subscription?['status'] ?? farm['subscription_status'] ?? '-'}')),
                Chip(avatar: const Icon(Icons.payments_rounded, size: 17), label: Text('€${paidTotal.toStringAsFixed(2)}')),
              ]),
            ]),
          ),
        ),
      );
}

class VetAdminCompanyDetail extends StatelessWidget {
  const VetAdminCompanyDetail({super.key, required this.farm, required this.data, required this.onFarmEdited});
  final Map<String, dynamic> farm;
  final _CompanyData data;
  final VoidCallback onFarmEdited;

  @override
  Widget build(BuildContext context) {
    final id = farm['id'].toString();
    final sensors = data.sensors.where((e) => e['farm_id'].toString() == id).toList();
    final animals = data.animals.where((e) => e['farm_id'].toString() == id).toList();
    final alerts = data.alerts.where((e) => e['farm_id'].toString() == id).take(20).toList();
    final support = data.support.where((e) => e['farm_id'].toString() == id).toList();
    final subscriptions = data.subscriptions.where((e) => e['farm_id'].toString() == id).toList();
    final payments = data.payments.where((e) => e['farm_id'].toString() == id).toList();
    final owner = data.profiles.where((e) => e['id'].toString() == farm['owner_id'].toString()).firstOrNull;

    return DefaultTabController(
      length: 7,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${farm['company_name'] ?? ''} / ${farm['farm_name'] ?? ''}'),
          bottom: TabBar(isScrollable: true, tabs: [
            Tab(text: _ct(context, 'Overview', 'نظرة عامة', 'Overzicht')),
            Tab(text: _ct(context, 'Sensors', 'الحساسات', 'Sensoren')),
            Tab(text: _ct(context, 'Animals', 'الحيوانات', 'Dieren')),
            Tab(text: _ct(context, 'Alerts', 'الإنذارات', 'Meldingen')),
            Tab(text: _ct(context, 'Support', 'الدعم', 'Support')),
            Tab(text: _ct(context, 'Subscription', 'الاشتراك', 'Abonnement')),
            Tab(text: _ct(context, 'Payments', 'المدفوعات', 'Betalingen')),
          ]),
        ),
        body: TabBarView(children: [
          _detailList(context, [
            _line(_ct(context, 'Company', 'الشركة', 'Bedrijf'), farm['company_name']),
            _line(_ct(context, 'Farm', 'المزرعة', 'Boerderij'), farm['farm_name']),
            _line(_ct(context, 'Owner', 'المالك', 'Eigenaar'), owner?['full_name']),
            _line(_ct(context, 'Phone', 'الهاتف', 'Telefoon'), owner?['phone']),
            _line(_ct(context, 'Country / region', 'الدولة / المنطقة', 'Land / regio'), '${farm['country'] ?? ''} / ${farm['region'] ?? ''}'),
            _line(_ct(context, 'Workers', 'العمال', 'Werknemers'), farm['worker_count']),
            _line(_ct(context, 'Veterinarians', 'الأطباء', 'Dierenartsen'), farm['veterinarian_count']),
            _line(_ct(context, 'Barns / sections', 'الحظائر / الأقسام', 'Stallen / afdelingen'), farm['barn_count']),
            _line(_ct(context, 'Subscription state', 'حالة الاشتراك', 'Abonnementsstatus'), farm['subscription_status']),
          ]),
          _simpleRows(context, sensors, (e) => '${e['display_name'] ?? e['device_uid']}', (e) => '${e['section_name'] ?? '-'} • ${e['active'] == true ? 'active' : 'disabled'} • ${e['last_seen_at'] ?? '-'}', Icons.sensors_rounded),
          _simpleRows(context, animals, (e) => '${e['name'] ?? e['external_id'] ?? '-'}', (e) => '${e['species'] ?? ''} • ${e['breed'] ?? ''} • ${e['active'] == true ? 'active' : 'inactive'}', Icons.pets_rounded),
          _simpleRows(context, alerts, (e) => '${e['title'] ?? ''}', (e) => '${e['risk']} • ${e['details'] ?? ''} • ${e['created_at'] ?? ''}', Icons.warning_rounded),
          _simpleRows(context, support, (e) => '${e['subject'] ?? 'Support'}', (e) => '${e['status']} • ${e['priority'] ?? 'normal'} • unread ${e['unread_by_admin'] ?? 0}', Icons.support_agent_rounded),
          _simpleRows(context, subscriptions, (e) => '${e['status']}', (e) => '${e['billing_cycle']} • ${e['currency']} ${e['amount']} • ${e['current_period_end'] ?? ''}', Icons.workspace_premium_rounded),
          _simpleRows(context, payments, (e) => '${e['currency']} ${e['amount']}', (e) => '${e['status']} • ${e['provider']} • ${e['description'] ?? ''}', Icons.payments_rounded),
        ]),
      ),
    );
  }

  Widget _detailList(BuildContext context, List<Widget> rows) => ListView(padding: const EdgeInsets.all(18), children: rows);
  Widget _line(String label, dynamic value) => Card(child: ListTile(title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)), trailing: SizedBox(width: 260, child: Text('${value ?? '-'}', textAlign: TextAlign.end))));
  Widget _simpleRows(BuildContext context, List<Map<String, dynamic>> rows, String Function(Map<String, dynamic>) title, String Function(Map<String, dynamic>) subtitle, IconData icon) => ListView(padding: const EdgeInsets.all(18), children: [for (final row in rows) Card(child: ListTile(leading: CircleAvatar(child: Icon(icon)), title: Text(title(row), style: const TextStyle(fontWeight: FontWeight.w900)), subtitle: Text(subtitle(row))))]);
}

class _CompanyData {
  const _CompanyData({required this.farms, required this.profiles, required this.sensors, required this.animals, required this.alerts, required this.support, required this.subscriptions, required this.payments});
  final List<Map<String, dynamic>> farms;
  final List<Map<String, dynamic>> profiles;
  final List<Map<String, dynamic>> sensors;
  final List<Map<String, dynamic>> animals;
  final List<Map<String, dynamic>> alerts;
  final List<Map<String, dynamic>> support;
  final List<Map<String, dynamic>> subscriptions;
  final List<Map<String, dynamic>> payments;
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

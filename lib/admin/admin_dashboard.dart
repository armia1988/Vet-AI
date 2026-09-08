import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n/vet_locale.dart';
import '../services/vet_backend.dart';
import '../support/support_console.dart';
import '../theme/app_theme.dart';
import 'admin_service.dart';

String _at(BuildContext context, String en, String ar, String nl) =>
    VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

class VetAdminDashboard extends StatefulWidget {
  const VetAdminDashboard({super.key});

  @override
  State<VetAdminDashboard> createState() => _VetAdminDashboardState();
}

class _VetAdminDashboardState extends State<VetAdminDashboard> {
  final admin = VetAdminService.instance;
  int index = 0;
  int refreshTick = 0;
  String? role;
  Timer? refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadRole();
    refreshTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (mounted && index == 0) setState(() => refreshTick++);
    });
  }

  Future<void> _loadRole() async {
    final value = await admin.role();
    if (mounted) setState(() => role = value);
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    super.dispose();
  }

  List<_AdminDestination> get destinations => [
        _AdminDestination(Icons.space_dashboard_rounded, _at(context, 'Overview', 'نظرة عامة', 'Overzicht')),
        _AdminDestination(Icons.domain_rounded, _at(context, 'Companies & farms', 'الشركات والمزارع', 'Bedrijven & boerderijen')),
        _AdminDestination(Icons.people_alt_rounded, _at(context, 'Customers', 'العملاء', 'Klanten')),
        _AdminDestination(Icons.pets_rounded, _at(context, 'Animals', 'الحيوانات', 'Dieren')),
        _AdminDestination(Icons.sensors_rounded, _at(context, 'Sensors & devices', 'الحساسات والأجهزة', 'Sensoren & apparaten')),
        _AdminDestination(Icons.warning_amber_rounded, _at(context, 'Alerts center', 'مركز الإنذارات', 'Meldingscentrum')),
        _AdminDestination(Icons.notifications_active_rounded, _at(context, 'Notifications', 'الإشعارات', 'Meldingen')),
        _AdminDestination(Icons.support_agent_rounded, _at(context, 'Support inbox', 'رسائل الدعم', 'Support-inbox')),
        _AdminDestination(Icons.workspace_premium_rounded, _at(context, 'Subscriptions', 'الاشتراكات', 'Abonnementen')),
        _AdminDestination(Icons.payments_rounded, _at(context, 'Payments', 'المدفوعات', 'Betalingen')),
        _AdminDestination(Icons.admin_panel_settings_rounded, _at(context, 'Admin staff', 'فريق الإدارة', 'Adminteam')),
        _AdminDestination(Icons.history_rounded, _at(context, 'Audit log', 'سجل العمليات', 'Auditlog')),
        _AdminDestination(Icons.settings_rounded, _at(context, 'System', 'النظام', 'Systeem')),
      ];

  Widget _page() {
    switch (index) {
      case 0:
        return _OverviewPage(key: ValueKey('overview-$refreshTick'));
      case 1:
        return _FarmsPage(key: ValueKey('farms-$refreshTick'));
      case 2:
        return _CustomersPage(key: ValueKey('customers-$refreshTick'));
      case 3:
        return _AnimalsPage(key: ValueKey('animals-$refreshTick'));
      case 4:
        return _SensorsPage(key: ValueKey('sensors-$refreshTick'));
      case 5:
        return _AlertsPage(key: ValueKey('alerts-$refreshTick'));
      case 6:
        return _NotificationsPage(key: ValueKey('notifications-$refreshTick'));
      case 7:
        return _SupportPage(key: ValueKey('support-$refreshTick'));
      case 8:
        return _SubscriptionsPage(key: ValueKey('subscriptions-$refreshTick'));
      case 9:
        return _PaymentsPage(key: ValueKey('payments-$refreshTick'));
      case 10:
        return _AdminsPage(key: ValueKey('admins-$refreshTick'));
      case 11:
        return _AuditPage(key: ValueKey('audit-$refreshTick'));
      default:
        return const _SystemPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final body = Column(
      children: [
        _AdminTopBar(
          title: destinations[index].label,
          role: role ?? 'admin',
          onRefresh: () => setState(() => refreshTick++),
        ),
        Expanded(child: _page()),
      ],
    );

    if (!wide) {
      return Scaffold(
        drawer: Drawer(
          child: SafeArea(
            child: Column(
              children: [
                const _AdminBrandHeader(),
                Expanded(
                  child: ListView.builder(
                    itemCount: destinations.length,
                    itemBuilder: (context, i) => ListTile(
                      selected: i == index,
                      leading: Icon(destinations[i].icon),
                      title: Text(destinations[i].label),
                      onTap: () {
                        setState(() => index = i);
                        Navigator.pop(context);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        appBar: AppBar(
          title: Text(destinations[index].label),
          actions: [
            IconButton(
              onPressed: () => setState(() => refreshTick++),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: _page(),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 265,
            decoration: const BoxDecoration(
              color: VetColors.surface2,
              border: Border(right: BorderSide(color: VetColors.border)),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  const _AdminBrandHeader(),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      itemCount: destinations.length,
                      itemBuilder: (context, i) {
                        final d = destinations[i];
                        final selected = i == index;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Material(
                            color: selected ? VetColors.softGreen : Colors.transparent,
                            borderRadius: BorderRadius.circular(13),
                            child: ListTile(
                              selected: selected,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                              leading: Icon(d.icon, color: selected ? VetColors.green : VetColors.muted),
                              title: Text(d.label, style: TextStyle(fontWeight: selected ? FontWeight.w900 : FontWeight.w700)),
                              onTap: () => setState(() => index = i),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: VetColors.surface3,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: VetColors.border),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_at(context, 'Signed in as', 'تسجيل الدخول كـ', 'Ingelogd als'), style: const TextStyle(color: VetColors.muted, fontSize: 11)),
                        const SizedBox(height: 4),
                        Text(role ?? 'admin', style: const TextStyle(fontWeight: FontWeight.w900)),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _AdminDestination {
  const _AdminDestination(this.icon, this.label);
  final IconData icon;
  final String label;
}

class _AdminBrandHeader extends StatelessWidget {
  const _AdminBrandHeader();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: VetColors.softGreen, borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.health_and_safety_rounded, color: VetColors.green, size: 27),
          ),
          const SizedBox(width: 11),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Vet AI', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              Text('ADMIN CONTROL CENTER', style: TextStyle(fontSize: 9.5, letterSpacing: 1.1, color: VetColors.muted, fontWeight: FontWeight.w800)),
            ]),
          ),
        ]),
      );
}

class _AdminTopBar extends StatelessWidget {
  const _AdminTopBar({required this.title, required this.role, required this.onRefresh});
  final String title;
  final String role;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: VetColors.border))),
        child: Row(children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
          Chip(avatar: const Icon(Icons.verified_user_rounded, size: 18, color: VetColors.green), label: Text(role)),
          const SizedBox(width: 8),
          IconButton.filledTonal(onPressed: onRefresh, icon: const Icon(Icons.refresh_rounded)),
          const SizedBox(width: 6),
          IconButton.filledTonal(onPressed: () => showVetLanguagePicker(context), icon: const Icon(Icons.language_rounded)),
        ]),
      );
}

class _AdminPageFrame extends StatelessWidget {
  const _AdminPageFrame({required this.children, this.actions = const []});
  final List<Widget> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: () async {},
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (actions.isNotEmpty) ...[
              Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: actions),
              const SizedBox(height: 14),
            ],
            ...children,
            const SizedBox(height: 50),
          ],
        ),
      );
}

class _LoadError extends StatelessWidget {
  const _LoadError(this.error);
  final Object? error;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline_rounded, size: 54, color: VetColors.red),
            const SizedBox(height: 12),
            Text(_at(context, 'Admin data could not be loaded.', 'تعذر تحميل بيانات الإدارة.', 'Admin-gegevens konden niet worden geladen.'), style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text('$error', textAlign: TextAlign.center, style: const TextStyle(color: VetColors.muted, fontSize: 12)),
          ]),
        ),
      );
}

class _OverviewPage extends StatelessWidget {
  const _OverviewPage({super.key});

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: VetAdminService.instance.stats(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return _LoadError(snapshot.error);
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final s = snapshot.data!;
          final cards = <_MetricData>[
            _MetricData(Icons.people_alt_rounded, _at(context, 'Customers', 'العملاء', 'Klanten'), s['customers'], VetColors.blue),
            _MetricData(Icons.domain_rounded, _at(context, 'Farms', 'المزارع', 'Boerderijen'), s['farms'], VetColors.green),
            _MetricData(Icons.pets_rounded, _at(context, 'Animals', 'الحيوانات', 'Dieren'), s['animals'], VetColors.history),
            _MetricData(Icons.sensors_rounded, _at(context, 'Sensors online', 'الحساسات المتصلة', 'Sensoren online'), '${s['sensors_online'] ?? 0}/${s['sensors_active'] ?? 0}', VetColors.green),
            _MetricData(Icons.sensors_off_rounded, _at(context, 'Sensors offline', 'الحساسات غير المتصلة', 'Sensoren offline'), s['sensors_offline'], VetColors.red),
            _MetricData(Icons.report_problem_rounded, _at(context, 'Red alerts 24h', 'إنذارات حمراء 24س', 'Rode meldingen 24u'), s['red_alerts_24h'], VetColors.red),
            _MetricData(Icons.warning_amber_rounded, _at(context, 'Orange alerts 24h', 'إنذارات برتقالية 24س', 'Oranje meldingen 24u'), s['orange_alerts_24h'], VetColors.history),
            _MetricData(Icons.support_agent_rounded, _at(context, 'Open support', 'دعم مفتوح', 'Open support'), s['support_open'], VetColors.blue),
            _MetricData(Icons.mark_chat_unread_rounded, _at(context, 'Unread messages', 'رسائل غير مقروءة', 'Ongelezen berichten'), s['support_unread'], VetColors.history),
            _MetricData(Icons.workspace_premium_rounded, _at(context, 'Active subscriptions', 'اشتراكات فعالة', 'Actieve abonnementen'), s['subscriptions_active'], VetColors.green),
            _MetricData(Icons.money_off_rounded, _at(context, 'Past due', 'متأخرات الاشتراك', 'Achterstallig'), s['subscriptions_past_due'], VetColors.red),
            _MetricData(Icons.pending_actions_rounded, _at(context, 'Pending payments', 'مدفوعات معلقة', 'Openstaande betalingen'), s['payments_pending'], VetColors.history),
          ];
          return _AdminPageFrame(children: [
            _HeroPanel(
              title: _at(context, 'Vet AI global operations', 'التحكم العالمي في Vet AI', 'Vet AI wereldwijde operaties'),
              subtitle: _at(context, 'Live operational view across customers, farms, sensors, alerts, support and commercial activity.', 'متابعة مباشرة لكل العملاء والمزارع والحساسات والإنذارات والدعم والاشتراكات.', 'Live overzicht van klanten, boerderijen, sensoren, meldingen, support en commerciële activiteit.'),
            ),
            const SizedBox(height: 18),
            LayoutBuilder(builder: (context, c) {
              final w = c.maxWidth;
              final width = w >= 1200 ? (w - 48) / 4 : w >= 760 ? (w - 32) / 3 : w >= 500 ? (w - 16) / 2 : w;
              return Wrap(spacing: 16, runSpacing: 16, children: [for (final card in cards) SizedBox(width: width, child: _MetricCard(card))]);
            }),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(children: [
                  const Icon(Icons.account_balance_wallet_rounded, size: 34, color: VetColors.green),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_at(context, 'Recorded paid revenue', 'إجمالي المدفوعات المسجلة', 'Geregistreerde betaalde omzet'), style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text('€ ${s['payments_paid_total'] ?? 0}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                  ])),
                ]),
              ),
            ),
          ]);
        },
      );
}

class _MetricData {
  const _MetricData(this.icon, this.title, this.value, this.color);
  final IconData icon;
  final String title;
  final dynamic value;
  final Color color;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(this.data);
  final _MetricData data;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(width: 45, height: 45, decoration: BoxDecoration(color: data.color.withValues(alpha: .12), borderRadius: BorderRadius.circular(13)), child: Icon(data.icon, color: data.color)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${data.value ?? 0}', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
              Text(data.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: VetColors.muted, fontSize: 12, fontWeight: FontWeight.w700)),
            ])),
          ]),
        ),
      );
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: VetColors.surface2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: VetColors.green.withValues(alpha: .25)),
        ),
        child: Row(children: [
          Container(width: 58, height: 58, decoration: BoxDecoration(color: VetColors.softGreen, borderRadius: BorderRadius.circular(17)), child: const Icon(Icons.command_rounded, size: 34, color: VetColors.green)),
          const SizedBox(width: 15),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 5),
            Text(subtitle, style: const TextStyle(color: VetColors.muted, height: 1.45)),
          ])),
        ]),
      );
}

class _FarmsPage extends StatefulWidget {
  const _FarmsPage({super.key});
  @override
  State<_FarmsPage> createState() => _FarmsPageState();
}

class _FarmsPageState extends State<_FarmsPage> {
  late Future<List<Map<String, dynamic>>> future = VetAdminService.instance.farms();
  void reload() => setState(() => future = VetAdminService.instance.farms());

  Future<void> edit(Map<String, dynamic> row) async {
    final company = TextEditingController(text: '${row['company_name'] ?? ''}');
    final farm = TextEditingController(text: '${row['farm_name'] ?? ''}');
    final country = TextEditingController(text: '${row['country'] ?? ''}');
    final region = TextEditingController(text: '${row['region'] ?? ''}');
    final workers = TextEditingController(text: '${row['worker_count'] ?? 0}');
    final vets = TextEditingController(text: '${row['veterinarian_count'] ?? 0}');
    final barns = TextEditingController(text: '${row['barn_count'] ?? 0}');
    final ok = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text(_at(context, 'Edit company / farm', 'تعديل الشركة / المزرعة', 'Bedrijf / boerderij bewerken')),
      content: SizedBox(width: 560, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: company, decoration: InputDecoration(labelText: _at(context, 'Company name', 'اسم الشركة', 'Bedrijfsnaam'))),
        const SizedBox(height: 10), TextField(controller: farm, decoration: InputDecoration(labelText: _at(context, 'Farm name', 'اسم المزرعة', 'Boerderijnaam'))),
        const SizedBox(height: 10), Row(children: [Expanded(child: TextField(controller: country, decoration: InputDecoration(labelText: _at(context, 'Country', 'الدولة', 'Land')))), const SizedBox(width: 10), Expanded(child: TextField(controller: region, decoration: InputDecoration(labelText: _at(context, 'Region', 'المنطقة', 'Regio'))))]),
        const SizedBox(height: 10), Row(children: [Expanded(child: TextField(controller: workers, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _at(context, 'Workers', 'العمال', 'Werknemers')))), const SizedBox(width: 10), Expanded(child: TextField(controller: vets, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _at(context, 'Veterinarians', 'الأطباء', 'Dierenartsen')))), const SizedBox(width: 10), Expanded(child: TextField(controller: barns, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _at(context, 'Barns', 'الأقسام/الحظائر', 'Stallen'))))]),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_at(context, 'Cancel', 'إلغاء', 'Annuleren'))), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_at(context, 'Save', 'حفظ', 'Opslaan')))],
    ));
    if (ok != true) return;
    await VetAdminService.instance.updateFarm(row['id'].toString(), {
      'company_name': company.text.trim(), 'farm_name': farm.text.trim(), 'country': country.text.trim(), 'region': region.text.trim(),
      'worker_count': int.tryParse(workers.text) ?? 0, 'veterinarian_count': int.tryParse(vets.text) ?? 0, 'barn_count': int.tryParse(barns.text) ?? 0,
    });
    reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasError) return _LoadError(snapshot.error);
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final rows = snapshot.data!;
      return _AdminPageFrame(children: [
        _SectionTitle(icon: Icons.domain_rounded, title: _at(context, 'All customer companies and farms', 'كل شركات ومزارع العملاء', 'Alle klantbedrijven en boerderijen'), subtitle: '${rows.length}'),
        const SizedBox(height: 12),
        for (final row in rows) Card(child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.agriculture_rounded)),
          title: Text('${row['company_name'] ?? ''} — ${row['farm_name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w900)),
          subtitle: Text('${row['country'] ?? ''} • ${row['region'] ?? ''}\n${_at(context, 'Plan', 'الخطة', 'Plan')}: ${row['subscription_tier'] ?? '-'} • ${_at(context, 'Animals', 'الحيوانات', 'Dieren')}: ${(row['livestock_count'] ?? 0)} + ${(row['poultry_count'] ?? 0)} + ${(row['dog_count'] ?? 0)}'),
          isThreeLine: true,
          trailing: IconButton(onPressed: () => edit(row), icon: const Icon(Icons.edit_rounded)),
          onTap: () => edit(row),
        )),
      ]);
    },
  );
}

class _CustomersPage extends StatefulWidget {
  const _CustomersPage({super.key});
  @override
  State<_CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<_CustomersPage> {
  late Future<List<Map<String, dynamic>>> future = VetAdminService.instance.profiles();
  void reload() => setState(() => future = VetAdminService.instance.profiles());

  Future<void> edit(Map<String, dynamic> row) async {
    final name = TextEditingController(text: '${row['full_name'] ?? ''}');
    final phone = TextEditingController(text: '${row['phone'] ?? ''}');
    final job = TextEditingController(text: '${row['job_title'] ?? ''}');
    final lang = TextEditingController(text: '${row['preferred_language'] ?? ''}');
    final ok = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text(_at(context, 'Edit customer', 'تعديل العميل', 'Klant bewerken')),
      content: SizedBox(width: 480, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: InputDecoration(labelText: _at(context, 'Full name', 'الاسم الكامل', 'Volledige naam'))), const SizedBox(height: 10),
        TextField(controller: phone, decoration: InputDecoration(labelText: _at(context, 'Phone', 'الهاتف', 'Telefoon'))), const SizedBox(height: 10),
        TextField(controller: job, decoration: InputDecoration(labelText: _at(context, 'Job title', 'الوظيفة', 'Functie'))), const SizedBox(height: 10),
        TextField(controller: lang, decoration: InputDecoration(labelText: _at(context, 'Language code', 'كود اللغة', 'Taalcode'))),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_at(context, 'Cancel', 'إلغاء', 'Annuleren'))), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_at(context, 'Save', 'حفظ', 'Opslaan')))],
    ));
    if (ok != true) return;
    await VetAdminService.instance.updateProfile(row['id'].toString(), {'full_name': name.text.trim(), 'phone': phone.text.trim(), 'job_title': job.text.trim(), 'preferred_language': lang.text.trim()});
    reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(future: future, builder: (context, snapshot) {
    if (snapshot.hasError) return _LoadError(snapshot.error);
    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
    final rows = snapshot.data!;
    return _AdminPageFrame(children: [
      _SectionTitle(icon: Icons.people_alt_rounded, title: _at(context, 'Customer accounts', 'حسابات العملاء', 'Klantaccounts'), subtitle: '${rows.length}'), const SizedBox(height: 12),
      for (final row in rows) Card(child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
        title: Text('${row['full_name'] ?? _at(context, 'Unnamed customer', 'عميل بدون اسم', 'Naamloze klant')}', style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text('${row['phone'] ?? ''} • ${row['preferred_language'] ?? ''}\nID: ${row['id']}'), isThreeLine: true,
        trailing: IconButton(onPressed: () => edit(row), icon: const Icon(Icons.edit_rounded)), onTap: () => edit(row),
      )),
    ]);
  });
}

class _AnimalsPage extends StatelessWidget {
  const _AnimalsPage({super.key});
  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(
    future: Future.wait([VetAdminService.instance.animals(), VetAdminService.instance.farms()]),
    builder: (context, snapshot) {
      if (snapshot.hasError) return _LoadError(snapshot.error);
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final animals = snapshot.data![0] as List<Map<String, dynamic>>;
      final farms = snapshot.data![1] as List<Map<String, dynamic>>;
      final names = {for (final f in farms) f['id'].toString(): '${f['company_name'] ?? ''} / ${f['farm_name'] ?? ''}'};
      return _AdminPageFrame(children: [
        _SectionTitle(icon: Icons.pets_rounded, title: _at(context, 'All registered animals', 'كل الحيوانات المسجلة', 'Alle geregistreerde dieren'), subtitle: '${animals.length}'), const SizedBox(height: 12),
        for (final a in animals) Card(child: ListTile(
          leading: CircleAvatar(child: Icon(a['active'] == true ? Icons.pets_rounded : Icons.block_rounded)),
          title: Text('${a['name'] ?? a['external_id'] ?? '-'} • ${a['species'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w900)),
          subtitle: Text('${names[a['farm_id'].toString()] ?? a['farm_id']}\n${a['breed'] ?? ''} • ${a['sex'] ?? ''} • ${a['weight_kg'] ?? '-'} kg'), isThreeLine: true,
          trailing: Chip(label: Text(a['active'] == true ? _at(context, 'Active', 'نشط', 'Actief') : _at(context, 'Inactive', 'غير نشط', 'Inactief'))),
        )),
      ]);
    },
  );
}

class _SensorsPage extends StatefulWidget {
  const _SensorsPage({super.key});
  @override
  State<_SensorsPage> createState() => _SensorsPageState();
}

class _SensorsPageState extends State<_SensorsPage> {
  late Future<List<dynamic>> future = _load();
  Future<List<dynamic>> _load() => Future.wait([VetAdminService.instance.sensors(), VetAdminService.instance.farms()]);
  void reload() => setState(() => future = _load());

  bool online(Map<String, dynamic> row) {
    final raw = row['last_seen_at']?.toString();
    final date = raw == null ? null : DateTime.tryParse(raw);
    return row['active'] == true && date != null && DateTime.now().toUtc().difference(date.toUtc()) < const Duration(minutes: 10);
  }

  Future<void> edit(Map<String, dynamic> row) async {
    final name = TextEditingController(text: '${row['display_name'] ?? ''}');
    final section = TextEditingController(text: '${row['section_name'] ?? ''}');
    final firmware = TextEditingController(text: '${row['firmware_version'] ?? ''}');
    final notes = TextEditingController(text: '${row['admin_notes'] ?? ''}');
    var active = row['active'] == true;
    final ok = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setLocal) => AlertDialog(
      title: Text(_at(context, 'Control sensor device', 'التحكم في جهاز الحساس', 'Sensorapparaat beheren')),
      content: SizedBox(width: 540, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: InputDecoration(labelText: _at(context, 'Device name', 'اسم الجهاز', 'Apparaatnaam'))), const SizedBox(height: 10),
        TextField(controller: section, decoration: InputDecoration(labelText: _at(context, 'Section / barn', 'القسم / الحظيرة', 'Afdeling / stal'))), const SizedBox(height: 10),
        TextField(controller: firmware, decoration: const InputDecoration(labelText: 'Firmware')), const SizedBox(height: 10),
        TextField(controller: notes, minLines: 2, maxLines: 4, decoration: InputDecoration(labelText: _at(context, 'Admin notes', 'ملاحظات الإدارة', 'Adminnotities'))), const SizedBox(height: 8),
        SwitchListTile(value: active, onChanged: (v) => setLocal(() => active = v), title: Text(_at(context, 'Device enabled', 'الجهاز مفعّل', 'Apparaat ingeschakeld'))),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_at(context, 'Cancel', 'إلغاء', 'Annuleren'))), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_at(context, 'Save', 'حفظ', 'Opslaan')))],
    )));
    if (ok != true) return;
    await VetAdminService.instance.updateSensor(row['id'].toString(), {'display_name': name.text.trim(), 'section_name': section.text.trim(), 'firmware_version': firmware.text.trim(), 'admin_notes': notes.text.trim(), 'active': active, 'admin_disabled_reason': active ? null : 'Disabled from Vet AI Admin'});
    reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(future: future, builder: (context, snapshot) {
    if (snapshot.hasError) return _LoadError(snapshot.error);
    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
    final sensors = snapshot.data![0] as List<Map<String, dynamic>>;
    final farms = snapshot.data![1] as List<Map<String, dynamic>>;
    final farmMap = {for (final f in farms) f['id'].toString(): f};
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final s in sensors) grouped.putIfAbsent(s['farm_id'].toString(), () => []).add(s);
    return _AdminPageFrame(children: [
      _SectionTitle(icon: Icons.sensors_rounded, title: _at(context, 'Sensor fleet by company', 'الحساسات حسب كل شركة', 'Sensorvloot per bedrijf'), subtitle: '${sensors.length}'), const SizedBox(height: 14),
      for (final entry in grouped.entries) ...[
        Card(
          color: VetColors.surface2,
          child: Padding(padding: const EdgeInsets.all(15), child: Row(children: [
            const Icon(Icons.domain_rounded, color: VetColors.green), const SizedBox(width: 10),
            Expanded(child: Text('${farmMap[entry.key]?['company_name'] ?? ''} / ${farmMap[entry.key]?['farm_name'] ?? entry.key}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
            Chip(label: Text('${entry.value.where(online).length} ${_at(context, 'online', 'متصل', 'online')} / ${entry.value.length}')),
          ])),
        ),
        for (final row in entry.value) Card(child: ListTile(
          leading: CircleAvatar(backgroundColor: online(row) ? VetColors.softGreen : VetColors.surface3, child: Icon(online(row) ? Icons.sensors_rounded : Icons.sensors_off_rounded, color: online(row) ? VetColors.green : VetColors.red)),
          title: Text('${row['display_name'] ?? row['device_uid'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w900)),
          subtitle: Text('${row['section_name'] ?? _at(context, 'No section', 'بدون قسم', 'Geen afdeling')} • ${row['device_type'] ?? ''}\n${_at(context, 'Last seen', 'آخر اتصال', 'Laatst gezien')}: ${row['last_seen_at'] ?? '-'}'), isThreeLine: true,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Chip(label: Text(row['active'] == true ? (online(row) ? _at(context, 'Online', 'متصل', 'Online') : _at(context, 'Offline', 'غير متصل', 'Offline')) : _at(context, 'Disabled', 'مفصول', 'Uitgeschakeld'))),
            IconButton(onPressed: () => edit(row), icon: const Icon(Icons.tune_rounded)),
          ]),
          onTap: () => edit(row),
        )),
        const SizedBox(height: 12),
      ],
    ]);
  });
}

class _AlertsPage extends StatefulWidget {
  const _AlertsPage({super.key});
  @override
  State<_AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<_AlertsPage> {
  late Future<List<dynamic>> future = _load();
  Future<List<dynamic>> _load() => Future.wait([VetAdminService.instance.alerts(), VetAdminService.instance.farms()]);
  void reload() => setState(() => future = _load());

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(future: future, builder: (context, snapshot) {
    if (snapshot.hasError) return _LoadError(snapshot.error);
    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
    final alerts = snapshot.data![0] as List<Map<String, dynamic>>;
    final farms = snapshot.data![1] as List<Map<String, dynamic>>;
    final farmNames = {for (final f in farms) f['id'].toString(): '${f['company_name'] ?? ''} / ${f['farm_name'] ?? ''}'};
    return _AdminPageFrame(children: [
      _SectionTitle(icon: Icons.warning_amber_rounded, title: _at(context, 'Global alerts center', 'مركز الإنذارات العالمي', 'Wereldwijd meldingscentrum'), subtitle: '${alerts.length}'), const SizedBox(height: 12),
      for (final row in alerts) Card(child: ListTile(
        leading: CircleAvatar(backgroundColor: '${row['risk']}' == 'red' ? VetColors.red.withValues(alpha: .12) : VetColors.history.withValues(alpha: .12), child: Icon(Icons.warning_rounded, color: '${row['risk']}' == 'red' ? VetColors.red : VetColors.history)),
        title: Text('${row['title'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text('${farmNames[row['farm_id'].toString()] ?? row['farm_id']}\n${row['details'] ?? ''}\n${row['created_at'] ?? ''}', maxLines: 4, overflow: TextOverflow.ellipsis), isThreeLine: true,
        trailing: row['acknowledged_at'] == null ? IconButton(tooltip: _at(context, 'Acknowledge', 'تأكيد الاطلاع', 'Bevestigen'), onPressed: () async { await VetAdminService.instance.acknowledgeAlert(row['id'].toString()); reload(); }, icon: const Icon(Icons.done_all_rounded)) : const Icon(Icons.verified_rounded, color: VetColors.green),
      )),
    ]);
  });
}

class _NotificationsPage extends StatefulWidget {
  const _NotificationsPage({super.key});
  @override
  State<_NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<_NotificationsPage> {
  late Future<List<dynamic>> future = _load();
  Future<List<dynamic>> _load() => Future.wait([VetAdminService.instance.notifications(), VetAdminService.instance.farms()]);
  void reload() => setState(() => future = _load());

  Future<void> compose(List<Map<String, dynamic>> farms) async {
    final title = TextEditingController();
    final body = TextEditingController();
    String scope = 'all';
    String severity = 'info';
    String? farmId;
    final userId = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setLocal) => AlertDialog(
      title: Text(_at(context, 'Send customer notification', 'إرسال إشعار للعملاء', 'Klantmelding versturen')),
      content: SizedBox(width: 590, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(initialValue: scope, decoration: InputDecoration(labelText: _at(context, 'Target', 'الإرسال إلى', 'Doel')), items: [
          DropdownMenuItem(value: 'all', child: Text(_at(context, 'All customers', 'كل العملاء', 'Alle klanten'))),
          DropdownMenuItem(value: 'farm', child: Text(_at(context, 'One company / farm', 'شركة / مزرعة محددة', 'Eén bedrijf / boerderij'))),
          DropdownMenuItem(value: 'user', child: Text(_at(context, 'One user', 'مستخدم محدد', 'Eén gebruiker'))),
        ], onChanged: (v) => setLocal(() => scope = v ?? 'all')),
        if (scope == 'farm') ...[const SizedBox(height: 10), DropdownButtonFormField<String>(initialValue: farmId, decoration: InputDecoration(labelText: _at(context, 'Farm', 'المزرعة', 'Boerderij')), items: [for (final f in farms) DropdownMenuItem(value: f['id'].toString(), child: Text('${f['company_name'] ?? ''} / ${f['farm_name'] ?? ''}'))], onChanged: (v) => setLocal(() => farmId = v))],
        if (scope == 'user') ...[const SizedBox(height: 10), TextField(controller: userId, decoration: InputDecoration(labelText: _at(context, 'User ID', 'رقم المستخدم', 'Gebruikers-ID')))],
        const SizedBox(height: 10), DropdownButtonFormField<String>(initialValue: severity, decoration: InputDecoration(labelText: _at(context, 'Priority / sound', 'الأولوية / الصوت', 'Prioriteit / geluid')), items: [
          DropdownMenuItem(value: 'info', child: Text(_at(context, 'Normal', 'عادي', 'Normaal'))), DropdownMenuItem(value: 'orange', child: Text(_at(context, 'Orange warning', 'تحذير برتقالي', 'Oranje waarschuwing'))), DropdownMenuItem(value: 'red', child: Text(_at(context, 'Red emergency', 'إنذار أحمر', 'Rood alarm'))),
        ], onChanged: (v) => setLocal(() => severity = v ?? 'info')),
        const SizedBox(height: 10), TextField(controller: title, decoration: InputDecoration(labelText: _at(context, 'Title', 'العنوان', 'Titel'))),
        const SizedBox(height: 10), TextField(controller: body, minLines: 3, maxLines: 6, decoration: InputDecoration(labelText: _at(context, 'Message', 'الرسالة', 'Bericht'))),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_at(context, 'Cancel', 'إلغاء', 'Annuleren'))), FilledButton.icon(onPressed: () => Navigator.pop(dialogContext, true), icon: const Icon(Icons.send_rounded), label: Text(_at(context, 'Send now', 'إرسال الآن', 'Nu versturen')))],
    )));
    if (ok != true || title.text.trim().isEmpty || body.text.trim().isEmpty) return;
    await VetAdminService.instance.sendNotification(targetScope: scope, farmId: farmId, userId: scope == 'user' ? userId.text.trim() : null, title: title.text, body: body.text, severity: severity);
    reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(future: future, builder: (context, snapshot) {
    if (snapshot.hasError) return _LoadError(snapshot.error);
    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
    final rows = snapshot.data![0] as List<Map<String, dynamic>>;
    final farms = snapshot.data![1] as List<Map<String, dynamic>>;
    return _AdminPageFrame(actions: [FilledButton.icon(onPressed: () => compose(farms), icon: const Icon(Icons.add_alert_rounded), label: Text(_at(context, 'New notification', 'إشعار جديد', 'Nieuwe melding')))], children: [
      _SectionTitle(icon: Icons.notifications_active_rounded, title: _at(context, 'Push notification control', 'التحكم الكامل في الإشعارات', 'Pushmeldingen beheren'), subtitle: _at(context, 'All / farm / user', 'الكل / مزرعة / مستخدم', 'Alle / boerderij / gebruiker')), const SizedBox(height: 12),
      for (final row in rows) Card(child: ListTile(
        leading: CircleAvatar(child: Icon('${row['severity']}' == 'red' ? Icons.crisis_alert_rounded : Icons.notifications_rounded)),
        title: Text('${row['title'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text('${row['target_scope']} • ${row['status']} • ${row['sent_count']} sent / ${row['failed_count']} failed\n${row['body'] ?? ''}'), isThreeLine: true,
        trailing: Text('${row['created_at'] ?? ''}', style: const TextStyle(fontSize: 10, color: VetColors.muted)),
      )),
    ]);
  });
}

class _SupportPage extends StatefulWidget {
  const _SupportPage({super.key});
  @override
  State<_SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<_SupportPage> {
  late Future<List<dynamic>> future = _load();
  Future<List<dynamic>> _load() => Future.wait([VetAdminService.instance.supportThreads(), VetAdminService.instance.farms()]);
  void reload() => setState(() => future = _load());

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(future: future, builder: (context, snapshot) {
    if (snapshot.hasError) return _LoadError(snapshot.error);
    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
    final threads = snapshot.data![0] as List<Map<String, dynamic>>;
    final farms = snapshot.data![1] as List<Map<String, dynamic>>;
    final farmMap = {for (final f in farms) f['id'].toString(): f};
    return _AdminPageFrame(actions: [OutlinedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VetSupportConsoleScreen())), icon: const Icon(Icons.open_in_new_rounded), label: Text(_at(context, 'Open full support console', 'فتح كونسول الدعم الكامل', 'Volledige supportconsole openen')))], children: [
      _SectionTitle(icon: Icons.support_agent_rounded, title: _at(context, 'Customer support inbox', 'صندوق رسائل دعم العملاء', 'Klantsupport-inbox'), subtitle: '${threads.length}'), const SizedBox(height: 12),
      for (final row in threads) Card(child: ListTile(
        leading: Badge(label: Text('${row['unread_by_admin'] ?? 0}'), isLabelVisible: (row['unread_by_admin'] ?? 0) != 0, child: const CircleAvatar(child: Icon(Icons.chat_bubble_rounded))),
        title: Text('${farmMap[row['farm_id'].toString()]?['company_name'] ?? ''} / ${farmMap[row['farm_id'].toString()]?['farm_name'] ?? row['farm_id']}', style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text('${row['subject'] ?? ''} • ${row['status']} • ${row['priority']}\n${row['last_message_at'] ?? row['updated_at'] ?? ''}'), isThreeLine: true,
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () async {
          await VetAdminService.instance.markSupportRead(row['id'].toString());
          if (!context.mounted) return;
          final enriched = Map<String, dynamic>.from(row);
          enriched['farms'] = farmMap[row['farm_id'].toString()] ?? <String, dynamic>{};
          await Navigator.push(context, MaterialPageRoute(builder: (_) => VetSupportAgentThreadScreen(thread: enriched)));
          reload();
        },
      )),
    ]);
  });
}

class _SubscriptionsPage extends StatefulWidget {
  const _SubscriptionsPage({super.key});
  @override
  State<_SubscriptionsPage> createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends State<_SubscriptionsPage> {
  late Future<List<dynamic>> future = _load();
  Future<List<dynamic>> _load() => Future.wait([VetAdminService.instance.subscriptions(), VetAdminService.instance.plans(), VetAdminService.instance.farms()]);
  void reload() => setState(() => future = _load());

  Future<void> create(List<Map<String, dynamic>> farms, List<Map<String, dynamic>> plans) async {
    String? farmId;
    String? planId;
    String status = 'active';
    String cycle = 'monthly';
    final amount = TextEditingController(text: '0');
    final ok = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setLocal) => AlertDialog(
      title: Text(_at(context, 'Create subscription', 'إنشاء اشتراك', 'Abonnement aanmaken')),
      content: SizedBox(width: 520, child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(initialValue: farmId, decoration: InputDecoration(labelText: _at(context, 'Farm', 'المزرعة', 'Boerderij')), items: [for (final f in farms) DropdownMenuItem(value: f['id'].toString(), child: Text('${f['company_name'] ?? ''} / ${f['farm_name'] ?? ''}'))], onChanged: (v) => setLocal(() => farmId = v)), const SizedBox(height: 10),
        DropdownButtonFormField<String>(initialValue: planId, decoration: InputDecoration(labelText: _at(context, 'Plan', 'الخطة', 'Plan')), items: [for (final p in plans) DropdownMenuItem(value: p['id'].toString(), child: Text('${p['name']} — €${p['monthly_price']}/m'))], onChanged: (v) { setLocal(() => planId = v); final p = plans.where((e) => e['id'].toString() == v).firstOrNull; if (p != null) amount.text = '${p['monthly_price'] ?? 0}'; }), const SizedBox(height: 10),
        Row(children: [Expanded(child: DropdownButtonFormField<String>(initialValue: status, decoration: InputDecoration(labelText: _at(context, 'Status', 'الحالة', 'Status')), items: const [DropdownMenuItem(value: 'trial', child: Text('trial')), DropdownMenuItem(value: 'active', child: Text('active')), DropdownMenuItem(value: 'past_due', child: Text('past_due')), DropdownMenuItem(value: 'paused', child: Text('paused'))], onChanged: (v) => setLocal(() => status = v ?? 'active'))), const SizedBox(width: 10), Expanded(child: DropdownButtonFormField<String>(initialValue: cycle, decoration: InputDecoration(labelText: _at(context, 'Cycle', 'الدورة', 'Cyclus')), items: const [DropdownMenuItem(value: 'monthly', child: Text('monthly')), DropdownMenuItem(value: 'yearly', child: Text('yearly')), DropdownMenuItem(value: 'manual', child: Text('manual'))], onChanged: (v) => setLocal(() => cycle = v ?? 'monthly')))]), const SizedBox(height: 10),
        TextField(controller: amount, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _at(context, 'Amount EUR', 'المبلغ EUR', 'Bedrag EUR'))),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_at(context, 'Cancel', 'إلغاء', 'Annuleren'))), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_at(context, 'Create', 'إنشاء', 'Aanmaken')))],
    )));
    if (ok != true || farmId == null) return;
    await VetAdminService.instance.createSubscription(farmId: farmId!, planId: planId, status: status, billingCycle: cycle, currency: 'EUR', amount: double.tryParse(amount.text) ?? 0);
    reload();
  }

  Future<void> changeStatus(Map<String, dynamic> row) async {
    var status = '${row['status']}';
    final selected = await showDialog<String>(context: context, builder: (dialogContext) => SimpleDialog(title: Text(_at(context, 'Subscription status', 'حالة الاشتراك', 'Abonnementsstatus')), children: [for (final s in ['trial','active','past_due','paused','cancelled','expired']) RadioListTile<String>(value: s, groupValue: status, title: Text(s), onChanged: (v) => Navigator.pop(dialogContext, v))]));
    if (selected == null) return;
    await VetAdminService.instance.updateSubscription(row['id'].toString(), {'status': selected, if (selected == 'cancelled') 'cancelled_at': DateTime.now().toUtc().toIso8601String()});
    reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(future: future, builder: (context, snapshot) {
    if (snapshot.hasError) return _LoadError(snapshot.error);
    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
    final subscriptions = snapshot.data![0] as List<Map<String, dynamic>>;
    final plans = snapshot.data![1] as List<Map<String, dynamic>>;
    final farms = snapshot.data![2] as List<Map<String, dynamic>>;
    final farmNames = {for (final f in farms) f['id'].toString(): '${f['company_name'] ?? ''} / ${f['farm_name'] ?? ''}'};
    final planNames = {for (final p in plans) p['id'].toString(): '${p['name'] ?? ''}'};
    return _AdminPageFrame(actions: [FilledButton.icon(onPressed: () => create(farms, plans), icon: const Icon(Icons.add_rounded), label: Text(_at(context, 'New subscription', 'اشتراك جديد', 'Nieuw abonnement')))], children: [
      _SectionTitle(icon: Icons.workspace_premium_rounded, title: _at(context, 'Subscriptions & plans', 'الاشتراكات والخطط', 'Abonnementen & plannen'), subtitle: '${subscriptions.length}'), const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, children: [for (final p in plans) Chip(avatar: const Icon(Icons.sell_rounded, size: 17), label: Text('${p['name']} • €${p['monthly_price']}/m • €${p['yearly_price']}/y'))]), const SizedBox(height: 14),
      for (final row in subscriptions) Card(child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.workspace_premium_rounded)),
        title: Text(farmNames[row['farm_id'].toString()] ?? row['farm_id'].toString(), style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text('${planNames[row['plan_id'].toString()] ?? '-'} • ${row['billing_cycle']} • ${row['currency']} ${row['amount']}\n${row['status']} • ${row['current_period_end'] ?? ''}'), isThreeLine: true,
        trailing: IconButton(onPressed: () => changeStatus(row), icon: const Icon(Icons.edit_rounded)), onTap: () => changeStatus(row),
      )),
    ]);
  });
}

class _PaymentsPage extends StatefulWidget {
  const _PaymentsPage({super.key});
  @override
  State<_PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<_PaymentsPage> {
  late Future<List<dynamic>> future = _load();
  Future<List<dynamic>> _load() => Future.wait([VetAdminService.instance.payments(), VetAdminService.instance.farms()]);
  void reload() => setState(() => future = _load());

  Future<void> add(List<Map<String, dynamic>> farms) async {
    String? farmId;
    final amount = TextEditingController();
    final description = TextEditingController();
    String status = 'pending';
    final ok = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setLocal) => AlertDialog(
      title: Text(_at(context, 'Add manual payment', 'إضافة دفعة يدوية', 'Handmatige betaling toevoegen')),
      content: SizedBox(width: 500, child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(initialValue: farmId, decoration: InputDecoration(labelText: _at(context, 'Farm', 'المزرعة', 'Boerderij')), items: [for (final f in farms) DropdownMenuItem(value: f['id'].toString(), child: Text('${f['company_name'] ?? ''} / ${f['farm_name'] ?? ''}'))], onChanged: (v) => setLocal(() => farmId = v)), const SizedBox(height: 10),
        TextField(controller: amount, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _at(context, 'Amount EUR', 'المبلغ EUR', 'Bedrag EUR'))), const SizedBox(height: 10),
        DropdownButtonFormField<String>(initialValue: status, decoration: InputDecoration(labelText: _at(context, 'Status', 'الحالة', 'Status')), items: const [DropdownMenuItem(value: 'pending', child: Text('pending')), DropdownMenuItem(value: 'paid', child: Text('paid')), DropdownMenuItem(value: 'failed', child: Text('failed'))], onChanged: (v) => setLocal(() => status = v ?? 'pending')), const SizedBox(height: 10),
        TextField(controller: description, decoration: InputDecoration(labelText: _at(context, 'Description', 'الوصف', 'Beschrijving'))),
      ])), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_at(context, 'Cancel', 'إلغاء', 'Annuleren'))), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_at(context, 'Save', 'حفظ', 'Opslaan')))],
    )));
    if (ok != true || farmId == null) return;
    await VetAdminService.instance.createPayment(farmId: farmId!, amount: double.tryParse(amount.text) ?? 0, currency: 'EUR', status: status, description: description.text);
    reload();
  }

  Future<void> status(Map<String, dynamic> row, String value) async {
    await VetAdminService.instance.updatePayment(row['id'].toString(), {'status': value, if (value == 'paid') 'paid_at': DateTime.now().toUtc().toIso8601String()});
    reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(future: future, builder: (context, snapshot) {
    if (snapshot.hasError) return _LoadError(snapshot.error);
    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
    final payments = snapshot.data![0] as List<Map<String, dynamic>>;
    final farms = snapshot.data![1] as List<Map<String, dynamic>>;
    final farmNames = {for (final f in farms) f['id'].toString(): '${f['company_name'] ?? ''} / ${f['farm_name'] ?? ''}'};
    return _AdminPageFrame(actions: [FilledButton.icon(onPressed: () => add(farms), icon: const Icon(Icons.add_card_rounded), label: Text(_at(context, 'Add payment', 'إضافة دفعة', 'Betaling toevoegen')))], children: [
      _SectionTitle(icon: Icons.payments_rounded, title: _at(context, 'Payments & invoices', 'المدفوعات والفواتير', 'Betalingen & facturen'), subtitle: '${payments.length}'), const SizedBox(height: 12),
      for (final row in payments) Card(child: ListTile(
        leading: CircleAvatar(child: Icon('${row['status']}' == 'paid' ? Icons.check_rounded : Icons.payments_rounded)),
        title: Text('${row['currency']} ${row['amount']} • ${farmNames[row['farm_id'].toString()] ?? row['farm_id']}', style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text('${row['status']} • ${row['provider']}\n${row['description'] ?? ''}'), isThreeLine: true,
        trailing: PopupMenuButton<String>(onSelected: (v) => status(row, v), itemBuilder: (_) => const [PopupMenuItem(value: 'paid', child: Text('Mark paid')), PopupMenuItem(value: 'pending', child: Text('Mark pending')), PopupMenuItem(value: 'failed', child: Text('Mark failed')), PopupMenuItem(value: 'refunded', child: Text('Refunded'))]),
      )),
    ]);
  });
}

class _AdminsPage extends StatefulWidget {
  const _AdminsPage({super.key});
  @override
  State<_AdminsPage> createState() => _AdminsPageState();
}

class _AdminsPageState extends State<_AdminsPage> {
  late Future<List<dynamic>> future = _load();
  Future<List<dynamic>> _load() => Future.wait([VetAdminService.instance.admins(), VetAdminService.instance.profiles()]);
  void reload() => setState(() => future = _load());

  Future<void> add(List<Map<String, dynamic>> profiles) async {
    String? userId;
    String role = 'support';
    final ok = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setLocal) => AlertDialog(
      title: Text(_at(context, 'Add admin staff member', 'إضافة موظف إدارة', 'Adminmedewerker toevoegen')),
      content: SizedBox(width: 520, child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(initialValue: userId, decoration: InputDecoration(labelText: _at(context, 'Existing user', 'مستخدم موجود', 'Bestaande gebruiker')), items: [for (final p in profiles) DropdownMenuItem(value: p['id'].toString(), child: Text('${p['full_name'] ?? '-'} — ${p['id'].toString().substring(0, 8)}…'))], onChanged: (v) => setLocal(() => userId = v)), const SizedBox(height: 10),
        DropdownButtonFormField<String>(initialValue: role, decoration: InputDecoration(labelText: _at(context, 'Role', 'الصلاحية', 'Rol')), items: const [DropdownMenuItem(value: 'admin', child: Text('Admin')), DropdownMenuItem(value: 'support', child: Text('Support')), DropdownMenuItem(value: 'billing', child: Text('Billing')), DropdownMenuItem(value: 'operations', child: Text('Operations'))], onChanged: (v) => setLocal(() => role = v ?? 'support')),
      ])), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_at(context, 'Cancel', 'إلغاء', 'Annuleren'))), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_at(context, 'Add', 'إضافة', 'Toevoegen')))],
    )));
    if (ok != true || userId == null) return;
    await VetAdminService.instance.upsertAdmin(userId: userId!, role: role, active: true);
    reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(future: future, builder: (context, snapshot) {
    if (snapshot.hasError) return _LoadError(snapshot.error);
    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
    final admins = snapshot.data![0] as List<Map<String, dynamic>>;
    final profiles = snapshot.data![1] as List<Map<String, dynamic>>;
    final names = {for (final p in profiles) p['id'].toString(): '${p['full_name'] ?? ''}'};
    return _AdminPageFrame(actions: [FilledButton.icon(onPressed: () => add(profiles), icon: const Icon(Icons.person_add_alt_1_rounded), label: Text(_at(context, 'Add staff', 'إضافة موظف', 'Medewerker toevoegen')))], children: [
      _SectionTitle(icon: Icons.admin_panel_settings_rounded, title: _at(context, 'Admin roles & permissions', 'صلاحيات فريق الإدارة', 'Adminrollen & rechten'), subtitle: '${admins.length}'), const SizedBox(height: 12),
      for (final row in admins) Card(child: SwitchListTile(
        value: row['active'] == true,
        onChanged: '${row['role']}' == 'super_admin' ? null : (v) async { await VetAdminService.instance.upsertAdmin(userId: row['user_id'].toString(), role: row['role'].toString(), active: v); reload(); },
        secondary: CircleAvatar(child: Icon('${row['role']}' == 'super_admin' ? Icons.security_rounded : Icons.admin_panel_settings_rounded)),
        title: Text('${names[row['user_id'].toString()] ?? row['user_id']} • ${row['role']}', style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text('ID: ${row['user_id']}'),
      )),
    ]);
  });
}

class _AuditPage extends StatelessWidget {
  const _AuditPage({super.key});
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(future: VetAdminService.instance.auditLog(), builder: (context, snapshot) {
    if (snapshot.hasError) return _LoadError(snapshot.error);
    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
    final rows = snapshot.data!;
    return _AdminPageFrame(children: [
      _SectionTitle(icon: Icons.history_rounded, title: _at(context, 'Admin audit trail', 'سجل كل عمليات الإدارة', 'Admin-audittrail'), subtitle: '${rows.length}'), const SizedBox(height: 12),
      for (final row in rows) Card(child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.history_rounded)),
        title: Text('${row['action']} • ${row['table_name']}', style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text('${row['record_id'] ?? ''}\n${row['created_at'] ?? ''}\n${row['actor_user_id'] ?? ''}'), isThreeLine: true,
      )),
    ]);
  });
}

class _SystemPage extends StatelessWidget {
  const _SystemPage();
  @override
  Widget build(BuildContext context) => _AdminPageFrame(children: [
    _SectionTitle(icon: Icons.settings_rounded, title: _at(context, 'Admin system settings', 'إعدادات نظام الإدارة', 'Admin-systeeminstellingen'), subtitle: 'Vet AI'), const SizedBox(height: 12),
    Card(child: ListTile(leading: const Icon(Icons.language_rounded), title: Text(_at(context, 'Language', 'اللغة', 'Taal')), subtitle: Text(_at(context, 'Vet AI supports the full global language list. Other languages are translated through the protected Vet AI translation service.', 'لوحة التحكم تدعم قائمة لغات Vet AI كاملة، وباقي اللغات يتم تجهيز ترجمتها من خدمة Vet AI المحمية.', 'Het dashboard ondersteunt de volledige Vet AI-taallijst. Andere talen worden vertaald via de beveiligde Vet AI-vertaalservice.')), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => showVetLanguagePicker(context))),
    Card(child: ListTile(leading: const Icon(Icons.security_rounded, color: VetColors.green), title: Text(_at(context, 'Server-enforced admin access', 'صلاحيات الإدارة محمية من السيرفر', 'Server-afgedwongen admintoegang')), subtitle: Text(_at(context, 'Admin pages are not unlocked by a local button. The authenticated account must be authorized by Supabase.', 'لا يمكن فتح لوحة الإدارة بزر مخفي؛ لازم الحساب يكون مصرح له من Supabase نفسه.', 'Adminpagina’s worden niet via een lokale knop ontgrendeld; het account moet door Supabase zijn geautoriseerd.')))),
    Card(child: ListTile(leading: const Icon(Icons.logout_rounded, color: VetColors.red), title: Text(_at(context, 'Sign out', 'تسجيل الخروج', 'Uitloggen')), onTap: () => VetBackend.instance.signOut())),
  ]);
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 44, height: 44, decoration: BoxDecoration(color: VetColors.surface3, borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: VetColors.green)),
    const SizedBox(width: 11),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)), Text(subtitle, style: const TextStyle(color: VetColors.muted, fontSize: 12))])),
  ]);
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

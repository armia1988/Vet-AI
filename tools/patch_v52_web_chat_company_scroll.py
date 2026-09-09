from pathlib import Path

# V52 fixes three web-admin issues reported from iPhone Safari:
# 1) touch scrolling that can get stuck,
# 2) company detail tabs that look like blank white pages when no rows exist,
# 3) direct access from a company to account/sensor/animal/support management.

# ---------------------------------------------------------------------------
# 1) Stable touch/mouse/stylus scrolling for Flutter Web on mobile browsers.
# ---------------------------------------------------------------------------
p = Path('lib/admin/admin_web_root.dart')
s = p.read_text(encoding='utf-8')
if "import 'dart:ui' show PointerDeviceKind;" not in s:
    s = s.replace("import 'dart:async';\n", "import 'dart:async';\nimport 'dart:ui' show PointerDeviceKind;\n", 1)

if 'class _VetAdminScrollBehavior extends MaterialScrollBehavior' not in s:
    marker = 'class _AdminWebShell extends StatefulWidget {'
    behavior = r'''class _VetAdminScrollBehavior extends MaterialScrollBehavior {
  const _VetAdminScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.unknown,
      };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}

'''
    if marker not in s:
        raise SystemExit('V52: admin web shell marker missing')
    s = s.replace(marker, behavior + marker, 1)

if 'scrollBehavior: const _VetAdminScrollBehavior(),' not in s:
    anchor = "        theme: buildVetTheme(),\n"
    if anchor not in s:
        raise SystemExit('V52: MaterialApp theme anchor missing')
    s = s.replace(anchor, anchor + "        scrollBehavior: const _VetAdminScrollBehavior(),\n", 1)

p.write_text(s, encoding='utf-8')

# ---------------------------------------------------------------------------
# 2) Replace the old static company detail page with a live, reloadable page.
#    Empty tabs now show a useful empty-state instead of a blank page.
# ---------------------------------------------------------------------------
p = Path('lib/admin/admin_company_center.dart')
s = p.read_text(encoding='utf-8')

imports_anchor = "import 'admin_service.dart';\n"
extra_imports = [
    "import 'admin_account_center.dart';\n",
    "import 'admin_animal_center.dart';\n",
    "import 'admin_sensor_center.dart';\n",
    "import 'admin_support_center.dart';\n",
]
for item in extra_imports:
    if item not in s:
        s = s.replace(imports_anchor, imports_anchor + item, 1)

start_marker = 'class VetAdminCompanyDetail extends '
end_marker = 'class _CompanyData {'
start = s.find(start_marker)
end = s.find(end_marker)
if start < 0 or end < 0 or end <= start:
    raise SystemExit('V52: company detail class markers missing')

new_detail = r'''class VetAdminCompanyDetail extends StatefulWidget {
  const VetAdminCompanyDetail({
    super.key,
    required this.farm,
    required this.data,
    required this.onFarmEdited,
  });

  final Map<String, dynamic> farm;
  final _CompanyData data;
  final VoidCallback onFarmEdited;

  @override
  State<VetAdminCompanyDetail> createState() => _VetAdminCompanyDetailState();
}

class _VetAdminCompanyDetailState extends State<VetAdminCompanyDetail> {
  final admin = VetAdminService.instance;
  late Future<_CompanyData> future;

  @override
  void initState() {
    super.initState();
    future = _load();
  }

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

  void reload() {
    if (!mounted) return;
    setState(() => future = _load());
    widget.onFarmEdited();
  }

  Future<void> _openManager(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) reload();
  }

  void _manage(String value) {
    switch (value) {
      case 'accounts':
        _openManager(const VetAdminAccountCenter());
      case 'sensors':
        _openManager(const VetAdminSensorCenter());
      case 'animals':
        _openManager(const VetAdminAnimalCenter());
      case 'support':
        _openManager(const VetAdminSupportCenter());
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_CompanyData>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              appBar: AppBar(title: Text('${widget.farm['company_name'] ?? ''}')),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded, color: VetColors.red, size: 40),
                      const SizedBox(height: 10),
                      Text('${snapshot.error}', textAlign: TextAlign.center, style: const TextStyle(color: VetColors.red)),
                      const SizedBox(height: 12),
                      FilledButton.icon(onPressed: reload, icon: const Icon(Icons.refresh_rounded), label: Text(_ct(context, 'Retry', 'إعادة المحاولة', 'Opnieuw proberen'))),
                    ],
                  ),
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return Scaffold(
              appBar: AppBar(title: Text('${widget.farm['company_name'] ?? ''}')),
              body: const Center(child: CircularProgressIndicator()),
            );
          }
          return _page(context, snapshot.data!);
        },
      );

  Widget _page(BuildContext context, _CompanyData data) {
    final id = widget.farm['id'].toString();
    final farm = data.farms.where((e) => e['id'].toString() == id).firstOrNull ?? widget.farm;
    final sensors = data.sensors.where((e) => e['farm_id'].toString() == id).toList();
    final animals = data.animals.where((e) => e['farm_id'].toString() == id).toList();
    final alerts = data.alerts.where((e) => e['farm_id'].toString() == id).take(50).toList();
    final support = data.support.where((e) => e['farm_id'].toString() == id).toList();
    final subscriptions = data.subscriptions.where((e) => e['farm_id'].toString() == id).toList();
    final payments = data.payments.where((e) => e['farm_id'].toString() == id).toList();
    final owner = data.profiles.where((e) => e['id'].toString() == farm['owner_id'].toString()).firstOrNull;

    return DefaultTabController(
      length: 7,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${farm['company_name'] ?? ''} / ${farm['farm_name'] ?? ''}'),
          actions: [
            IconButton(onPressed: reload, tooltip: _ct(context, 'Refresh', 'تحديث', 'Vernieuwen'), icon: const Icon(Icons.refresh_rounded)),
            PopupMenuButton<String>(
              tooltip: _ct(context, 'Manage customer', 'إدارة العميل', 'Klant beheren'),
              onSelected: _manage,
              itemBuilder: (_) => [
                PopupMenuItem(value: 'accounts', child: ListTile(leading: const Icon(Icons.manage_accounts_rounded), title: Text(_ct(context, 'Accounts & staff', 'الحسابات والموظفون', 'Accounts & medewerkers')))),
                PopupMenuItem(value: 'sensors', child: ListTile(leading: const Icon(Icons.sensors_rounded), title: Text(_ct(context, 'Sensors & devices', 'الحساسات والأجهزة', 'Sensoren & apparaten')))),
                PopupMenuItem(value: 'animals', child: ListTile(leading: const Icon(Icons.pets_rounded), title: Text(_ct(context, 'Animals', 'الحيوانات', 'Dieren')))),
                PopupMenuItem(value: 'support', child: ListTile(leading: const Icon(Icons.support_agent_rounded), title: Text(_ct(context, 'Support inbox', 'صندوق الدعم', 'Support-inbox')))),
              ],
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: _ct(context, 'Overview', 'نظرة عامة', 'Overzicht')),
              Tab(text: _ct(context, 'Sensors', 'الحساسات', 'Sensoren')),
              Tab(text: _ct(context, 'Animals', 'الحيوانات', 'Dieren')),
              Tab(text: _ct(context, 'Alerts', 'الإنذارات', 'Meldingen')),
              Tab(text: _ct(context, 'Support', 'الدعم', 'Support')),
              Tab(text: _ct(context, 'Subscription', 'الاشتراك', 'Abonnement')),
              Tab(text: _ct(context, 'Payments', 'المدفوعات', 'Betalingen')),
            ],
          ),
        ),
        body: TabBarView(
          physics: const ClampingScrollPhysics(),
          children: [
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
            _managedRows(
              context,
              rows: sensors,
              icon: Icons.sensors_rounded,
              title: _ct(context, 'Customer sensors', 'حساسات العميل', 'Klantsensoren'),
              subtitle: _ct(context, 'Add, edit, move, enable or disable this customer’s sensors.', 'أضف وعدّل وانقل وفعّل أو افصل حساسات العميل.', 'Voeg sensoren toe, bewerk of verplaats ze en schakel ze in of uit.'),
              button: _ct(context, 'Manage sensors', 'إدارة الحساسات', 'Sensoren beheren'),
              empty: _ct(context, 'No sensors have been added to this customer yet.', 'لسه مفيش حساسات مضافة للعميل ده.', 'Er zijn nog geen sensoren voor deze klant.'),
              onManage: () => _openManager(const VetAdminSensorCenter()),
              itemTitle: (e) => '${e['display_name'] ?? e['device_uid'] ?? '-'}',
              itemSubtitle: (e) => '${e['section_name'] ?? '-'} • ${e['active'] == true ? 'active' : 'disabled'} • ${e['last_seen_at'] ?? '-'}',
            ),
            _managedRows(
              context,
              rows: animals,
              icon: Icons.pets_rounded,
              title: _ct(context, 'Customer animals', 'حيوانات العميل', 'Dieren van klant'),
              subtitle: _ct(context, 'View and manage every animal linked to this farm.', 'اعرض وتحكم في كل الحيوانات المرتبطة بالمزرعة.', 'Bekijk en beheer alle dieren die aan deze boerderij zijn gekoppeld.'),
              button: _ct(context, 'Manage animals', 'إدارة الحيوانات', 'Dieren beheren'),
              empty: _ct(context, 'No animals have been added to this farm yet.', 'لسه مفيش حيوانات مضافة للمزرعة دي.', 'Er zijn nog geen dieren aan deze boerderij toegevoegd.'),
              onManage: () => _openManager(const VetAdminAnimalCenter()),
              itemTitle: (e) => '${e['name'] ?? e['external_id'] ?? '-'}',
              itemSubtitle: (e) => '${e['species'] ?? ''} • ${e['breed'] ?? ''} • ${e['active'] == true ? 'active' : 'inactive'}',
            ),
            _simpleRows(
              context,
              rows: alerts,
              icon: Icons.warning_rounded,
              empty: _ct(context, 'No alerts for this farm.', 'مفيش إنذارات للمزرعة دي.', 'Geen meldingen voor deze boerderij.'),
              itemTitle: (e) => '${e['title'] ?? '-'}',
              itemSubtitle: (e) => '${e['risk'] ?? ''} • ${e['details'] ?? ''} • ${e['created_at'] ?? ''}',
            ),
            _managedRows(
              context,
              rows: support,
              icon: Icons.support_agent_rounded,
              title: _ct(context, 'Customer support', 'دعم العميل', 'Klantensupport'),
              subtitle: _ct(context, 'Open the live WhatsApp-style support conversation and answer the customer.', 'افتح محادثة الدعم المباشرة ورد على العميل.', 'Open het live supportgesprek en antwoord de klant.'),
              button: _ct(context, 'Open support inbox', 'فتح صندوق الدعم', 'Support-inbox openen'),
              empty: _ct(context, 'No support conversations for this farm yet.', 'مفيش محادثات دعم للمزرعة دي لسه.', 'Nog geen supportgesprekken voor deze boerderij.'),
              onManage: () => _openManager(const VetAdminSupportCenter()),
              itemTitle: (e) => '${e['subject'] ?? 'Support'}',
              itemSubtitle: (e) => '${e['status'] ?? '-'} • ${e['priority'] ?? 'normal'} • unread ${e['unread_by_admin'] ?? 0}',
            ),
            _simpleRows(
              context,
              rows: subscriptions,
              icon: Icons.workspace_premium_rounded,
              empty: _ct(context, 'No subscription is linked to this farm yet.', 'مفيش اشتراك مربوط بالمزرعة دي لسه.', 'Er is nog geen abonnement aan deze boerderij gekoppeld.'),
              itemTitle: (e) => '${e['status'] ?? '-'}',
              itemSubtitle: (e) => '${e['billing_cycle'] ?? '-'} • ${e['currency'] ?? ''} ${e['amount'] ?? ''} • ${e['current_period_end'] ?? ''}',
            ),
            _simpleRows(
              context,
              rows: payments,
              icon: Icons.payments_rounded,
              empty: _ct(context, 'No payments recorded for this farm.', 'مفيش مدفوعات مسجلة للمزرعة دي.', 'Geen betalingen geregistreerd voor deze boerderij.'),
              itemTitle: (e) => '${e['currency'] ?? ''} ${e['amount'] ?? '-'}',
              itemSubtitle: (e) => '${e['status'] ?? '-'} • ${e['provider'] ?? '-'} • ${e['description'] ?? ''}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailList(BuildContext context, List<Widget> rows) => ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
        padding: const EdgeInsets.all(18),
        children: rows,
      );

  Widget _line(String label, dynamic value) => Card(
        child: ListTile(
          title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('${value ?? '-'}'),
        ),
      );

  Widget _managedRows(
    BuildContext context, {
    required List<Map<String, dynamic>> rows,
    required IconData icon,
    required String title,
    required String subtitle,
    required String button,
    required String empty,
    required VoidCallback onManage,
    required String Function(Map<String, dynamic>) itemTitle,
    required String Function(Map<String, dynamic>) itemSubtitle,
  }) =>
      ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [Icon(icon, color: VetColors.green), const SizedBox(width: 9), Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)))]),
                  const SizedBox(height: 6),
                  Text(subtitle, style: const TextStyle(color: VetColors.muted, height: 1.35)),
                  const SizedBox(height: 12),
                  FilledButton.icon(onPressed: onManage, icon: const Icon(Icons.tune_rounded), label: Text(button)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            _emptyState(context, icon: icon, text: empty, button: button, onPressed: onManage)
          else
            for (final row in rows)
              Card(
                child: ListTile(
                  onTap: onManage,
                  leading: CircleAvatar(child: Icon(icon)),
                  title: Text(itemTitle(row), style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text(itemSubtitle(row)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                ),
              ),
          const SizedBox(height: 90),
        ],
      );

  Widget _simpleRows(
    BuildContext context, {
    required List<Map<String, dynamic>> rows,
    required IconData icon,
    required String empty,
    required String Function(Map<String, dynamic>) itemTitle,
    required String Function(Map<String, dynamic>) itemSubtitle,
  }) =>
      ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
        padding: const EdgeInsets.all(18),
        children: [
          if (rows.isEmpty)
            _emptyState(context, icon: icon, text: empty)
          else
            for (final row in rows)
              Card(
                child: ListTile(
                  leading: CircleAvatar(child: Icon(icon)),
                  title: Text(itemTitle(row), style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text(itemSubtitle(row)),
                ),
              ),
          const SizedBox(height: 90),
        ],
      );

  Widget _emptyState(
    BuildContext context, {
    required IconData icon,
    required String text,
    String? button,
    VoidCallback? onPressed,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 70, horizontal: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(radius: 34, backgroundColor: VetColors.softGreen, child: Icon(icon, size: 34, color: VetColors.green)),
                const SizedBox(height: 14),
                Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: VetColors.muted)),
                if (button != null && onPressed != null) ...[
                  const SizedBox(height: 14),
                  FilledButton.icon(onPressed: onPressed, icon: const Icon(Icons.add_rounded), label: Text(button)),
                ],
              ],
            ),
          ),
        ),
      );
}

'''

s = s[:start] + new_detail + s[end:]
p.write_text(s, encoding='utf-8')

print('Vet AI V52 applied: stable mobile scrolling, live company tabs, direct customer management')

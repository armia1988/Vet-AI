import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/vet_locale.dart';
import '../theme/app_theme.dart';
import 'admin_service.dart';
import 'admin_staff_center.dart';

String _act(BuildContext context, String en, String ar, String nl) =>
    VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

class VetAdminAccountCenter extends StatelessWidget {
  const VetAdminAccountCenter({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Column(children: [
          Material(
            color: VetColors.surface2,
            child: TabBar(
              isScrollable: true,
              tabs: [
                Tab(icon: const Icon(Icons.person_add_alt_1_rounded), text: _act(context, 'Accounts & invitations', 'الحسابات والدعوات', 'Accounts & uitnodigingen')),
                Tab(icon: const Icon(Icons.admin_panel_settings_rounded), text: _act(context, 'Staff & permissions', 'الموظفون والصلاحيات', 'Medewerkers & rechten')),
              ],
            ),
          ),
          const Expanded(child: TabBarView(children: [VetAdminAccountsInvitePage(), VetAdminStaffCenter()])),
        ]),
      );
}

class VetAdminAccountsInvitePage extends StatefulWidget {
  const VetAdminAccountsInvitePage({super.key});
  @override
  State<VetAdminAccountsInvitePage> createState() => _VetAdminAccountsInvitePageState();
}

class _VetAdminAccountsInvitePageState extends State<VetAdminAccountsInvitePage> {
  final admin = VetAdminService.instance;
  late Future<_AccountData> future = _load();

  Future<_AccountData> _load() async {
    final values = await Future.wait([
      admin.profiles(),
      admin.farms(),
      admin.admins(),
      admin.client.from('admin_account_invites').select().order('created_at', ascending: false).limit(200),
    ]);
    return _AccountData(
      profiles: values[0] as List<Map<String, dynamic>>,
      farms: values[1] as List<Map<String, dynamic>>,
      admins: values[2] as List<Map<String, dynamic>>,
      invites: (values[3] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
    );
  }

  void reload() => setState(() => future = _load());

  Future<void> _newInvite(_AccountData data) async {
    final email = TextEditingController();
    final fullName = TextEditingController();
    final phone = TextEditingController();
    final language = TextEditingController(text: 'en');
    final company = TextEditingController();
    final farmName = TextEditingController();
    final country = TextEditingController();
    final region = TextEditingController();
    String kind = 'customer';
    String adminRole = 'admin';
    String memberRole = 'worker';
    String? farmId;
    bool createFarm = true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(_act(context, 'Create account / invitation', 'إنشاء حساب / دعوة', 'Account / uitnodiging maken')),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  decoration: InputDecoration(labelText: _act(context, 'Account type', 'نوع الحساب', 'Accounttype')),
                  items: [
                    DropdownMenuItem(value: 'customer', child: Text(_act(context, 'Customer / farm owner', 'عميل / صاحب مزرعة', 'Klant / boerderijeigenaar'))),
                    DropdownMenuItem(value: 'worker', child: Text(_act(context, 'Farm employee', 'موظف مزرعة', 'Boerderijmedewerker'))),
                    const DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    const DropdownMenuItem(value: 'support', child: Text('Support')),
                    const DropdownMenuItem(value: 'operations', child: Text('Operations')),
                    const DropdownMenuItem(value: 'billing', child: Text('Billing')),
                  ],
                  onChanged: (v) => setLocal(() {
                    kind = v ?? 'customer';
                    if (kind != 'customer') createFarm = false;
                  }),
                ),
                const SizedBox(height: 10),
                TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: _act(context, 'Email address', 'البريد الإلكتروني', 'E-mailadres'))),
                const SizedBox(height: 10),
                TextField(controller: fullName, decoration: InputDecoration(labelText: _act(context, 'Full name', 'الاسم الكامل', 'Volledige naam'))),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: phone, decoration: InputDecoration(labelText: _act(context, 'Phone', 'الهاتف', 'Telefoon')))),
                  const SizedBox(width: 10),
                  SizedBox(width: 150, child: TextField(controller: language, decoration: InputDecoration(labelText: _act(context, 'Language', 'اللغة', 'Taal'), hintText: 'ar / en / nl'))),
                ]),
                if (kind == 'admin') ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: adminRole,
                    decoration: InputDecoration(labelText: _act(context, 'Admin role', 'صلاحية الإدارة', 'Adminrol')),
                    items: const [
                      DropdownMenuItem(value: 'super_admin', child: Text('Super Admin')),
                      DropdownMenuItem(value: 'admin', child: Text('Admin')),
                      DropdownMenuItem(value: 'operations', child: Text('Operations')),
                      DropdownMenuItem(value: 'support', child: Text('Support')),
                      DropdownMenuItem(value: 'billing', child: Text('Billing')),
                    ],
                    onChanged: (v) => setLocal(() => adminRole = v ?? 'admin'),
                  ),
                ],
                if (kind == 'worker') ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: farmId,
                    decoration: InputDecoration(labelText: _act(context, 'Company / farm', 'الشركة / المزرعة', 'Bedrijf / boerderij')),
                    items: [for (final f in data.farms) DropdownMenuItem(value: f['id'].toString(), child: Text('${f['company_name'] ?? ''} / ${f['farm_name'] ?? ''}'))],
                    onChanged: (v) => setLocal(() => farmId = v),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: memberRole,
                    decoration: InputDecoration(labelText: _act(context, 'Farm role', 'وظيفة المزرعة', 'Boerderijrol')),
                    items: const [
                      DropdownMenuItem(value: 'manager', child: Text('Manager')),
                      DropdownMenuItem(value: 'veterinarian', child: Text('Veterinarian')),
                      DropdownMenuItem(value: 'supervisor', child: Text('Supervisor')),
                      DropdownMenuItem(value: 'worker', child: Text('Worker')),
                    ],
                    onChanged: (v) => setLocal(() => memberRole = v ?? 'worker'),
                  ),
                ],
                if (kind == 'customer') ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: createFarm,
                    onChanged: (v) => setLocal(() => createFarm = v),
                    title: Text(_act(context, 'Create the customer company/farm when they accept', 'إنشاء شركة/مزرعة للعميل عند قبول الدعوة', 'Bedrijf/boerderij maken wanneer de klant accepteert')),
                  ),
                  if (createFarm) ...[
                    TextField(controller: company, decoration: InputDecoration(labelText: _act(context, 'Company name', 'اسم الشركة', 'Bedrijfsnaam'))),
                    const SizedBox(height: 10),
                    TextField(controller: farmName, decoration: InputDecoration(labelText: _act(context, 'Farm name', 'اسم المزرعة', 'Boerderijnaam'))),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: TextField(controller: country, decoration: InputDecoration(labelText: _act(context, 'Country', 'الدولة', 'Land')))),
                      const SizedBox(width: 10),
                      Expanded(child: TextField(controller: region, decoration: InputDecoration(labelText: _act(context, 'Region', 'المنطقة', 'Regio')))),
                    ]),
                  ],
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_act(context, 'Cancel', 'إلغاء', 'Annuleren'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_act(context, 'Create invitation', 'إنشاء الدعوة', 'Uitnodiging maken'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (email.text.trim().isEmpty || (kind == 'worker' && farmId == null) || (kind == 'customer' && createFarm && farmName.text.trim().isEmpty)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_act(context, 'Complete the required fields.', 'كمّل البيانات المطلوبة.', 'Vul de verplichte velden in.'))));
      return;
    }
    try {
      final raw = await admin.client.rpc('admin_create_account_invite', params: {
        'p_email': email.text.trim(),
        'p_full_name': fullName.text.trim(),
        'p_phone': phone.text.trim(),
        'p_preferred_language': language.text.trim().isEmpty ? 'en' : language.text.trim(),
        'p_kind': kind,
        'p_admin_role': kind == 'admin' ? adminRole : null,
        'p_permissions': <String, bool>{},
        'p_farm_id': kind == 'worker' ? farmId : null,
        'p_member_role': kind == 'worker' ? memberRole : null,
        'p_create_farm': kind == 'customer' && createFarm,
        'p_company_name': company.text.trim(),
        'p_farm_name': farmName.text.trim(),
        'p_country': country.text.trim(),
        'p_region': region.text.trim(),
      });
      final result = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      final token = '${result['token'] ?? ''}';
      if (token.isEmpty) throw StateError('Invite token missing');
      final base = Uri.base.replace(queryParameters: <String, String>{
        'invite': token,
        'email': email.text.trim().toLowerCase(),
      }).toString();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_act(context, 'Account invitation ready', 'دعوة الحساب جاهزة', 'Accountuitnodiging klaar')),
          content: SizedBox(
            width: 680,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_act(context, 'Send this private link to the person. They set their own password; Vet AI applies the customer/staff permissions automatically after sign-in.', 'ابعت الرابط الخاص ده للشخص. هو بيحدد الباسورد بنفسه، وبعد الدخول Vet AI يطبق صلاحيات العميل/الموظف تلقائيًا.', 'Stuur deze privékoppeling naar de persoon. Die stelt zelf een wachtwoord in; Vet AI past daarna automatisch de juiste rechten toe.')),
              const SizedBox(height: 12),
              Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: VetColors.surface2, borderRadius: BorderRadius.circular(12), border: Border.all(color: VetColors.border)), child: SelectableText(base)),
            ]),
          ),
          actions: [
            OutlinedButton.icon(onPressed: () async { await Clipboard.setData(ClipboardData(text: base)); if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(_act(dialogContext, 'Link copied', 'تم نسخ الرابط', 'Link gekopieerd')))); }, icon: const Icon(Icons.copy_rounded), label: Text(_act(context, 'Copy link', 'نسخ الرابط', 'Link kopiëren'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext), child: Text(_act(context, 'Done', 'تم', 'Klaar'))),
          ],
        ),
      );
      reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_act(context, 'Could not create invitation', 'تعذر إنشاء الدعوة', 'Uitnodiging kon niet worden gemaakt')}: $e'), backgroundColor: VetColors.red));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_AccountData>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('${snapshot.error}', style: const TextStyle(color: VetColors.red)));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!;
          final adminByUser = {for (final a in data.admins) a['user_id'].toString(): a};
          final pending = data.invites.where((e) => e['accepted_at'] == null).toList();
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_act(context, 'All Vet AI accounts', 'كل حسابات Vet AI', 'Alle Vet AI-accounts'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(_act(context, 'Create customer, farm employee, support, billing, operations or admin access from one place.', 'أنشئ حساب عميل أو موظف مزرعة أو دعم أو فوترة أو عمليات أو أدمن من مكان واحد.', 'Maak klant-, boerderijmedewerker-, support-, billing-, operations- of admin-toegang op één plek.'), style: const TextStyle(color: VetColors.muted)),
                ])),
                FilledButton.icon(onPressed: () => _newInvite(data), icon: const Icon(Icons.person_add_alt_1_rounded), label: Text(_act(context, 'Create account', 'إنشاء حساب', 'Account maken'))),
              ]),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Chip(avatar: const Icon(Icons.people_alt_rounded, size: 17), label: Text('${data.profiles.length} ${_act(context, 'users', 'مستخدم', 'gebruikers')}')),
                Chip(avatar: const Icon(Icons.admin_panel_settings_rounded, size: 17), label: Text('${data.admins.length} ${_act(context, 'admin/staff', 'إدارة/موظف', 'admin/medewerkers')}')),
                Chip(avatar: const Icon(Icons.mail_outline_rounded, size: 17), label: Text('${pending.length} ${_act(context, 'pending invitations', 'دعوة معلقة', 'open uitnodigingen')}')),
              ]),
              const SizedBox(height: 14),
              if (pending.isNotEmpty) ...[
                Text(_act(context, 'Pending invitations', 'الدعوات المعلقة', 'Open uitnodigingen'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                const SizedBox(height: 8),
                for (final invite in pending)
                  Card(child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.mark_email_unread_rounded)),
                    title: Text('${invite['full_name'] ?? invite['email']}', style: const TextStyle(fontWeight: FontWeight.w900)),
                    subtitle: Text('${invite['email']} • ${invite['kind']} • ${_act(context, 'expires', 'تنتهي', 'verloopt')} ${invite['expires_at'] ?? '-'}'),
                  )),
                const SizedBox(height: 16),
              ],
              Text(_act(context, 'Existing accounts', 'الحسابات الموجودة', 'Bestaande accounts'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
              const SizedBox(height: 8),
              for (final p in data.profiles)
                Card(child: ListTile(
                  leading: CircleAvatar(child: Icon(adminByUser.containsKey(p['id'].toString()) ? Icons.admin_panel_settings_rounded : Icons.person_rounded)),
                  title: Text('${p['full_name'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text('${p['phone'] ?? '-'} • ${p['preferred_language'] ?? '-'} • ${p['account_status'] ?? 'active'}'),
                  trailing: adminByUser.containsKey(p['id'].toString()) ? Chip(label: Text('${adminByUser[p['id'].toString()]?['role']}')) : null,
                )),
            ],
          );
        },
      );
}

class _AccountData {
  const _AccountData({required this.profiles, required this.farms, required this.admins, required this.invites});
  final List<Map<String, dynamic>> profiles;
  final List<Map<String, dynamic>> farms;
  final List<Map<String, dynamic>> admins;
  final List<Map<String, dynamic>> invites;
}

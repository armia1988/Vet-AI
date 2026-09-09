import 'package:flutter/material.dart';

import '../i18n/vet_locale.dart';
import '../theme/app_theme.dart';
import 'admin_service.dart';

String _uct(BuildContext context, String en, String ar, String nl) =>
    VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

class VetAdminAccountControlV2 extends StatefulWidget {
  const VetAdminAccountControlV2({super.key});

  @override
  State<VetAdminAccountControlV2> createState() => _VetAdminAccountControlV2State();
}

class _VetAdminAccountControlV2State extends State<VetAdminAccountControlV2> {
  final admin = VetAdminService.instance;
  final search = TextEditingController();
  late Future<_AccountControlData> future = _load();

  static const permissions = <String>[
    'farms',
    'customers',
    'animals',
    'sensors',
    'alerts',
    'notifications',
    'support',
    'billing',
    'audit',
    'global_search',
    'reports',
    'system',
    'manage_admins',
  ];

  Future<_AccountControlData> _load() async {
    final core = await Future.wait<List<Map<String, dynamic>>>([
      admin.profiles(),
      admin.admins(),
    ]);
    final rawAuth = await admin.client.rpc('admin_auth_directory');
    final authRows = rawAuth is List
        ? rawAuth.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];
    return _AccountControlData(
      profiles: core[0],
      admins: core[1],
      authUsers: authRows,
    );
  }

  void reload() {
    admin.invalidateCache();
    setState(() => future = _load());
  }

  Future<Map<String, dynamic>> _function(Map<String, dynamic> body) async {
    final response = await admin.client.functions.invoke(
      'admin-user-management',
      body: body,
    );
    final raw = response.data;
    if (raw is! Map) throw StateError('Invalid server response');
    final result = Map<String, dynamic>.from(raw);
    if (result['ok'] != true) {
      throw StateError('${result['error'] ?? 'Account operation failed'}');
    }
    return result;
  }

  Map<String, dynamic>? _authFor(_AccountControlData data, String id) {
    for (final row in data.authUsers) {
      if ('${row['user_id']}' == id) return row;
    }
    return null;
  }

  Map<String, dynamic>? _adminFor(_AccountControlData data, String id) {
    for (final row in data.admins) {
      if ('${row['user_id']}' == id) return row;
    }
    return null;
  }

  String _roleLabel(BuildContext context, String role) => switch (role) {
        'customer' => _uct(context, 'Customer — app only', 'عميل — البرنامج فقط', 'Klant — alleen app'),
        'manager' => _uct(context, 'Manager', 'مدير', 'Manager'),
        'assistant_manager' => _uct(context, 'Assistant manager', 'مساعد مدير', 'Assistent-manager'),
        'super_admin' => 'Super Admin',
        'admin' => 'Admin',
        'support' => _uct(context, 'Support', 'دعم', 'Support'),
        'operations' => _uct(context, 'Operations', 'تشغيل', 'Operations'),
        'billing' => _uct(context, 'Billing', 'فوترة', 'Facturering'),
        _ => role,
      };

  String _permissionLabel(BuildContext context, String p) => switch (p) {
        'farms' => _uct(context, 'Companies & farms', 'الشركات والمزارع', 'Bedrijven & boerderijen'),
        'customers' => _uct(context, 'Customers', 'العملاء', 'Klanten'),
        'animals' => _uct(context, 'Animals', 'الحيوانات', 'Dieren'),
        'sensors' => _uct(context, 'Sensors', 'الحساسات', 'Sensoren'),
        'alerts' => _uct(context, 'Alerts', 'الإنذارات', 'Meldingen'),
        'notifications' => _uct(context, 'Notifications', 'الإشعارات', 'Notificaties'),
        'support' => _uct(context, 'Support', 'الدعم', 'Support'),
        'billing' => _uct(context, 'Billing', 'الفوترة', 'Facturering'),
        'audit' => _uct(context, 'Audit log', 'سجل العمليات', 'Auditlog'),
        'global_search' => _uct(context, 'Global search', 'البحث الشامل', 'Globaal zoeken'),
        'reports' => _uct(context, 'Reports', 'التقارير', 'Rapporten'),
        'system' => _uct(context, 'System', 'النظام', 'Systeem'),
        'manage_admins' => _uct(context, 'Manage accounts', 'إدارة الحسابات', 'Accounts beheren'),
        _ => p,
      };

  Future<void> _createLogin() async {
    final email = TextEditingController();
    final password = TextEditingController();
    final name = TextEditingController();
    final phone = TextEditingController();
    final language = TextEditingController(text: 'en');
    var kind = 'customer';
    var obscure = true;
    final selected = <String, bool>{for (final p in permissions) p: false};

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(_uct(context, 'Create login account now', 'إنشاء حساب دخول الآن', 'Nu loginaccount maken')),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  decoration: InputDecoration(labelText: _uct(context, 'Account type', 'نوع الحساب', 'Accounttype')),
                  items: [
                    DropdownMenuItem(value: 'customer', child: Text(_roleLabel(context, 'customer'))),
                    DropdownMenuItem(value: 'manager', child: Text(_roleLabel(context, 'manager'))),
                    DropdownMenuItem(value: 'assistant_manager', child: Text(_roleLabel(context, 'assistant_manager'))),
                    const DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    DropdownMenuItem(value: 'support', child: Text(_roleLabel(context, 'support'))),
                    DropdownMenuItem(value: 'operations', child: Text(_roleLabel(context, 'operations'))),
                    DropdownMenuItem(value: 'billing', child: Text(_roleLabel(context, 'billing'))),
                  ],
                  onChanged: (v) => setLocal(() => kind = v ?? 'customer'),
                ),
                const SizedBox(height: 10),
                TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: _uct(context, 'Email', 'البريد الإلكتروني', 'E-mail'))),
                const SizedBox(height: 10),
                TextField(
                  controller: password,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: _uct(context, 'Temporary / chosen password', 'كلمة المرور', 'Wachtwoord'),
                    helperText: _uct(context, 'Minimum 8 characters.', '8 أحرف على الأقل.', 'Minimaal 8 tekens.'),
                    suffixIcon: IconButton(onPressed: () => setLocal(() => obscure = !obscure), icon: Icon(obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(controller: name, decoration: InputDecoration(labelText: _uct(context, 'Full name', 'الاسم الكامل', 'Volledige naam'))),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: phone, decoration: InputDecoration(labelText: _uct(context, 'Phone', 'الهاتف', 'Telefoon')))),
                  const SizedBox(width: 10),
                  SizedBox(width: 150, child: TextField(controller: language, decoration: InputDecoration(labelText: _uct(context, 'Language', 'اللغة', 'Taal'), hintText: 'ar / en / nl'))),
                ]),
                if (kind == 'customer') ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: VetColors.softGreen, borderRadius: BorderRadius.circular(12)),
                    child: Text(_uct(context, 'This creates a Vet AI customer login only. No farm or admin access is created.', 'ده ينشئ حساب عميل للبرنامج فقط، بدون مزرعة وبدون صلاحيات إدارة.', 'Dit maakt alleen een Vet AI-klantlogin, zonder boerderij of beheerrechten.')),
                  ),
                ],
                if (kind != 'customer') ...[
                  const SizedBox(height: 14),
                  Text(_uct(context, 'Extra permissions', 'الصلاحيات الإضافية', 'Extra rechten'), style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [for (final p in permissions) FilterChip(selected: selected[p] == true, label: Text(_permissionLabel(context, p)), onSelected: (v) => setLocal(() => selected[p] = v))],
                  ),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_uct(context, 'Cancel', 'إلغاء', 'Annuleren'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_uct(context, 'Create account', 'إنشاء الحساب', 'Account maken'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (email.text.trim().isEmpty || password.text.length < 8) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_uct(context, 'Enter a valid email and a password of at least 8 characters.', 'اكتب بريد صحيح وكلمة مرور 8 أحرف على الأقل.', 'Voer een geldig e-mailadres en een wachtwoord van minimaal 8 tekens in.'))));
      return;
    }
    try {
      await _function({
        'action': 'create',
        'email': email.text.trim(),
        'password': password.text,
        'full_name': name.text.trim(),
        'phone': phone.text.trim(),
        'preferred_language': language.text.trim().isEmpty ? 'en' : language.text.trim(),
        'kind': kind,
        'permissions': {for (final e in selected.entries) if (e.value) e.key: true},
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_uct(context, 'Account created and ready to sign in.', 'تم إنشاء الحساب وهو جاهز لتسجيل الدخول.', 'Account is gemaakt en klaar om in te loggen.'))));
      reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: VetColors.red));
    }
  }

  Future<void> _manage(Map<String, dynamic> profile, _AccountControlData data) async {
    final id = profile['id'].toString();
    final auth = _authFor(data, id);
    final staff = _adminFor(data, id);
    final email = TextEditingController(text: '${auth?['email'] ?? ''}');
    final password = TextEditingController();
    final name = TextEditingController(text: '${profile['full_name'] ?? ''}');
    final phone = TextEditingController(text: '${profile['phone'] ?? ''}');
    final language = TextEditingController(text: '${profile['preferred_language'] ?? 'en'}');
    var role = '${staff?['role'] ?? 'customer'}';
    if (!{'customer','super_admin','manager','assistant_manager','admin','support','operations','billing'}.contains(role)) role = 'customer';
    var obscure = true;
    final rawPermissions = staff?['permissions'];
    final selected = <String, bool>{for (final p in permissions) p: rawPermissions is Map && rawPermissions[p] == true};
    final originalEmail = email.text.trim().toLowerCase();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(_uct(context, 'Account control', 'التحكم الكامل في الحساب', 'Accountbeheer')),
          content: SizedBox(
            width: 740,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: _uct(context, 'Login email', 'بريد تسجيل الدخول', 'Login-e-mail'))),
                const SizedBox(height: 10),
                TextField(controller: name, decoration: InputDecoration(labelText: _uct(context, 'Full name', 'الاسم الكامل', 'Volledige naam'))),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: phone, decoration: InputDecoration(labelText: _uct(context, 'Phone', 'الهاتف', 'Telefoon')))),
                  const SizedBox(width: 10),
                  SizedBox(width: 150, child: TextField(controller: language, decoration: InputDecoration(labelText: _uct(context, 'Language', 'اللغة', 'Taal')))),
                ]),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: VetColors.surface2, borderRadius: BorderRadius.circular(12), border: Border.all(color: VetColors.border)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.lock_rounded, size: 20, color: VetColors.muted),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_uct(context, 'The current password can never be viewed. Vet AI stores only a one-way password hash. You can securely set a new password below.', 'كلمة المرور الحالية لا يمكن عرضها أصلًا لأن النظام يحفظها مشفّرة باتجاه واحد. تقدر تعيّن كلمة مرور جديدة بأمان من تحت.', 'Het huidige wachtwoord kan nooit worden bekeken. Vet AI bewaart alleen een eenrichtingshash. Je kunt hieronder veilig een nieuw wachtwoord instellen.'))),
                  ]),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: password,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: _uct(context, 'Set new password (optional)', 'تعيين كلمة مرور جديدة (اختياري)', 'Nieuw wachtwoord instellen (optioneel)'),
                    suffixIcon: IconButton(onPressed: () => setLocal(() => obscure = !obscure), icon: Icon(obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded)),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: InputDecoration(labelText: _uct(context, 'Account access', 'نوع وصلاحية الحساب', 'Accounttoegang')),
                  items: [
                    DropdownMenuItem(value: 'customer', child: Text(_roleLabel(context, 'customer'))),
                    const DropdownMenuItem(value: 'super_admin', child: Text('Super Admin')),
                    DropdownMenuItem(value: 'manager', child: Text(_roleLabel(context, 'manager'))),
                    DropdownMenuItem(value: 'assistant_manager', child: Text(_roleLabel(context, 'assistant_manager'))),
                    const DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    DropdownMenuItem(value: 'support', child: Text(_roleLabel(context, 'support'))),
                    DropdownMenuItem(value: 'operations', child: Text(_roleLabel(context, 'operations'))),
                    DropdownMenuItem(value: 'billing', child: Text(_roleLabel(context, 'billing'))),
                  ],
                  onChanged: (v) => setLocal(() => role = v ?? role),
                ),
                if (role != 'customer') ...[
                  const SizedBox(height: 13),
                  Text(_uct(context, 'Explicit extra permissions', 'صلاحيات إضافية محددة', 'Expliciete extra rechten'), style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 7, runSpacing: 7, children: [for (final p in permissions) FilterChip(selected: selected[p] == true, label: Text(_permissionLabel(context, p)), onSelected: (v) => setLocal(() => selected[p] = v))]),
                ],
                const SizedBox(height: 10),
                Text('ID: $id', style: const TextStyle(color: VetColors.muted, fontSize: 11)),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_uct(context, 'Cancel', 'إلغاء', 'Annuleren'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_uct(context, 'Save account', 'حفظ الحساب', 'Account opslaan'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (password.text.isNotEmpty && password.text.length < 8) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_uct(context, 'New password must be at least 8 characters.', 'كلمة المرور الجديدة لازم تكون 8 أحرف على الأقل.', 'Nieuw wachtwoord moet minimaal 8 tekens zijn.'))));
      return;
    }
    try {
      await admin.updateProfile(id, {
        'full_name': name.text.trim(),
        'phone': phone.text.trim(),
        'preferred_language': language.text.trim().isEmpty ? 'en' : language.text.trim(),
        'last_admin_review_at': DateTime.now().toUtc().toIso8601String(),
        'last_admin_reviewed_by': admin.client.auth.currentUser?.id,
      });

      final nextEmail = email.text.trim().toLowerCase();
      if (nextEmail != originalEmail || password.text.isNotEmpty) {
        await _function({
          'action': 'update',
          'user_id': id,
          if (nextEmail != originalEmail) 'email': nextEmail,
          if (password.text.isNotEmpty) 'password': password.text,
        });
      }

      if (role == 'customer') {
        if (staff != null) {
          await admin.client.rpc('admin_remove_staff', params: {'p_user_id': id});
        }
      } else {
        await admin.client.rpc('admin_upsert_staff', params: {
          'p_user_id': id,
          'p_role': role,
          'p_active': true,
          'p_permissions': {for (final e in selected.entries) if (e.value) e.key: true},
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_uct(context, 'Account updated.', 'تم تحديث الحساب.', 'Account bijgewerkt.'))));
      reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: VetColors.red));
    }
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_AccountControlData>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('${snapshot.error}', textAlign: TextAlign.center, style: const TextStyle(color: VetColors.red))));
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!;
          final authById = {for (final row in data.authUsers) '${row['user_id']}': row};
          final adminById = {for (final row in data.admins) '${row['user_id']}': row};
          final needle = search.text.trim().toLowerCase();
          final rows = data.profiles.where((p) {
            if (needle.isEmpty) return true;
            final id = '${p['id']}';
            final email = '${authById[id]?['email'] ?? ''}';
            return '${p['full_name']} ${p['phone']} $email $id'.toLowerCase().contains(needle);
          }).toList();
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_uct(context, 'Account control center', 'مركز التحكم في الحسابات', 'Accountbeheercentrum'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(_uct(context, 'Create logins, edit email and profile details, set a new password, and control manager or assistant-manager permissions.', 'أنشئ حسابات دخول، وعدّل البريد والبيانات، وعيّن كلمة مرور جديدة، وتحكم في صلاحيات المدير ومساعد المدير.', 'Maak logins, wijzig e-mail en profielgegevens, stel een nieuw wachtwoord in en beheer managerrechten.'), style: const TextStyle(color: VetColors.muted)),
                ])),
                const SizedBox(width: 10),
                FilledButton.icon(onPressed: _createLogin, icon: const Icon(Icons.person_add_alt_1_rounded), label: Text(_uct(context, 'New login', 'حساب جديد', 'Nieuwe login'))),
              ]),
              const SizedBox(height: 13),
              TextField(controller: search, onChanged: (_) => setState(() {}), decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: _uct(context, 'Search name, email, phone or ID', 'ابحث بالاسم أو البريد أو الهاتف أو ID', 'Zoek naam, e-mail, telefoon of ID'))),
              const SizedBox(height: 13),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Chip(avatar: const Icon(Icons.people_rounded, size: 17), label: Text('${data.profiles.length} ${_uct(context, 'accounts', 'حساب', 'accounts')}')),
                Chip(avatar: const Icon(Icons.admin_panel_settings_rounded, size: 17), label: Text('${data.admins.length} ${_uct(context, 'staff/admin', 'إدارة/موظف', 'beheer/medewerkers')}')),
              ]),
              const SizedBox(height: 13),
              for (final p in rows)
                Builder(builder: (context) {
                  final id = '${p['id']}';
                  final auth = authById[id];
                  final staff = adminById[id];
                  final role = '${staff?['role'] ?? 'customer'}';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(children: [
                        CircleAvatar(child: Icon(staff == null ? Icons.person_rounded : Icons.admin_panel_settings_rounded)),
                        const SizedBox(width: 11),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${p['full_name'] ?? _uct(context, 'Unnamed account', 'حساب بدون اسم', 'Naamloos account')}', style: const TextStyle(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 2),
                          Text('${auth?['email'] ?? '-'} • ${p['phone'] ?? '-'}', style: const TextStyle(color: VetColors.muted, fontSize: 12)),
                          const SizedBox(height: 4),
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            Chip(label: Text(_roleLabel(context, role))),
                            Chip(label: Text('${p['account_status'] ?? 'active'}')),
                          ]),
                        ])),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(onPressed: () => _manage(p, data), icon: const Icon(Icons.manage_accounts_rounded), label: Text(_uct(context, 'Manage', 'إدارة', 'Beheren'))),
                      ]),
                    ),
                  );
                }),
              if (rows.isEmpty) Padding(padding: const EdgeInsets.all(30), child: Center(child: Text(_uct(context, 'No matching accounts.', 'لا توجد حسابات مطابقة.', 'Geen overeenkomende accounts.')))),
            ],
          );
        },
      );
}

class _AccountControlData {
  const _AccountControlData({required this.profiles, required this.admins, required this.authUsers});
  final List<Map<String, dynamic>> profiles;
  final List<Map<String, dynamic>> admins;
  final List<Map<String, dynamic>> authUsers;
}

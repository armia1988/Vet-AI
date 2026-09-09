import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n/vet_locale.dart';
import '../theme/app_theme.dart';
import 'admin_service.dart';

String _pt(BuildContext context, String en, String ar, String nl) =>
    VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

class VetAdminMyAccountPage extends StatefulWidget {
  const VetAdminMyAccountPage({super.key});

  @override
  State<VetAdminMyAccountPage> createState() => _VetAdminMyAccountPageState();
}

class _VetAdminMyAccountPageState extends State<VetAdminMyAccountPage> {
  final admin = VetAdminService.instance;
  final name = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  final jobTitle = TextEditingController();
  final language = TextEditingController();
  final newPassword = TextEditingController();

  bool loading = true;
  bool saving = false;
  bool obscure = true;
  String role = 'admin';
  String accountStatus = 'active';
  String createdAt = '';
  String lastSignIn = '';
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = admin.client.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() { loading = false; error = 'Not signed in'; });
      return;
    }
    try {
      final values = await Future.wait<dynamic>([
        admin.client.from('profiles').select().eq('id', user.id).maybeSingle(),
        admin.client.from('admin_accounts').select().eq('user_id', user.id).maybeSingle(),
      ]);
      final profile = values[0] is Map ? Map<String, dynamic>.from(values[0] as Map) : <String, dynamic>{};
      final staff = values[1] is Map ? Map<String, dynamic>.from(values[1] as Map) : <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        name.text = '${profile['full_name'] ?? user.userMetadata?['full_name'] ?? ''}';
        email.text = user.email ?? '';
        phone.text = '${profile['phone'] ?? ''}';
        jobTitle.text = '${profile['job_title'] ?? ''}';
        language.text = '${profile['preferred_language'] ?? 'en'}';
        role = '${staff['role'] ?? 'admin'}';
        accountStatus = '${profile['account_status'] ?? 'active'}';
        createdAt = '${user.createdAt}';
        lastSignIn = '${user.lastSignInAt ?? ''}';
        loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { loading = false; error = '$e'; });
    }
  }

  Future<void> _save() async {
    final user = admin.client.auth.currentUser;
    if (user == null || saving) return;
    if (newPassword.text.isNotEmpty && newPassword.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_pt(context, 'New password must be at least 8 characters.',
            'كلمة المرور الجديدة لازم تكون 8 أحرف على الأقل.',
            'Nieuw wachtwoord moet minimaal 8 tekens zijn.')),
      ));
      return;
    }
    setState(() => saving = true);
    try {
      await admin.updateProfile(user.id, {
        'full_name': name.text.trim(),
        'phone': phone.text.trim(),
        'job_title': jobTitle.text.trim(),
        'preferred_language': language.text.trim().isEmpty ? 'en' : language.text.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

      final nextEmail = email.text.trim().toLowerCase();
      final emailChanged = nextEmail.isNotEmpty && nextEmail != (user.email ?? '').toLowerCase();
      if (emailChanged || newPassword.text.isNotEmpty) {
        await admin.client.auth.updateUser(UserAttributes(
          email: emailChanged ? nextEmail : null,
          password: newPassword.text.isNotEmpty ? newPassword.text : null,
          data: {'full_name': name.text.trim()},
        ));
      } else {
        await admin.client.auth.updateUser(UserAttributes(data: {'full_name': name.text.trim()}));
      }
      newPassword.clear();
      admin.invalidateCache();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(emailChanged
            ? _pt(context, 'Profile saved. Check the new email address if confirmation is required.', 'تم حفظ الحساب. راجع البريد الجديد إذا طلب النظام تأكيده.', 'Profiel opgeslagen. Controleer het nieuwe e-mailadres als bevestiging nodig is.')
            : _pt(context, 'Account saved.', 'تم حفظ حسابك.', 'Account opgeslagen.')),
      ));
      await _load();
    } on AuthException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: VetColors.red));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: VetColors.red));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    phone.dispose();
    jobTitle.dispose();
    language.dispose();
    newPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(_pt(context, 'My account', 'حسابي', 'Mijn account'))),
        body: Center(child: Text(error!, style: const TextStyle(color: VetColors.red))),
      );
    }
    final user = admin.client.auth.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: Text(_pt(context, 'My Vet AI account', 'حسابي في Vet AI', 'Mijn Vet AI-account')),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Column(children: [
                CircleAvatar(
                  radius: 42,
                  backgroundColor: VetColors.softGreen,
                  child: Text(
                    name.text.trim().isEmpty ? 'A' : name.text.trim().characters.first.toUpperCase(),
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: VetColors.green),
                  ),
                ),
                const SizedBox(height: 10),
                Text(name.text.trim().isEmpty ? _pt(context, 'Administrator', 'مدير النظام', 'Beheerder') : name.text.trim(), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Wrap(spacing: 7, runSpacing: 7, alignment: WrapAlignment.center, children: [
                  Chip(avatar: const Icon(Icons.verified_user_rounded, size: 16, color: VetColors.green), label: Text(role)),
                  Chip(label: Text(accountStatus)),
                ]),
              ]),
            ),
            const SizedBox(height: 18),
            _section(context, _pt(context, 'Personal details', 'البيانات الشخصية', 'Persoonlijke gegevens'), [
              TextField(controller: name, decoration: InputDecoration(labelText: _pt(context, 'Full name', 'الاسم الكامل', 'Volledige naam'), floatingLabelBehavior: FloatingLabelBehavior.always)),
              const SizedBox(height: 12),
              TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: _pt(context, 'Login email', 'بريد تسجيل الدخول', 'Login-e-mail'), floatingLabelBehavior: FloatingLabelBehavior.always)),
              const SizedBox(height: 12),
              TextField(controller: phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: _pt(context, 'Phone', 'رقم الهاتف', 'Telefoon'), floatingLabelBehavior: FloatingLabelBehavior.always)),
              const SizedBox(height: 12),
              TextField(controller: jobTitle, decoration: InputDecoration(labelText: _pt(context, 'Job title', 'المسمى الوظيفي', 'Functietitel'), floatingLabelBehavior: FloatingLabelBehavior.always)),
              const SizedBox(height: 12),
              TextField(controller: language, decoration: InputDecoration(labelText: _pt(context, 'Preferred language', 'اللغة المفضلة', 'Voorkeurstaal'), hintText: 'ar / en / nl', floatingLabelBehavior: FloatingLabelBehavior.always)),
            ]),
            const SizedBox(height: 14),
            _section(context, _pt(context, 'Security', 'الأمان', 'Beveiliging'), [
              TextField(
                controller: newPassword,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: _pt(context, 'Set a new password', 'تعيين كلمة مرور جديدة', 'Nieuw wachtwoord instellen'),
                  helperText: _pt(context, 'Leave empty to keep the current password.', 'اتركها فارغة للاحتفاظ بكلمة المرور الحالية.', 'Laat leeg om het huidige wachtwoord te behouden.'),
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  suffixIcon: IconButton(onPressed: () => setState(() => obscure = !obscure), icon: Icon(obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded)),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            _section(context, _pt(context, 'Account information', 'معلومات الحساب', 'Accountinformatie'), [
              _info(_pt(context, 'Role', 'الصلاحية', 'Rol'), role),
              _info(_pt(context, 'Status', 'الحالة', 'Status'), accountStatus),
              _info('ID', user?.id ?? ''),
              _info(_pt(context, 'Created', 'تاريخ الإنشاء', 'Aangemaakt'), createdAt),
              _info(_pt(context, 'Last sign in', 'آخر تسجيل دخول', 'Laatste login'), lastSignIn),
            ]),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: saving ? null : _save,
              icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_rounded),
              label: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_pt(context, 'Save all changes', 'حفظ كل التعديلات', 'Alle wijzigingen opslaan'))),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => admin.client.auth.signOut(),
              icon: const Icon(Icons.logout_rounded, color: VetColors.red),
              label: Text(_pt(context, 'Sign out', 'تسجيل الخروج', 'Uitloggen')),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            ...children,
          ]),
        ),
      );

  Widget _info(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(color: VetColors.muted, fontSize: 12))),
          Expanded(child: SelectableText(value.isEmpty ? '—' : value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
        ]),
      );
}

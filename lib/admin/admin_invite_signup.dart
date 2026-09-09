import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n/vet_locale.dart';
import '../theme/app_theme.dart';
import 'admin_entry.dart';

String _it(BuildContext context, String en, String ar, String nl) => VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

class VetAdminInviteApp extends StatefulWidget {
  const VetAdminInviteApp({super.key, required this.token, required this.email});
  final String token;
  final String email;

  @override
  State<VetAdminInviteApp> createState() => _VetAdminInviteAppState();
}

class _VetAdminInviteAppState extends State<VetAdminInviteApp> {
  final locale = VetLocaleController.instance;
  final translator = VetTranslator.instance;

  @override
  void initState() {
    super.initState();
    locale.addListener(_refresh);
    translator.addListener(_refresh);
    unawaited(locale.load());
    unawaited(translator.load());
  }

  void _refresh() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    locale.removeListener(_refresh);
    translator.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Vet AI Invitation',
        theme: buildVetTheme(),
        locale: locale.locale,
        supportedLocales: vetSupportedLocales,
        localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
        home: VetAdminInvitePage(token: widget.token, email: widget.email),
      );
}

class VetAdminInvitePage extends StatefulWidget {
  const VetAdminInvitePage({super.key, required this.token, required this.email});
  final String token;
  final String email;

  @override
  State<VetAdminInvitePage> createState() => _VetAdminInvitePageState();
}

class _VetAdminInvitePageState extends State<VetAdminInvitePage> {
  final password = TextEditingController();
  final confirm = TextEditingController();
  late Future<Map<String, dynamic>> preview = _loadPreview();
  bool busy = false;
  bool obscure = true;
  String? error;
  String? success;
  bool claimedAdmin = false;

  SupabaseClient get client => Supabase.instance.client;

  Future<Map<String, dynamic>> _loadPreview() async {
    final raw = await client.rpc('account_invite_preview', params: {'p_token': widget.token});
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{'valid': false};
  }

  @override
  void initState() {
    super.initState();
    if (client.auth.currentUser != null) WidgetsBinding.instance.addPostFrameCallback((_) => _claim());
  }

  Future<void> _createAccount() async {
    if (busy) return;
    final p = password.text;
    if (p.length < 8) { setState(() => error = _it(context, 'Use at least 8 characters.', 'استخدم 8 حروف/أرقام على الأقل.', 'Gebruik minimaal 8 tekens.')); return; }
    if (p != confirm.text) { setState(() => error = _it(context, 'Passwords do not match.', 'كلمتا المرور غير متطابقتين.', 'Wachtwoorden komen niet overeen.')); return; }
    setState(() { busy = true; error = null; });
    try {
      final redirect = Uri.base.replace(queryParameters: {'invite': widget.token, 'email': widget.email}).toString();
      final response = await client.auth.signUp(
        email: widget.email.trim().toLowerCase(),
        password: p,
        emailRedirectTo: redirect,
        data: {'brand_name': 'Vet AI', 'preferred_language': Localizations.localeOf(context).languageCode},
      );
      if (response.session != null) {
        await _claim();
      } else {
        if (mounted) setState(() => success = _it(context, 'Account created. Check your email, confirm it, then this invitation will continue automatically.', 'تم إنشاء الحساب. افتح الإيميل وأكّد الحساب، وبعدها الدعوة هتكمل تلقائيًا.', 'Account gemaakt. Bevestig je e-mail; daarna gaat deze uitnodiging automatisch verder.'));
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _claim() async {
    if (busy && success == null) return;
    setState(() { busy = true; error = null; });
    try {
      final raw = await client.rpc('claim_account_invite', params: {'p_token': widget.token});
      final result = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      claimedAdmin = result['is_admin'] == true;
      if (mounted) setState(() => success = claimedAdmin
          ? _it(context, 'Your Vet AI administration access is active.', 'تم تفعيل صلاحية إدارة Vet AI.', 'Je Vet AI-beheerrechten zijn actief.')
          : _it(context, 'Your Vet AI customer/employee account is active. You can now use the Vet AI app.', 'تم تفعيل حساب Vet AI للعميل/الموظف. تقدر دلوقتي تستخدم تطبيق Vet AI.', 'Je Vet AI-klant/medewerkersaccount is actief. Je kunt nu de Vet AI-app gebruiken.'));
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: FutureBuilder<Map<String, dynamic>>(
                future: preview,
                builder: (context, snap) {
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  final info = snap.data!;
                  if (info['valid'] != true) return Card(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.link_off_rounded, size: 58, color: VetColors.red),
                    const SizedBox(height: 12),
                    Text(_it(context, 'This invitation is invalid or expired.', 'الدعوة غير صالحة أو انتهت.', 'Deze uitnodiging is ongeldig of verlopen.'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                  ])));
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        const CircleAvatar(radius: 32, backgroundColor: VetColors.softGreen, child: Icon(Icons.verified_user_rounded, size: 34, color: VetColors.green)),
                        const SizedBox(height: 14),
                        Text(_it(context, 'Vet AI account invitation', 'دعوة حساب Vet AI', 'Vet AI-accountuitnodiging'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 6),
                        Text('${info['full_name'] ?? ''}\n${info['email'] ?? widget.email}\n${info['kind'] ?? ''}', textAlign: TextAlign.center, style: const TextStyle(color: VetColors.muted, height: 1.45)),
                        const SizedBox(height: 20),
                        if (success != null) ...[
                          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: VetColors.softGreen, borderRadius: BorderRadius.circular(14)), child: Text(success!, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800))),
                          const SizedBox(height: 14),
                          if (claimedAdmin) FilledButton.icon(onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const VetAdminApp())), icon: const Icon(Icons.space_dashboard_rounded), label: Text(_it(context, 'Open admin dashboard', 'فتح لوحة التحكم', 'Admin-dashboard openen'))),
                        ] else if (client.auth.currentUser == null) ...[
                          TextField(controller: password, obscureText: obscure, decoration: InputDecoration(labelText: _it(context, 'Choose password', 'اختار كلمة المرور', 'Kies wachtwoord'), suffixIcon: IconButton(onPressed: () => setState(() => obscure = !obscure), icon: Icon(obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded)))),
                          const SizedBox(height: 10),
                          TextField(controller: confirm, obscureText: obscure, decoration: InputDecoration(labelText: _it(context, 'Confirm password', 'تأكيد كلمة المرور', 'Bevestig wachtwoord'))),
                          const SizedBox(height: 14),
                          FilledButton.icon(onPressed: busy ? null : _createAccount, icon: const Icon(Icons.person_add_alt_1_rounded), label: Text(_it(context, 'Create Vet AI account', 'إنشاء حساب Vet AI', 'Vet AI-account maken'))),
                        ] else ...[
                          FilledButton.icon(onPressed: busy ? null : _claim, icon: const Icon(Icons.verified_rounded), label: Text(_it(context, 'Activate invitation', 'تفعيل الدعوة', 'Uitnodiging activeren'))),
                        ],
                        if (busy) ...[const SizedBox(height: 14), const LinearProgressIndicator()],
                        if (error != null) ...[const SizedBox(height: 12), Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: VetColors.red, fontWeight: FontWeight.w700))],
                      ]),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
}

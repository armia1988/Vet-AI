import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n/vet_locale.dart';
import '../theme/app_theme.dart';
import 'admin_entry.dart';
import 'admin_service.dart';

class VetAdminWebRoot extends StatefulWidget {
  const VetAdminWebRoot({super.key});

  @override
  State<VetAdminWebRoot> createState() => _VetAdminWebRootState();
}

class _VetAdminWebRootState extends State<VetAdminWebRoot> {
  StreamSubscription<AuthState>? subscription;
  int revision = 0;

  @override
  void initState() {
    super.initState();
    subscription = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      if (mounted) setState(() => revision++);
    });
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  Future<bool> _isAdmin() => VetAdminService.instance.isAdmin();

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return const _AdminWebLoginApp();

    return FutureBuilder<bool>(
      key: ValueKey('admin-web-access-$revision-${user.id}'),
      future: _isAdmin(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _AdminWebLoadingApp();
        }
        if (snapshot.data == true) return const VetAdminApp();
        return const _AdminWebDeniedApp();
      },
    );
  }
}

class _AdminWebShell extends StatefulWidget {
  const _AdminWebShell({required this.home});
  final Widget home;

  @override
  State<_AdminWebShell> createState() => _AdminWebShellState();
}

class _AdminWebShellState extends State<_AdminWebShell> {
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

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    locale.removeListener(_refresh);
    translator.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Vet AI Admin',
        theme: buildVetTheme(),
        locale: locale.locale,
        supportedLocales: vetSupportedLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        localeResolutionCallback: (deviceLocale, supported) {
          if (deviceLocale == null) return const Locale('en');
          for (final item in supported) {
            if (item.languageCode == deviceLocale.languageCode) return item;
          }
          return const Locale('en');
        },
        home: widget.home,
      );
}

class _AdminWebLoginApp extends StatelessWidget {
  const _AdminWebLoginApp();
  @override
  Widget build(BuildContext context) => const _AdminWebShell(home: _AdminWebLoginPage());
}

class _AdminWebDeniedApp extends StatelessWidget {
  const _AdminWebDeniedApp();
  @override
  Widget build(BuildContext context) => const _AdminWebShell(home: _AdminWebDeniedPage());
}

class _AdminWebLoadingApp extends StatelessWidget {
  const _AdminWebLoadingApp();
  @override
  Widget build(BuildContext context) => const _AdminWebShell(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
}

String _wt(BuildContext context, String en, String ar, String nl) =>
    VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

class _AdminWebLoginPage extends StatefulWidget {
  const _AdminWebLoginPage();

  @override
  State<_AdminWebLoginPage> createState() => _AdminWebLoginPageState();
}

class _AdminWebLoginPageState extends State<_AdminWebLoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool obscure = true;
  bool busy = false;
  String? error;

  Future<void> signIn() async {
    final e = email.text.trim();
    final p = password.text;
    if (e.isEmpty || p.isEmpty) {
      setState(() => error = _wt(context, 'Enter your email and password.', 'اكتب البريد الإلكتروني وكلمة المرور.', 'Vul je e-mail en wachtwoord in.'));
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(email: e, password: p);
      final allowed = await VetAdminService.instance.isAdmin();
      if (!allowed) {
        await Supabase.instance.client.auth.signOut();
        throw const AuthException('ADMIN_ACCESS_REQUIRED');
      }
    } on AuthException catch (ex) {
      if (!mounted) return;
      setState(() {
        error = ex.message == 'ADMIN_ACCESS_REQUIRED'
            ? _wt(context, 'This account does not have Vet AI administrator access.', 'الحساب ده مش مصرح له بدخول إدارة Vet AI.', 'Dit account heeft geen Vet AI-beheerrechten.')
            : _wt(context, 'Sign-in failed. Check your email and password.', 'تسجيل الدخول فشل. راجع البريد وكلمة المرور.', 'Inloggen mislukt. Controleer je e-mail en wachtwoord.');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => error = _wt(context, 'Could not sign in right now.', 'تعذر تسجيل الدخول دلوقتي.', 'Inloggen is nu niet mogelijk.'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      VetColors.surface,
                      VetColors.surface2,
                      VetColors.green.withValues(alpha: .08),
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 470),
                    child: Card(
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(30),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(children: [
                              Container(
                                width: 54,
                                height: 54,
                                decoration: BoxDecoration(color: VetColors.softGreen, borderRadius: BorderRadius.circular(17)),
                                child: const Icon(Icons.health_and_safety_rounded, color: VetColors.green, size: 32),
                              ),
                              const SizedBox(width: 13),
                              const Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('Vet AI', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                                  Text('ADMIN CONTROL CENTER', style: TextStyle(fontSize: 10, letterSpacing: 1.25, color: VetColors.muted, fontWeight: FontWeight.w800)),
                                ]),
                              ),
                              IconButton(onPressed: () => showVetLanguagePicker(context), icon: const Icon(Icons.language_rounded)),
                            ]),
                            const SizedBox(height: 28),
                            Text(_wt(context, 'Administrator sign in', 'تسجيل دخول الإدارة', 'Beheerder inloggen'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 7),
                            Text(_wt(context, 'Use an authorized Vet AI administrator account. Access is verified by the server.', 'استخدم حساب إدارة Vet AI مصرح به. الصلاحية بيتم التحقق منها من السيرفر.', 'Gebruik een geautoriseerd Vet AI-beheeraccount. Toegang wordt door de server gecontroleerd.'), style: const TextStyle(color: VetColors.muted, height: 1.45)),
                            const SizedBox(height: 22),
                            TextField(
                              controller: email,
                              autofillHints: const [AutofillHints.username, AutofillHints.email],
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(labelText: _wt(context, 'Email', 'البريد الإلكتروني', 'E-mail'), prefixIcon: const Icon(Icons.email_rounded)),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: password,
                              obscureText: obscure,
                              autofillHints: const [AutofillHints.password],
                              onSubmitted: (_) => signIn(),
                              decoration: InputDecoration(
                                labelText: _wt(context, 'Password', 'كلمة المرور', 'Wachtwoord'),
                                prefixIcon: const Icon(Icons.lock_rounded),
                                suffixIcon: IconButton(onPressed: () => setState(() => obscure = !obscure), icon: Icon(obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded)),
                              ),
                            ),
                            if (error != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: VetColors.red.withValues(alpha: .09), borderRadius: BorderRadius.circular(12), border: Border.all(color: VetColors.red.withValues(alpha: .25))),
                                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  const Icon(Icons.error_outline_rounded, color: VetColors.red, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(error!, style: const TextStyle(color: VetColors.red, fontWeight: FontWeight.w700))),
                                ]),
                              ),
                            ],
                            const SizedBox(height: 18),
                            FilledButton.icon(
                              onPressed: busy ? null : signIn,
                              icon: busy
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.login_rounded),
                              label: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                child: Text(_wt(context, 'Sign in to control center', 'دخول لوحة التحكم', 'Inloggen bij beheercentrum')),
                              ),
                            ),
                            const SizedBox(height: 17),
                            Row(children: [
                              const Icon(Icons.shield_rounded, color: VetColors.green, size: 19),
                              const SizedBox(width: 7),
                              Expanded(child: Text(_wt(context, 'Protected by server-side administrator permissions and audit logging.', 'محمي بصلاحيات إدارة من السيرفر وتسجيل كامل للعمليات.', 'Beveiligd met server-side beheerrechten en auditlogging.'), style: const TextStyle(fontSize: 11.5, color: VetColors.muted))),
                            ]),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

class _AdminWebDeniedPage extends StatelessWidget {
  const _AdminWebDeniedPage();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const CircleAvatar(radius: 34, child: Icon(Icons.admin_panel_settings_rounded, size: 36, color: VetColors.red)),
                    const SizedBox(height: 18),
                    Text(_wt(context, 'Administrator access required', 'مطلوب صلاحية إدارة', 'Beheerderstoegang vereist'), style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Text(_wt(context, 'This signed-in account is not authorized for the Vet AI Admin Control Center.', 'الحساب المسجل حاليًا غير مصرح له بدخول لوحة إدارة Vet AI.', 'Het ingelogde account is niet geautoriseerd voor het Vet AI-beheercentrum.'), textAlign: TextAlign.center, style: const TextStyle(color: VetColors.muted, height: 1.5)),
                    const SizedBox(height: 20),
                    Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
                      OutlinedButton.icon(onPressed: () => showVetLanguagePicker(context), icon: const Icon(Icons.language_rounded), label: Text(_wt(context, 'Language', 'اللغة', 'Taal'))),
                      FilledButton.icon(onPressed: () => Supabase.instance.client.auth.signOut(), icon: const Icon(Icons.logout_rounded), label: Text(_wt(context, 'Sign out', 'تسجيل الخروج', 'Uitloggen'))),
                    ]),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
}

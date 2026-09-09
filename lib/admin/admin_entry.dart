import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n/vet_locale.dart';
import '../services/alert_notification_service.dart';
import '../services/vet_backend.dart';
import '../theme/app_theme.dart';
import '../v5_app.dart';
import 'admin_dashboard.dart';
import 'admin_service.dart';

class VetAIRoot extends StatefulWidget {
  const VetAIRoot({super.key});

  @override
  State<VetAIRoot> createState() => _VetAIRootState();
}

class _VetAIRootState extends State<VetAIRoot> {
  StreamSubscription<AuthState>? authSubscription;
  int authRevision = 0;

  @override
  void initState() {
    super.initState();
    authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      if (mounted) setState(() => authRevision++);
    });
  }

  @override
  void dispose() {
    authSubscription?.cancel();
    super.dispose();
  }

  Future<_RootAccess> _access() async {
    final admin = await VetAdminService.instance.isAdmin();
    if (admin) return const _RootAccess(isAdmin: true, accountStatus: 'active', maintenance: false);
    try {
      final value = await VetAdminService.instance.client.rpc('customer_access_state');
      final map = value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
      return _RootAccess(
        isAdmin: false,
        accountStatus: '${map['account_status'] ?? 'active'}',
        maintenance: map['maintenance_mode'] == true,
      );
    } catch (_) {
      return const _RootAccess(isAdmin: false, accountStatus: 'active', maintenance: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || user.emailConfirmedAt == null) {
      return const VetAIAppV5();
    }

    return FutureBuilder<_RootAccess>(
      key: ValueKey('access-check-$authRevision-${user.id}'),
      future: _access(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _AdminCheckApp();
        }
        final access = snapshot.data ?? const _RootAccess(isAdmin: false, accountStatus: 'active', maintenance: false);
        if (access.isAdmin) return const VetAdminApp();
        if (access.maintenance) return const _CustomerAccessApp(reason: _CustomerAccessReason.maintenance);
        if (access.accountStatus == 'suspended') return const _CustomerAccessApp(reason: _CustomerAccessReason.suspended);
        if (access.accountStatus == 'closed') return const _CustomerAccessApp(reason: _CustomerAccessReason.closed);
        return const VetAIAppV5();
      },
    );
  }
}

class _RootAccess {
  const _RootAccess({required this.isAdmin, required this.accountStatus, required this.maintenance});
  final bool isAdmin;
  final String accountStatus;
  final bool maintenance;
}

enum _CustomerAccessReason { maintenance, suspended, closed }

class _CustomerAccessApp extends StatefulWidget {
  const _CustomerAccessApp({required this.reason});
  final _CustomerAccessReason reason;

  @override
  State<_CustomerAccessApp> createState() => _CustomerAccessAppState();
}

class _CustomerAccessAppState extends State<_CustomerAccessApp> {
  final localeController = VetLocaleController.instance;
  final translator = VetTranslator.instance;

  @override
  void initState() {
    super.initState();
    localeController.addListener(_refresh);
    translator.addListener(_refresh);
    localeController.load();
    translator.load();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  String t(BuildContext context, String en, String ar, String nl) => translator.text(
        localeCode: Localizations.localeOf(context).languageCode,
        en: en,
        ar: ar,
        nl: nl,
      );

  @override
  void dispose() {
    localeController.removeListener(_refresh);
    translator.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildVetTheme(),
        locale: localeController.locale,
        supportedLocales: vetSupportedLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) {
            final maintenance = widget.reason == _CustomerAccessReason.maintenance;
            final closed = widget.reason == _CustomerAccessReason.closed;
            final title = maintenance
                ? t(context, 'Vet AI is under maintenance', 'Vet AI في وضع الصيانة', 'Vet AI is in onderhoud')
                : closed
                    ? t(context, 'Account closed', 'الحساب مغلق', 'Account gesloten')
                    : t(context, 'Account suspended', 'الحساب موقوف', 'Account opgeschort');
            final body = maintenance
                ? t(context, 'Customer access is temporarily paused by Vet AI administration. Please try again later.', 'تم إيقاف دخول العملاء مؤقتًا من إدارة Vet AI. حاول مرة أخرى لاحقًا.', 'Klanttoegang is tijdelijk gepauzeerd door Vet AI-beheer. Probeer het later opnieuw.')
                : closed
                    ? t(context, 'This Vet AI customer account has been closed. Contact Vet AI support if you need assistance.', 'تم إغلاق حساب Vet AI هذا. تواصل مع دعم Vet AI إذا كنت تحتاج مساعدة.', 'Dit Vet AI-klantaccount is gesloten. Neem contact op met Vet AI-support als je hulp nodig hebt.')
                    : t(context, 'This Vet AI customer account has been suspended by administration. Farm and sensor data access is blocked until it is reactivated.', 'تم إيقاف حساب Vet AI هذا من الإدارة. الوصول للمزرعة وبيانات الحساسات محظور حتى إعادة التفعيل.', 'Dit Vet AI-klantaccount is door beheer opgeschort. Toegang tot boerderij- en sensorgegevens is geblokkeerd tot heractivatie.');
            return Scaffold(
              body: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            CircleAvatar(
                              radius: 34,
                              backgroundColor: maintenance ? VetColors.surface3 : VetColors.red.withValues(alpha: .12),
                              child: Icon(maintenance ? Icons.build_circle_rounded : Icons.lock_rounded, size: 37, color: maintenance ? VetColors.history : VetColors.red),
                            ),
                            const SizedBox(height: 18),
                            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 10),
                            Text(body, textAlign: TextAlign.center, style: const TextStyle(color: VetColors.muted, height: 1.5)),
                            const SizedBox(height: 22),
                            Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: [
                              OutlinedButton.icon(onPressed: () => showVetLanguagePicker(context), icon: const Icon(Icons.language_rounded), label: Text(t(context, 'Language', 'اللغة', 'Taal'))),
                              FilledButton.icon(onPressed: () => VetBackend.instance.signOut(), icon: const Icon(Icons.logout_rounded), label: Text(t(context, 'Sign out', 'تسجيل الخروج', 'Uitloggen'))),
                            ]),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
}

class _AdminCheckApp extends StatelessWidget {
  const _AdminCheckApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildVetTheme(),
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
}

class VetAdminApp extends StatefulWidget {
  const VetAdminApp({super.key});

  @override
  State<VetAdminApp> createState() => _VetAdminAppState();
}

class _VetAdminAppState extends State<VetAdminApp> {
  final localeController = VetLocaleController.instance;
  final translator = VetTranslator.instance;

  @override
  void initState() {
    super.initState();
    localeController.addListener(_refresh);
    translator.addListener(_refresh);
    localeController.load();
    translator.load();
    unawaited(VetAlertNotificationService.instance.registerRemotePushForAdmin());
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    localeController.removeListener(_refresh);
    translator.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Vet AI Admin',
        theme: buildVetTheme(),
        locale: localeController.locale,
        supportedLocales: vetSupportedLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        localeResolutionCallback: (deviceLocale, supported) {
          if (deviceLocale == null) return const Locale('en');
          for (final locale in supported) {
            if (locale.languageCode == deviceLocale.languageCode) return locale;
          }
          return const Locale('en');
        },
        home: const VetAdminDashboard(),
      );
}

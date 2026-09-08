import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n/vet_locale.dart';
import '../services/alert_notification_service.dart';
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

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || user.emailConfirmedAt == null) {
      return const VetAIAppV5();
    }

    return FutureBuilder<bool>(
      key: ValueKey('admin-check-$authRevision-${user.id}'),
      future: VetAdminService.instance.isAdmin(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _AdminCheckApp();
        }
        if (snapshot.data == true) return const VetAdminApp();
        return const VetAIAppV5();
      },
    );
  }
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

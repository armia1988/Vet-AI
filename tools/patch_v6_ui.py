from pathlib import Path

p = Path('lib/v5_app.dart')
s = p.read_text()
s = s.replace("import 'v2_app.dart' show V2Text;\n", "import 'i18n/vet_locale.dart';\n")

old = '''class VetAIAppV5 extends StatelessWidget {
  const VetAIAppV5({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Vet AI',
      theme: buildVetTheme(),
      supportedLocales: V2Text.supportedLocales,
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
      home: const V5AuthGate(),
    );
  }
}

String tr(BuildContext context, String en, String ar, String nl) {
  switch (Localizations.localeOf(context).languageCode) {
    case 'ar':
      return ar;
    case 'nl':
      return nl;
    default:
      return en;
  }
}
'''
new = '''class VetAIAppV5 extends StatefulWidget {
  const VetAIAppV5({super.key});

  @override
  State<VetAIAppV5> createState() => _VetAIAppV5State();
}

class _VetAIAppV5State extends State<VetAIAppV5> {
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

  void _refresh() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    localeController.removeListener(_refresh);
    translator.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Vet AI',
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
      home: const V5AuthGate(),
    );
  }
}

String tr(BuildContext context, String en, String ar, String nl) {
  return VetTranslator.instance.text(
    localeCode: Localizations.localeOf(context).languageCode,
    en: en,
    ar: ar,
    nl: nl,
  );
}
'''
if old not in s:
    raise SystemExit('root app snippet not found')
s = s.replace(old, new, 1)

old = '''          const Spacer(),
          IconButton.filledTonal(
            tooltip: tr(context, 'Account & settings', 'الحساب والإعدادات', 'Account & instellingen'),
            icon: const Icon(Icons.account_circle_outlined, size: 34),
            onPressed: onAccount,
          ),
'''
new = '''          const Spacer(),
          IconButton.filledTonal(
            tooltip: tr(context, 'Language', 'اللغة', 'Taal'),
            style: IconButton.styleFrom(backgroundColor: VetColors.surface3),
            icon: const Icon(Icons.language_rounded, size: 33, color: VetColors.blue),
            onPressed: () => showVetLanguagePicker(context),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: tr(context, 'Account & settings', 'الحساب والإعدادات', 'Account & instellingen'),
            style: IconButton.styleFrom(backgroundColor: VetColors.surface3),
            icon: const Icon(Icons.account_circle_outlined, size: 34, color: VetColors.primary),
            onPressed: onAccount,
          ),
'''
if old not in s:
    raise SystemExit('home actions snippet not found')
s = s.replace(old, new, 1)

old = '''          _nav(Icons.home_outlined, Icons.home_rounded, tr(context, 'Home', 'الرئيسية', 'Home')),
          _nav(Icons.document_scanner_outlined, Icons.document_scanner_rounded, tr(context, 'AI Scan', 'فحص AI', 'AI-scan')),
          _nav(smart ? Icons.sensors_outlined : Icons.lock_outline_rounded, smart ? Icons.sensors_rounded : Icons.lock_rounded, tr(context, 'Sensors', 'الحساسات', 'Sensoren')),
          _nav(Icons.warning_amber_outlined, Icons.warning_rounded, tr(context, 'Alerts', 'الإنذارات', 'Meldingen')),
          _nav(Icons.history_rounded, Icons.manage_history_rounded, tr(context, 'History', 'السجل', 'Historie')),
'''
new = '''          _nav(Icons.home_outlined, Icons.home_rounded, tr(context, 'Home', 'الرئيسية', 'Home'), VetColors.green),
          _nav(Icons.document_scanner_outlined, Icons.document_scanner_rounded, tr(context, 'AI Scan', 'فحص AI', 'AI-scan'), VetColors.blue),
          _nav(smart ? Icons.sensors_outlined : Icons.lock_outline_rounded, smart ? Icons.sensors_rounded : Icons.lock_rounded, tr(context, 'Sensors', 'الحساسات', 'Sensoren'), VetColors.purple),
          _nav(Icons.warning_amber_outlined, Icons.warning_rounded, tr(context, 'Alerts', 'الإنذارات', 'Meldingen'), VetColors.orange),
          _nav(Icons.history_rounded, Icons.manage_history_rounded, tr(context, 'History', 'السجل', 'Historie'), VetColors.history),
'''
if old not in s:
    raise SystemExit('nav destinations snippet not found')
s = s.replace(old, new, 1)

old = '''  NavigationDestination _nav(IconData icon, IconData selected, String label) => NavigationDestination(
        icon: Icon(icon, size: 29),
        selectedIcon: Icon(selected, size: 31),
        label: label,
      );
'''
new = '''  NavigationDestination _nav(IconData icon, IconData selected, String label, Color color) => NavigationDestination(
        icon: Icon(icon, size: 30, color: VetColors.muted),
        selectedIcon: Container(
          width: 48,
          height: 40,
          decoration: BoxDecoration(color: color.withValues(alpha: .18), borderRadius: BorderRadius.circular(14)),
          child: Icon(selected, size: 32, color: color),
        ),
        label: label,
      );
'''
if old not in s:
    raise SystemExit('nav helper snippet not found')
s = s.replace(old, new, 1)

p.write_text(s)
print('V6 UI patch applied')

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';

class VetLanguage {
  const VetLanguage(this.code, this.englishName, this.nativeName);
  final String code;
  final String englishName;
  final String nativeName;
  Locale get locale => Locale(code);
}

const vetLanguages = <VetLanguage>[
  VetLanguage('en', 'English', 'English'),
  VetLanguage('ar', 'Arabic', 'العربية'),
  VetLanguage('nl', 'Dutch', 'Nederlands'),
  VetLanguage('de', 'German', 'Deutsch'),
  VetLanguage('fr', 'French', 'Français'),
  VetLanguage('es', 'Spanish', 'Español'),
  VetLanguage('it', 'Italian', 'Italiano'),
  VetLanguage('pt', 'Portuguese', 'Português'),
  VetLanguage('tr', 'Turkish', 'Türkçe'),
  VetLanguage('ru', 'Russian', 'Русский'),
  VetLanguage('uk', 'Ukrainian', 'Українська'),
  VetLanguage('pl', 'Polish', 'Polski'),
  VetLanguage('ro', 'Romanian', 'Română'),
  VetLanguage('el', 'Greek', 'Ελληνικά'),
  VetLanguage('cs', 'Czech', 'Čeština'),
  VetLanguage('sk', 'Slovak', 'Slovenčina'),
  VetLanguage('hu', 'Hungarian', 'Magyar'),
  VetLanguage('bg', 'Bulgarian', 'Български'),
  VetLanguage('hr', 'Croatian', 'Hrvatski'),
  VetLanguage('sr', 'Serbian', 'Српски'),
  VetLanguage('sl', 'Slovenian', 'Slovenščina'),
  VetLanguage('sv', 'Swedish', 'Svenska'),
  VetLanguage('no', 'Norwegian', 'Norsk'),
  VetLanguage('da', 'Danish', 'Dansk'),
  VetLanguage('fi', 'Finnish', 'Suomi'),
  VetLanguage('he', 'Hebrew', 'עברית'),
  VetLanguage('fa', 'Persian', 'فارسی'),
  VetLanguage('ur', 'Urdu', 'اردو'),
  VetLanguage('hi', 'Hindi', 'हिन्दी'),
  VetLanguage('bn', 'Bengali', 'বাংলা'),
  VetLanguage('pa', 'Punjabi', 'ਪੰਜਾਬੀ'),
  VetLanguage('ta', 'Tamil', 'தமிழ்'),
  VetLanguage('te', 'Telugu', 'తెలుగు'),
  VetLanguage('ml', 'Malayalam', 'മലയാളം'),
  VetLanguage('mr', 'Marathi', 'मराठी'),
  VetLanguage('gu', 'Gujarati', 'ગુજરાતી'),
  VetLanguage('kn', 'Kannada', 'ಕನ್ನಡ'),
  VetLanguage('zh', 'Chinese', '中文'),
  VetLanguage('ja', 'Japanese', '日本語'),
  VetLanguage('ko', 'Korean', '한국어'),
  VetLanguage('th', 'Thai', 'ไทย'),
  VetLanguage('vi', 'Vietnamese', 'Tiếng Việt'),
  VetLanguage('id', 'Indonesian', 'Bahasa Indonesia'),
  VetLanguage('ms', 'Malay', 'Bahasa Melayu'),
  VetLanguage('fil', 'Filipino', 'Filipino'),
  VetLanguage('sw', 'Swahili', 'Kiswahili'),
  VetLanguage('am', 'Amharic', 'አማርኛ'),
  VetLanguage('zu', 'Zulu', 'isiZulu'),
];

const vetCoreUiStrings = <String>[
  'Language',
  'Automatic',
  'Device language',
  'Preparing language…',
  'Home',
  'AI Scan',
  'Sensors',
  'Alerts',
  'History',
  'Account & settings',
  'Real data policy',
  'No demo sensor readings and no definitive diagnosis from one image.',
  'Health monitoring overview',
  'Barns',
  'Workers',
  'Veterinarians',
  'Plan',
  'Smart monitoring',
  'Software only',
  'AI health scan',
  'Image + symptoms + reviewed veterinary knowledge. Not a definitive diagnosis.',
  'Livestock',
  'Poultry',
  'Dogs',
  'Camera',
  'Photos',
  'Symptoms / history / recent changes',
  'Analyze case',
  'Analyzing safely…',
  'Fast preliminary assessment',
  'Final verified report',
  'Most likely at this stage',
  'Disease / most likely condition',
  'Cause',
  'Treatment / management',
  'Treatment & management',
  'Prevention',
  'What to do now',
  'What you should do now',
  'Veterinary next steps',
  'Danger signs',
  'How to confirm',
  'Trusted sources used',
  'Answer these to improve the report',
  'Yes',
  'No',
  'Unknown',
  'Send answers & create final report',
  'Create final verified report',
  'Checking trusted sources…',
  'Mute result',
  'Turn sound on',
  'Create account',
  'Sign in',
  'Full name',
  'Phone',
  'Email',
  'Password',
  'Confirm your email',
  'Profile & farm data',
  'Subscription',
  'Support chat',
  'About Vet AI',
];

class VetLocaleController extends ChangeNotifier {
  VetLocaleController._();
  static final instance = VetLocaleController._();
  static const _pref = 'vet_ai_language_override';

  String? _manualCode;
  bool _loaded = false;
  String? get manualCode => _manualCode;
  bool get isAutomatic => _manualCode == null;
  Locale? get locale => _manualCode == null ? null : Locale(_manualCode!);

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final p = await SharedPreferences.getInstance();
    final code = p.getString(_pref);
    if (code != null && vetLanguages.any((l) => l.code == code)) _manualCode = code;
    notifyListeners();
  }

  Future<void> automatic() async {
    _manualCode = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_pref);
    notifyListeners();
  }

  Future<void> choose(String code) async {
    if (!vetLanguages.any((l) => l.code == code)) return;
    _manualCode = code;
    final p = await SharedPreferences.getInstance();
    await p.setString(_pref, code);
    notifyListeners();
  }
}

class VetTranslator extends ChangeNotifier {
  VetTranslator._();
  static final instance = VetTranslator._();
  static const _pref = 'vet_ai_ui_translation_cache_v2';

  final Map<String, String> _cache = {};
  final Map<String, Set<String>> _queued = {};
  final Map<String, Timer> _timers = {};
  final Set<String> _running = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_pref);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            if (entry.key is String && entry.value is String) _cache[entry.key as String] = entry.value as String;
          }
        }
      } catch (_) {}
    }
  }

  bool _bundled(String code) => code == 'en' || code == 'ar' || code == 'nl';
  String _key(String language, String source) => '$language\u0001$source';

  String text({required String localeCode, required String en, required String ar, required String nl}) {
    if (localeCode == 'ar') return ar;
    if (localeCode == 'nl') return nl;
    if (localeCode == 'en') return en;
    final translated = _cache[_key(localeCode, en)];
    if (translated != null && translated.trim().isNotEmpty) return translated;
    _queue(localeCode, en);
    return en;
  }

  Future<bool> prepareLanguage(String language, Iterable<String> sources) async {
    if (_bundled(language)) return true;
    if (!_loaded) await load();
    final missing = sources
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !_cache.containsKey(_key(language, e)))
        .toSet()
        .toList();
    if (missing.isEmpty) return true;
    final hasSession = Supabase.instance.client.auth.currentSession != null;
    final permitted = hasSession ? missing : missing.where(vetCoreUiStrings.contains).toList();
    if (permitted.isEmpty) return false;

    var changed = false;
    for (var i = 0; i < permitted.length; i += 70) {
      final batch = permitted.sublist(i, i + 70 > permitted.length ? permitted.length : i + 70);
      final translated = await _translateBatch(language, batch);
      if (translated == null) return false;
      for (var n = 0; n < batch.length; n++) {
        _cache[_key(language, batch[n])] = translated[n];
      }
      changed = true;
    }
    if (changed) {
      await _save();
      notifyListeners();
    }
    return true;
  }

  void _queue(String language, String source) {
    if (!_loaded || source.trim().isEmpty) return;
    final signedIn = Supabase.instance.client.auth.currentSession != null;
    if (!signedIn && !vetCoreUiStrings.contains(source.trim())) return;
    final set = _queued.putIfAbsent(language, () => <String>{});
    set.add(source.trim());
    _timers[language]?.cancel();
    _timers[language] = Timer(const Duration(milliseconds: 90), () => _flush(language));
  }

  Future<void> _flush(String language) async {
    if (_running.contains(language)) return;
    final sources = _queued.remove(language)?.toList() ?? const <String>[];
    if (sources.isEmpty) return;
    _running.add(language);
    try {
      final translated = await _translateBatch(language, sources);
      if (translated == null) return;
      for (var i = 0; i < sources.length; i++) {
        _cache[_key(language, sources[i])] = translated[i];
      }
      await _save();
      notifyListeners();
    } finally {
      _running.remove(language);
      if ((_queued[language]?.isNotEmpty ?? false)) {
        _timers[language]?.cancel();
        _timers[language] = Timer(const Duration(milliseconds: 60), () => _flush(language));
      }
    }
  }

  Future<List<String>?> _translateBatch(String language, List<String> texts) async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'translate-ui',
        body: {'target_language': language, 'texts': texts},
      );
      final data = response.data;
      final raw = data is Map ? data['translations'] : null;
      if (raw is! List || raw.length != texts.length) return null;
      final out = raw.map((e) => e.toString().trim()).toList();
      if (out.any((e) => e.isEmpty)) return null;
      return out;
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_pref, jsonEncode(_cache));
  }

  @override
  void dispose() {
    for (final timer in _timers.values) timer.cancel();
    super.dispose();
  }
}

List<Locale> get vetSupportedLocales => vetLanguages.map((e) => e.locale).toList(growable: false);

String _pickerText(BuildContext context, String en, String ar, String nl) => VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

Future<void> showVetLanguagePicker(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: VetColors.surface,
    builder: (_) => const _VetLanguagePickerSheet(),
  );
}

class _VetLanguagePickerSheet extends StatefulWidget {
  const _VetLanguagePickerSheet();
  @override
  State<_VetLanguagePickerSheet> createState() => _VetLanguagePickerSheetState();
}

class _VetLanguagePickerSheetState extends State<_VetLanguagePickerSheet> {
  bool _bundled(String code) => code == 'en' || code == 'ar' || code == 'nl';

  Future<void> _choose(String code) async {
    final controller = VetLocaleController.instance;
    final translator = VetTranslator.instance;
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.pop(context);

    if (_bundled(code)) {
      await controller.choose(code);
      return;
    }

    bool prepared = false;
    try {
      prepared = await translator
          .prepareLanguage(code, vetCoreUiStrings)
          .timeout(const Duration(seconds: 12), onTimeout: () => false);
    } catch (_) {
      prepared = false;
    }
    if (prepared) {
      await controller.choose(code);
    } else {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            _pickerText(
              messenger.context,
              'This language could not be prepared right now. Your current language was kept.',
              'اللغة دي ماقدرتش تجهز دلوقتي، فسيبنا اللغة الحالية زي ما هي بدل ما نعرض كلام ناقص أو مختلط.',
              'Deze taal kon nu niet worden voorbereid. De huidige taal is behouden.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _automatic() async {
    final controller = VetLocaleController.instance;
    final translator = VetTranslator.instance;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final device = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    Navigator.pop(context);

    if (!vetLanguages.any((l) => l.code == device)) {
      await controller.automatic();
      return;
    }
    if (_bundled(device)) {
      await controller.automatic();
      return;
    }

    bool prepared = false;
    try {
      prepared = await translator
          .prepareLanguage(device, vetCoreUiStrings)
          .timeout(const Duration(seconds: 12), onTimeout: () => false);
    } catch (_) {
      prepared = false;
    }
    if (prepared) {
      await controller.automatic();
    } else {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            _pickerText(
              messenger.context,
              'The device language could not be prepared right now. Your current language was kept.',
              'لغة الهاتف ماقدرتش تجهز دلوقتي، فسيبنا اللغة الحالية بدل ما نعرض ترجمة ناقصة.',
              'De apparaattaal kon nu niet worden voorbereid. De huidige taal is behouden.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = VetLocaleController.instance;
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: .84,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(width: 44, height: 4, decoration: BoxDecoration(color: VetColors.border, borderRadius: BorderRadius.circular(4))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(children: [
                const Icon(Icons.language_rounded, color: VetColors.blue, size: 31),
                const SizedBox(width: 12),
                Text(_pickerText(context, 'Language', 'اللغة', 'Taal'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              ]),
            ),
            ListTile(
              leading: const Icon(Icons.phone_iphone_rounded, size: 30, color: VetColors.primary),
              title: Text(_pickerText(context, 'Automatic', 'تلقائي', 'Automatisch'), style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(_pickerText(context, 'Device language', 'حسب لغة الموبايل', 'Taal van apparaat')),
              trailing: controller.isAutomatic ? const Icon(Icons.check_circle_rounded, color: VetColors.primary) : null,
              onTap: _automatic,
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: vetLanguages.length,
                itemBuilder: (context, i) {
                  final language = vetLanguages[i];
                  final selected = controller.manualCode == language.code;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: VetColors.surface3,
                      child: Text(language.code.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: VetColors.primaryDark)),
                    ),
                    title: Text(language.nativeName, style: const TextStyle(fontWeight: FontWeight.w800)),
                    trailing: selected ? const Icon(Icons.check_circle_rounded, color: VetColors.primary) : null,
                    onTap: () => _choose(language.code),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
              child: Text(
                _pickerText(
                  context,
                  'English, Arabic and Dutch are built in. Other languages are prepared in one batch and the app switches only when the complete pack is ready.',
                  'العربي والإنجليزي والهولندي موجودين جوه التطبيق. باقي اللغات بتتجهز دفعة واحدة، والبرنامج بيحوّل عليها بس لما الحزمة تكون كاملة علشان مايبقاش فيه نص عربي ونص إنجليزي.',
                  'Engels, Arabisch en Nederlands zijn ingebouwd. Andere talen worden als één pakket voorbereid; de app schakelt pas om wanneer het volledige pakket klaar is.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(color: VetColors.muted, fontSize: 12, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

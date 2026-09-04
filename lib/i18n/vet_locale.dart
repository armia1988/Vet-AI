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
  static const _pref = 'vet_ai_ui_translation_cache_v1';

  final Map<String, String> _cache = {};
  final Set<String> _pending = {};
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

  String text({required String localeCode, required String en, required String ar, required String nl}) {
    if (localeCode == 'ar') return ar;
    if (localeCode == 'nl') return nl;
    if (localeCode == 'en') return en;
    final key = '$localeCode\u0001$en';
    final translated = _cache[key];
    if (translated != null && translated.trim().isNotEmpty) return translated;
    _schedule(localeCode, en, key);
    return en;
  }

  void _schedule(String language, String source, String key) {
    if (!_loaded || _pending.contains(key) || source.trim().isEmpty) return;
    _pending.add(key);
    Future<void>(() async {
      try {
        final response = await Supabase.instance.client.functions.invoke(
          'translate-ui',
          body: {'target_language': language, 'text': source},
        );
        final data = response.data;
        final translated = data is Map ? data['translation']?.toString() : null;
        if (translated != null && translated.trim().isNotEmpty) {
          _cache[key] = translated.trim();
          final p = await SharedPreferences.getInstance();
          await p.setString(_pref, jsonEncode(_cache));
          notifyListeners();
        }
      } catch (_) {
        // Keep the safe English fallback until the translation service becomes available.
      } finally {
        _pending.remove(key);
      }
    });
  }
}

List<Locale> get vetSupportedLocales => vetLanguages.map((e) => e.locale).toList(growable: false);

Future<void> showVetLanguagePicker(BuildContext context) async {
  final controller = VetLocaleController.instance;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: VetColors.surface,
    builder: (sheetContext) => SafeArea(
      child: FractionallySizedBox(
        heightFactor: .82,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(width: 44, height: 4, decoration: BoxDecoration(color: VetColors.border, borderRadius: BorderRadius.circular(4))),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(children: [Icon(Icons.language_rounded, color: VetColors.blue, size: 31), SizedBox(width: 12), Text('Language / اللغة', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900))]),
            ),
            ListTile(
              leading: const Icon(Icons.phone_iphone_rounded, size: 30, color: VetColors.primary),
              title: const Text('Automatic • Device language', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text('تلقائي • حسب لغة الهاتف'),
              trailing: controller.isAutomatic ? const Icon(Icons.check_circle_rounded, color: VetColors.primary) : null,
              onTap: () async { await controller.automatic(); if (sheetContext.mounted) Navigator.pop(sheetContext); },
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: vetLanguages.length,
                itemBuilder: (context, i) {
                  final language = vetLanguages[i];
                  final selected = controller.manualCode == language.code;
                  return ListTile(
                    leading: CircleAvatar(backgroundColor: VetColors.surface3, child: Text(language.code.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900))),
                    title: Text(language.nativeName, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: language.nativeName == language.englishName ? null : Text(language.englishName),
                    trailing: selected ? const Icon(Icons.check_circle_rounded, color: VetColors.primary) : null,
                    onTap: () async { await controller.choose(language.code); if (context.mounted) Navigator.pop(context); },
                  );
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 8, 18, 14),
              child: Text('Arabic, English and Dutch are bundled. Other languages are securely translated and cached when the protected translation service is available.', textAlign: TextAlign.center, style: TextStyle(color: VetColors.muted, fontSize: 12, height: 1.35)),
            ),
          ],
        ),
      ),
    ),
  );
}

from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'{label}: expected source block not found')
    return text.replace(old, new, 1)

# 1) Reset legacy language override so upgrades return to true device-language mode
# until the user explicitly chooses a new manual language in this build.
p = Path('lib/i18n/vet_locale.dart')
s = p.read_text()
s = replace_once(
    s,
    "static const _pref = 'vet_ai_language_override';",
    "static const _pref = 'vet_ai_language_override_v3';",
    'language preference version',
)
s = replace_once(
    s,
    "    final p = await SharedPreferences.getInstance();\n    final code = p.getString(_pref);",
    "    final p = await SharedPreferences.getInstance();\n    await p.remove('vet_ai_language_override');\n    final code = p.getString(_pref);",
    'legacy language cleanup',
)
s = replace_once(
    s,
    "  'About Vet AI',\n];",
    "  'About Vet AI',\n  'Vet AI — Confirm your account',\n  'Welcome to Vet AI',\n  'Confirm your email address to finish creating your Vet AI account and securely access your farm data.',\n  'Confirm Vet AI account',\n  'If you did not create this Vet AI account, you can ignore this email.',\n];",
    'email localization strings',
)
p.write_text(s)

# 2) Add localized auth-email metadata, fix RTL/LTR home header, and use raster final icons correctly.
p = Path('lib/v5_app.dart')
s = p.read_text()
s = replace_once(
    s,
    "          preferredLanguage: Localizations.localeOf(context).languageCode,\n        );",
    "          preferredLanguage: Localizations.localeOf(context).languageCode,\n          emailSubject: tr(context, 'Vet AI — Confirm your account', 'Vet AI — أكّد حسابك', 'Vet AI — Bevestig je account'),\n          emailHeading: tr(context, 'Welcome to Vet AI', 'أهلاً بيك في Vet AI', 'Welkom bij Vet AI'),\n          emailBody: tr(context, 'Confirm your email address to finish creating your Vet AI account and securely access your farm data.', 'أكّد بريدك الإلكتروني علشان تكمّل إنشاء حساب Vet AI وتدخل على بيانات مزرعتك بأمان.', 'Bevestig je e-mailadres om je Vet AI-account af te ronden en veilig toegang te krijgen tot je boerderijgegevens.'),\n          emailButton: tr(context, 'Confirm Vet AI account', 'تأكيد حساب Vet AI', 'Vet AI-account bevestigen'),\n          emailFooter: tr(context, 'If you did not create this Vet AI account, you can ignore this email.', 'لو إنت ماعملتش حساب Vet AI ده، تجاهل الرسالة دي.', 'Als je dit Vet AI-account niet hebt aangemaakt, kun je deze e-mail negeren.'),\n        );",
    'signup localized email metadata',
)
old_header = """        SizedBox(
          height: 108,
          child: Stack(
            children: [
              const Align(
                alignment: Alignment.topCenter,
                child: _BrandLockup(markWidth: 118, compact: true),
              ),
              PositionedDirectional(
                top: 0,
                end: 0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton.filledTonal(
                      tooltip: tr(context, 'Language', 'اللغة', 'Taal'),
                      style: IconButton.styleFrom(backgroundColor: VetColors.surface3),
                      icon: const Icon(Icons.language_rounded, size: 30, color: VetColors.blue),
                      onPressed: () => showVetLanguagePicker(context),
                    ),
                    const SizedBox(width: 5),
                    IconButton.filledTonal(
                      tooltip: tr(context, 'Account & settings', 'الحساب والإعدادات', 'Account & instellingen'),
                      style: IconButton.styleFrom(backgroundColor: VetColors.surface3),
                      icon: const Icon(Icons.account_circle_outlined, size: 31, color: VetColors.primary),
                      onPressed: onAccount,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
"""
new_header = """        SizedBox(
          height: 74,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const _HeaderBrand(),
              const Spacer(),
              IconButton.filledTonal(
                tooltip: tr(context, 'Language', 'اللغة', 'Taal'),
                style: IconButton.styleFrom(backgroundColor: VetColors.surface3),
                icon: const Icon(Icons.language_rounded, size: 30, color: VetColors.blue),
                onPressed: () => showVetLanguagePicker(context),
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: tr(context, 'Account & settings', 'الحساب والإعدادات', 'Account & instellingen'),
                style: IconButton.styleFrom(backgroundColor: VetColors.surface3),
                icon: const Icon(Icons.account_circle_outlined, size: 31, color: VetColors.primary),
                onPressed: onAccount,
              ),
            ],
          ),
        ),
"""
s = replace_once(s, old_header, new_header, 'home header')
s = replace_once(
    s,
    "ChoiceChip(avatar: SvgPicture.asset(asset(g), width: 26, height: 26), label: Text(label(g)),",
    "ChoiceChip(avatar: Image.asset(asset(g), width: 34, height: 34, fit: BoxFit.contain, filterQuality: FilterQuality.high), label: Text(label(g)),",
    'scan group icon renderer',
)
s = replace_once(
    s,
    "          _Notice(icon: Icons.pets_rounded, title: label(groups.first), text: tr(context, 'This is the animal group enabled for this farm.', 'هذا هو نوع الحيوان المفعّل لهذه المزرعة.', 'Dit is de diergroep die voor deze boerderij is ingeschakeld.')),",
    "          _AnimalGroupBanner(asset: asset(groups.first), title: label(groups.first), text: tr(context, 'This is the animal group enabled for this farm.', 'ده نوع الحيوان المفعّل للمزرعة دي.', 'Dit is de diergroep die voor deze boerderij is ingeschakeld.')),",
    'single scan group banner',
)
s = replace_once(
    s,
    "class _AnimalChoice extends StatelessWidget {",
    """class _AnimalGroupBanner extends StatelessWidget {
  const _AnimalGroupBanner({required this.asset, required this.title, required this.text});
  final String asset;
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: VetColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: VetColors.border)),
        child: Row(children: [
          Image.asset(asset, width: 64, height: 64, fit: BoxFit.contain, filterQuality: FilterQuality.high),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(height: 5),
            Text(text, style: const TextStyle(color: VetColors.muted, height: 1.4)),
          ])),
        ]),
      );
}

class _AnimalChoice extends StatelessWidget {""",
    'animal group banner helper',
)
s = replace_once(
    s,
    "class _BrandLockup extends StatelessWidget {",
    """class _HeaderBrand extends StatelessWidget {
  const _HeaderBrand();
  @override
  Widget build(BuildContext context) => Row(
        textDirection: TextDirection.ltr,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SvgPicture.asset('assets/vet_ai_logo.svg', width: 72, height: 49, colorFilter: const ColorFilter.mode(VetColors.primary, BlendMode.srcIn)),
          const SizedBox(width: 9),
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Vet ', style: TextStyle(color: VetColors.text)),
              const TextSpan(text: 'AI', style: TextStyle(color: VetColors.primary)),
            ]),
            style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w900, letterSpacing: .1),
          ),
        ],
      );
}

class _BrandLockup extends StatelessWidget {""",
    'header brand helper',
)
p.write_text(s)

# 3) Store branded localized confirmation-email content in auth user metadata.
p = Path('lib/services/vet_backend.dart')
s = p.read_text()
s = replace_once(
    s,
    """    required String phone,
    required String preferredLanguage,
  }) {""",
    """    required String phone,
    required String preferredLanguage,
    required String emailSubject,
    required String emailHeading,
    required String emailBody,
    required String emailButton,
    required String emailFooter,
  }) {""",
    'backend signup signature',
)
s = replace_once(
    s,
    """        'phone': phone.trim(),
        'preferred_language': preferredLanguage,
      },""",
    """        'phone': phone.trim(),
        'preferred_language': preferredLanguage,
        'language': preferredLanguage,
        'brand_name': 'Vet AI',
        'email_subject': emailSubject,
        'email_heading': emailHeading,
        'email_body': emailBody,
        'email_button': emailButton,
        'email_footer': emailFooter,
      },""",
    'backend signup metadata',
)
p.write_text(s)

# 4) Use the approved animal art on the intro instead of the old doodle SVGs.
p = Path('lib/startup/vet_startup_experience.dart')
s = p.read_text()
s = s.replace("asset: 'assets/icons/cow.svg'", "asset: 'assets/icons/livestock_final.png'")
s = s.replace("asset: 'assets/icons/buffalo.svg'", "asset: 'assets/icons/livestock_final.png'")
s = s.replace("asset: 'assets/icons/chicken.svg'", "asset: 'assets/icons/poultry_final.png'")
s = s.replace("asset: 'assets/icons/dog.svg'", "asset: 'assets/icons/dog_final.png'")
s = replace_once(
    s,
    "SvgPicture.asset(data.asset, width: 92, height: 92),",
    "Image.asset(data.asset, width: 112, height: 112, fit: BoxFit.contain, filterQuality: FilterQuality.high),",
    'startup animal renderer',
)
p.write_text(s)

# 5) Keep the annotation action physically on the far right and easy to hit.
p = Path('lib/support/support_chat_v6.dart')
s = p.read_text()
old_controls = """              Row(children: [
                for (final color in colors)
                  Padding(
                    padding: const EdgeInsets.only(right: 9),
                    child: InkWell(
                      onTap: () => setState(() => selected = color),
                      borderRadius: BorderRadius.circular(30),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: selected == color ? VetColors.text : Colors.transparent, width: 3)),
                      ),
                    ),
                  ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: saving ? null : _save,
                  icon: saving ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_rounded),
                  label: Text(_t(context, 'Use image', 'استخدام الصورة', 'Afbeelding gebruiken')),
                ),
              ]),"""
new_controls = """              Row(children: [
                for (final color in colors)
                  Padding(
                    padding: const EdgeInsets.only(right: 9),
                    child: InkWell(
                      onTap: () => setState(() => selected = color),
                      borderRadius: BorderRadius.circular(30),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: selected == color ? VetColors.text : Colors.transparent, width: 3)),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: 260,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: saving ? null : _save,
                    icon: saving ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_rounded),
                    label: Text(_t(context, 'Use image', 'استخدام الصورة', 'Afbeelding gebruiken')),
                  ),
                ),
              ),"""
s = replace_once(s, old_controls, new_controls, 'annotation action position')
p.write_text(s)

# 6) New TestFlight build number after the reliability fixes.
p = Path('pubspec.yaml')
s = p.read_text()
s = replace_once(s, 'version: 0.6.0+8', 'version: 0.6.1+9', 'version bump')
p.write_text(s)

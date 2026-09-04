from pathlib import Path
import re

app_path = Path('lib/v5_app.dart')
text = app_path.read_text(encoding='utf-8')

# Restore the original professional header hierarchy: brand and controls share one row,
# farm/company identity is centered underneath. Row direction automatically mirrors in RTL.
pattern = re.compile(
    r"        SizedBox\(\n          height: 116,\n          child: Row\(.*?        const SizedBox\(height: 8\),",
    re.S,
)
replacement = """        Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const _HeaderBrand(),
                const Spacer(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
              ],
            ),
            const SizedBox(height: 12),
            Text(
              farm['farm_name']?.toString() ?? 'Vet AI',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            if ((farm['company_name']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                farm['company_name'].toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: VetColors.muted, fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),"""
text, count = pattern.subn(replacement, text, count=1)
if count != 1:
    raise SystemExit(f'Header patch expected 1 match, got {count}')

# Make the approved animal artwork visibly larger everywhere without changing the artwork itself.
replacements = {
    "Image.asset(asset(g), width: 34, height: 34": "Image.asset(asset(g), width: 44, height: 44",
    "Image.asset(asset, width: 64, height: 64": "Image.asset(asset, width: 90, height: 90",
    "Image.asset(asset,width:54,height:54": "Image.asset(asset,width:78,height:78",
    "Image.asset(asset,width:62,height:62": "Image.asset(asset,width:94,height:94",
}
for old, new in replacements.items():
    if old not in text:
        raise SystemExit(f'Missing expected icon size snippet: {old}')
    text = text.replace(old, new)

# Retry only transient provider failures automatically. This avoids making the user press Analyze
# repeatedly when the provider briefly rate-limits or times out.
old_analysis = """      final response = await VetBackend.instance.analyzeAssessment(newAssessmentId, language: Localizations.localeOf(context).languageCode);
      if (mounted) setState(() => result = response);"""
new_analysis = """      Map<String, dynamic> response = <String, dynamic>{};
      for (var attempt = 0; attempt < 3; attempt++) {
        response = await VetBackend.instance.analyzeAssessment(
          newAssessmentId,
          language: Localizations.localeOf(context).languageCode,
        );
        final code = response['code']?.toString();
        final transient = const <String>{
          'AI_PROVIDER_RATE_LIMIT',
          'AI_TIMEOUT',
          'AI_PROVIDER_ERROR',
        }.contains(code);
        if (!transient || attempt == 2) break;
        await Future<void>.delayed(Duration(milliseconds: attempt == 0 ? 1200 : 2500));
      }
      if (mounted) setState(() => result = response);"""
if old_analysis not in text:
    raise SystemExit('Analysis call patch target not found')
text = text.replace(old_analysis, new_analysis, 1)

app_path.write_text(text, encoding='utf-8')

pubspec = Path('pubspec.yaml')
pub = pubspec.read_text(encoding='utf-8')
pub, version_count = re.subn(r'^version:\s*[^\n]+$', 'version: 0.6.2+11', pub, count=1, flags=re.M)
if version_count != 1:
    raise SystemExit('Could not bump pubspec version')
pubspec.write_text(pub, encoding='utf-8')

print('V18 patch applied: header restored, animal icons enlarged, transient AI retries added, version set to 0.6.2+11')

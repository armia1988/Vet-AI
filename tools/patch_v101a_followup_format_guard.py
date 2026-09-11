from pathlib import Path

path = Path('lib/health/animal_health_center.dart')
text = path.read_text(encoding='utf-8')

marker = "Unsupported follow-up image format"
if marker not in text:
    anchor = """    final bytes = await image.readAsBytes();
    final name = image.name.toLowerCase();
    final extension = name.contains('.') ? name.split('.').last : 'jpg';
    final language = Localizations.localeOf(context).languageCode;
"""
    replacement = """    final name = image.name.toLowerCase();
    final extension = name.contains('.') ? name.split('.').last : 'jpg';
    const supportedExtensions = {'jpg', 'jpeg', 'png', 'webp'};
    if (!supportedExtensions.contains(extension)) {
      _showMessage(
        context,
        _t(
          context,
          'Unsupported follow-up image format. Use JPEG, PNG or WEBP.',
          'صيغة صورة المتابعة غير مدعومة. استخدم JPEG أو PNG أو WEBP.',
          'Niet-ondersteund follow-up afbeeldingsformaat. Gebruik JPEG, PNG of WEBP.',
        ),
      );
      notes.dispose();
      temperature.dispose();
      return;
    }
    final bytes = await image.readAsBytes();
    final language = Localizations.localeOf(context).languageCode;
"""
    if anchor not in text:
        raise SystemExit('V101a image format anchor not found')
    text = text.replace(anchor, replacement, 1)

for required in [
    "const supportedExtensions = {'jpg', 'jpeg', 'png', 'webp'};",
    'Unsupported follow-up image format',
    'final bytes = await image.readAsBytes();',
]:
    if required not in text:
        raise SystemExit(f'V101a marker missing: {required}')

path.write_text(text, encoding='utf-8')
print('V101a follow-up image format guard applied')

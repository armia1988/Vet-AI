from pathlib import Path

REPORT = Path('lib/analysis/vet_analysis_report.dart')
report = REPORT.read_text(encoding='utf-8')

helper_marker = '  Future<void> _configureSpeechAudioSession() async {'
if 'String _egyptianSpeechText(String input)' not in report:
    if helper_marker not in report:
        raise SystemExit('0.6.24 Egyptian voice patch: insertion marker not found')
    helper = r'''  String _egyptianSpeechText(String input) {
    var value = input;
    const replacements = <String, String>{
      'تظهر الصورة': 'باين في الصورة',
      'يظهر في الصورة': 'باين في الصورة',
      'توضح الصورة': 'باين في الصورة',
      'يعاني من': 'عنده',
      'تعاني من': 'عندها',
      'توجد': 'فيه',
      'يوجد': 'فيه',
      'لا توجد': 'مفيش',
      'لا يوجد': 'مفيش',
      'مع وجود': 'ومعه',
      'في هذه المرحلة': 'دلوقتي',
      'الآن': 'دلوقتي',
      'يجب': 'لازم',
      'ينبغي': 'الأفضل',
      'يُنصح': 'الأفضل',
      'ينصح': 'الأفضل',
      'تجنب': 'ابعد عن',
      'فورًا': 'على طول',
      'فوراً': 'على طول',
      'الحيوان المصاب': 'الحيوان اللي عنده الإصابة',
      'باقي القطيع': 'باقي القطيع',
      'احتمالية': 'احتمال',
      'منع العدوى': 'منع انتشار العدوى',
    };
    replacements.forEach((from, to) {
      value = value.replaceAll(from, to);
    });
    return value;
  }

'''
    report = report.replace(helper_marker, helper + helper_marker, 1)

old = '    text = _speechSafeText(text);'
new = """    if (widget.languageCode.toLowerCase().startsWith('ar')) {
      text = _egyptianSpeechText(text);
    }
    text = _speechSafeText(text);"""
if old in report:
    report = report.replace(old, new, 1)
elif "text = _egyptianSpeechText(text);" not in report:
    raise SystemExit('0.6.24 Egyptian voice patch: speech normalization call not found')

REPORT.write_text(report, encoding='utf-8')

check = REPORT.read_text(encoding='utf-8')
for marker in (
    'String _egyptianSpeechText(String input)',
    "text = _egyptianSpeechText(text);",
    "'تظهر الصورة': 'باين في الصورة'",
    "'يعاني من': 'عنده'",
    "'يجب': 'لازم'",
):
    if marker not in check:
        raise SystemExit(f'0.6.24 Egyptian voice verification missing: {marker}')

print('Vet AI 0.6.24 Egyptian spoken-Arabic normalization applied')

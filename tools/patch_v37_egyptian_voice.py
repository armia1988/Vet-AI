from pathlib import Path

REPORT = Path('lib/analysis/vet_analysis_report.dart')
report = REPORT.read_text(encoding='utf-8')

helper_marker = '  Future<void> _configureSpeechAudioSession() async {'
helper_start = report.find('  String _egyptianSpeechText(String input) {')
helper_end = report.find(helper_marker)
helper = r'''  String _egyptianSpeechText(String input) {
    var value = input;
    const replacements = <String, String>{
      'لا توجد': 'مفيش',
      'لا يوجد': 'مفيش',
      'تظهر الصورة': 'باين في الصورة',
      'يظهر في الصورة': 'باين في الصورة',
      'توضح الصورة': 'باين في الصورة',
      'يظهر على': 'باين على',
      'تظهر على': 'باين على',
      'يعاني من': 'عنده',
      'تعاني من': 'عندها',
      'مع وجود': 'ومعه',
      'بالإضافة إلى': 'وكمان',
      'بالإضافة ل': 'وكمان',
      'في هذه المرحلة': 'دلوقتي',
      'في المرحلة الحالية': 'دلوقتي',
      'الأكثر احتمالًا': 'أقرب احتمال',
      'الأكثر احتمالاً': 'أقرب احتمال',
      'الحالة الأكثر احتمالًا': 'أقرب حالة',
      'الحالة الأكثر احتمالاً': 'أقرب حالة',
      'الآن': 'دلوقتي',
      'يجب': 'لازم',
      'ينبغي': 'الأفضل',
      'يُنصح': 'الأفضل',
      'ينصح': 'الأفضل',
      'تجنب': 'ابعد عن',
      'تجنّب': 'ابعد عن',
      'فورًا': 'على طول',
      'فوراً': 'على طول',
      'على الفور': 'على طول',
      'الحيوان المصاب': 'الحيوان اللي عنده الإصابة',
      'الحيوانات المصابة': 'الحيوانات اللي عندها الإصابة',
      'احتمالية': 'احتمال',
      'منع العدوى': 'منع انتشار العدوى',
      'منع انتقال العدوى': 'منع انتشار العدوى',
      'توجد': 'فيه',
      'يوجد': 'فيه',
      'قم بعزل': 'اعزل',
      'عزل الحيوان': 'اعزل الحيوان',
      'ارتداء قفازات': 'البس قفازات',
      'ارتدِ قفازات': 'البس قفازات',
      'توفير مياه نظيفة': 'وفر مياه نظيفة',
      'توفير ماء نظيف': 'وفر مياه نظيفة',
      'توفير غذاء': 'وفر أكل',
      'توفير طعام': 'وفر أكل',
      'الغذاء': 'الأكل',
      'الطعام': 'الأكل',
      'مياه الشرب': 'المياه',
      'استشارة طبيب بيطري': 'كلم دكتور بيطري',
      'استشر طبيبًا بيطريًا': 'كلم دكتور بيطري',
      'استشر طبيب بيطري': 'كلم دكتور بيطري',
      'راقب الحيوان': 'خليك متابع الحيوان',
      'مراقبة الحيوان': 'متابعة الحيوان',
      'في حالة': 'لو',
      'إذا ظهرت': 'لو ظهرت',
      'إذا ظهر': 'لو ظهر',
      'إذا استمرت': 'لو استمرت',
      'إذا استمر': 'لو استمر',
      'حول فتحتي الأنف': 'حوالين فتحات الأنف',
      'حول الأنف': 'حوالين الأنف',
      'حول الفم': 'حوالين الفم',
      'قشور جافة': 'قشور ناشفة',
      'مخاط صديدي': 'إفرازات صديدية',
      'سيلان رغوي كثيف للعاب': 'لعاب كتير ورغوي',
      'سيلان اللعاب': 'لعاب نازل',
      'تقرحات': 'قروح',
      'بالقرب من': 'جنب',
      'قد يكون': 'ممكن يكون',
      'قد تكون': 'ممكن تكون',
      'من المحتمل': 'ممكن',
      'لا تلمس': 'متلمسش',
      'لا تستخدم': 'متستخدمش',
      'لا تعطي': 'متديش',
    };
    replacements.forEach((from, to) {
      value = value.replaceAll(from, to);
    });
    return value;
  }

'''

if helper_start >= 0 and helper_end > helper_start:
    report = report[:helper_start] + helper + report[helper_end:]
else:
    if helper_marker not in report:
        raise SystemExit('0.6.24 Egyptian voice patch: insertion marker not found')
    report = report.replace(helper_marker, helper + helper_marker, 1)

old = '    text = _speechSafeText(text);'
new = """    if (widget.languageCode.toLowerCase().startsWith('ar')) {
      text = _egyptianSpeechText(text);
    }
    text = _speechSafeText(text);"""
if 'text = _egyptianSpeechText(text);' not in report:
    if old in report:
        report = report.replace(old, new, 1)
    else:
        raise SystemExit('0.6.24 Egyptian voice patch: speech normalization call not found')

REPORT.write_text(report, encoding='utf-8')

check = REPORT.read_text(encoding='utf-8')
for marker in (
    'String _egyptianSpeechText(String input)',
    "'يظهر على': 'باين على'",
    "'بالإضافة إلى': 'وكمان'",
    "'ارتداء قفازات': 'البس قفازات'",
    "'استشارة طبيب بيطري': 'كلم دكتور بيطري'",
    "'سيلان رغوي كثيف للعاب': 'لعاب كتير ورغوي'",
):
    if marker not in check:
        raise SystemExit(f'0.6.24 Egyptian voice verification missing: {marker}')

print('Vet AI 0.6.24 consistent Egyptian spoken-Arabic normalization applied')

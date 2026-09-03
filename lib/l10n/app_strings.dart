import 'package:flutter/widgets.dart';

class AppStrings {
  AppStrings(this.locale);

  final Locale locale;

  static const supportedLocales = <Locale>[
    Locale('en'), Locale('ar'), Locale('zh'), Locale('es'), Locale('fr'), Locale('de'),
    Locale('nl'), Locale('it'), Locale('pt'), Locale('ru'), Locale('tr'), Locale('pl'),
    Locale('uk'), Locale('ro'), Locale('el'), Locale('sv'), Locale('no'), Locale('da'),
    Locale('fi'), Locale('cs'), Locale('sk'), Locale('hu'), Locale('bg'), Locale('hr'),
    Locale('sr'), Locale('sl'), Locale('he'), Locale('fa'), Locale('ur'), Locale('hi'),
    Locale('bn'), Locale('pa'), Locale('ta'), Locale('te'), Locale('ml'), Locale('mr'),
    Locale('gu'), Locale('kn'), Locale('th'), Locale('vi'), Locale('id'), Locale('ms'),
    Locale('fil'), Locale('ja'), Locale('ko'), Locale('sw'), Locale('am'), Locale('zu'),
  ];

  static Locale resolve(Locale? deviceLocale, Iterable<Locale> supported) {
    if (deviceLocale == null) return const Locale('en');
    for (final locale in supported) {
      if (locale.languageCode == deviceLocale.languageCode) return locale;
    }
    // Keep the device language code so remote catalog translation can serve it later.
    return Locale(deviceLocale.languageCode, deviceLocale.countryCode);
  }

  static AppStrings of(BuildContext context) => AppStrings(Localizations.localeOf(context));

  String _t(String key) {
    final lang = locale.languageCode;
    return _catalog[lang]?[key] ?? _catalog['en']![key] ?? key;
  }

  String get appName => _t('appName');
  String get tagline => _t('tagline');
  String get getStarted => _t('getStarted');
  String get createAccount => _t('createAccount');
  String get companyFarm => _t('companyFarm');
  String get animalsHousing => _t('animalsHousing');
  String get healthBaseline => _t('healthBaseline');
  String get subscription => _t('subscription');
  String get dashboard => _t('dashboard');
  String get livestock => _t('livestock');
  String get poultry => _t('poultry');
  String get dogs => _t('dogs');
  String get aiScan => _t('aiScan');
  String get sensors => _t('sensors');
  String get alerts => _t('alerts');
  String get history => _t('history');
  String get softwareOnly => _t('softwareOnly');
  String get smartMonitoring => _t('smartMonitoring');
  String get monthly => _t('monthly');
  String get annual => _t('annual');
  String get continueText => _t('continue');
  String get bodyTemperature => _t('bodyTemperature');
  String get barnTemperature => _t('barnTemperature');
  String get activity => _t('activity');
  String get herdDistance => _t('herdDistance');
  String get calving => _t('calving');
  String get noAlert => _t('noAlert');
}

const _catalog = <String, Map<String, String>>{
  'en': {
    'appName': 'Vet AI',
    'tagline': 'AI veterinary decision support & smart animal monitoring',
    'getStarted': 'Get started',
    'createAccount': 'Create account',
    'companyFarm': 'Company & farm',
    'animalsHousing': 'Animals & housing',
    'healthBaseline': 'Health baseline',
    'subscription': 'Subscription',
    'dashboard': 'Dashboard',
    'livestock': 'Livestock',
    'poultry': 'Poultry',
    'dogs': 'Dogs',
    'aiScan': 'AI Scan',
    'sensors': 'Sensors',
    'alerts': 'Alerts',
    'history': 'History',
    'softwareOnly': 'Vet AI Software',
    'smartMonitoring': 'Vet AI Smart Monitoring',
    'monthly': 'Monthly',
    'annual': 'Annual',
    'continue': 'Continue',
    'bodyTemperature': 'Body temperature',
    'barnTemperature': 'Barn temperature',
    'activity': 'Activity',
    'herdDistance': 'Distance from herd',
    'calving': 'Calving watch',
    'noAlert': 'No current alert',
  },
  'ar': {
    'appName': 'Vet AI',
    'tagline': 'دعم القرار البيطري بالذكاء الاصطناعي ومراقبة الحيوانات الذكية',
    'getStarted': 'ابدأ الآن',
    'createAccount': 'إنشاء الحساب',
    'companyFarm': 'الشركة والمزرعة',
    'animalsHousing': 'الحيوانات والعنابر',
    'healthBaseline': 'الحالة الصحية الأساسية',
    'subscription': 'الاشتراك',
    'dashboard': 'لوحة التحكم',
    'livestock': 'المواشي',
    'poultry': 'الدواجن',
    'dogs': 'الكلاب',
    'aiScan': 'فحص AI',
    'sensors': 'الحساسات',
    'alerts': 'الإنذارات',
    'history': 'السجل',
    'softwareOnly': 'برنامج Vet AI',
    'smartMonitoring': 'Vet AI مع المراقبة الذكية',
    'monthly': 'شهري',
    'annual': 'سنوي',
    'continue': 'متابعة',
    'bodyTemperature': 'حرارة الحيوان',
    'barnTemperature': 'حرارة العنبر',
    'activity': 'النشاط والحركة',
    'herdDistance': 'البعد عن القطيع',
    'calving': 'متابعة الولادة',
    'noAlert': 'لا يوجد إنذار حالي',
  },
  'zh': {
    'appName': 'Vet AI',
    'tagline': 'AI 兽医决策支持与智能动物监测',
    'getStarted': '开始使用',
    'createAccount': '创建账户',
    'companyFarm': '公司与农场',
    'animalsHousing': '动物与栏舍',
    'healthBaseline': '健康基线',
    'subscription': '订阅',
    'dashboard': '控制面板',
    'livestock': '牲畜',
    'poultry': '家禽',
    'dogs': '犬类',
    'aiScan': 'AI 检查',
    'sensors': '传感器',
    'alerts': '警报',
    'history': '历史记录',
    'softwareOnly': 'Vet AI 软件版',
    'smartMonitoring': 'Vet AI 智能监测版',
    'monthly': '每月',
    'annual': '每年',
    'continue': '继续',
    'bodyTemperature': '体温',
    'barnTemperature': '栏舍温度',
    'activity': '活动',
    'herdDistance': '离群距离',
    'calving': '分娩监测',
    'noAlert': '当前无警报',
  },
};

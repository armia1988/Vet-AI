import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/vet_backend.dart';
import 'theme/app_theme.dart';

class VetAIAppV2 extends StatelessWidget {
  const VetAIAppV2({super.key});

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
      home: const AuthGate(),
    );
  }
}

class V2Text {
  V2Text(this.locale);
  final Locale locale;

  static const supportedLocales = <Locale>[
    Locale('en'), Locale('ar'), Locale('zh'), Locale('nl'), Locale('de'),
    Locale('fr'), Locale('es'), Locale('it'), Locale('pt'), Locale('tr'),
    Locale('ru'), Locale('ja'), Locale('ko'), Locale('hi'),
  ];

  static V2Text of(BuildContext context) => V2Text(Localizations.localeOf(context));

  String t(String key) => _strings[locale.languageCode]?[key] ?? _strings['en']![key] ?? key;

  static const _strings = <String, Map<String, String>>{
    'en': {
      'tagline': 'Veterinary intelligence & smart animal monitoring',
      'create': 'Create account', 'signin': 'Sign in', 'email': 'Email',
      'password': 'Password', 'name': 'Full name', 'phone': 'Phone',
      'continue': 'Continue', 'farm': 'Farm setup', 'company': 'Company name',
      'farmName': 'Farm / site name', 'country': 'Country', 'region': 'Region',
      'workers': 'Workers', 'vets': 'Veterinarians', 'barns': 'Barns',
      'area': 'Indoor area m²', 'livestock': 'Livestock', 'poultry': 'Poultry',
      'dogs': 'Dogs', 'breeds': 'Breeds / strains', 'age': 'Age / production cycle',
      'purpose': 'Production purpose', 'ventilation': 'Ventilation / housing',
      'vaccines': 'Vaccination program', 'history': 'Disease / mortality history',
      'software': 'Software only', 'smart': 'Software + smart sensors',
      'monthly': 'Monthly', 'annual': 'Annual', 'saveFarm': 'Create farm',
      'home': 'Home', 'scan': 'AI Scan', 'sensors': 'Sensors', 'alerts': 'Alerts',
      'records': 'History', 'signout': 'Sign out', 'camera': 'Camera', 'gallery': 'Gallery',
      'upload': 'Upload case', 'symptoms': 'Symptoms / notes', 'noSensors': 'No sensors connected yet',
      'noAlerts': 'No alerts', 'noHistory': 'No assessments yet', 'addSensor': 'Add sensor',
      'awaitingAi': 'Case securely uploaded. AI clinical analysis is not enabled until the protected AI service is connected.',
      'confirmEmail': 'Check your email and confirm your account, then sign in.',
      'realData': 'Live data only — no demo readings', 'critical': 'Critical safety monitoring',
    },
    'ar': {
      'tagline': 'ذكاء بيطري ومراقبة ذكية لصحة الحيوان',
      'create': 'إنشاء حساب', 'signin': 'تسجيل الدخول', 'email': 'البريد الإلكتروني',
      'password': 'كلمة المرور', 'name': 'الاسم الكامل', 'phone': 'الهاتف',
      'continue': 'متابعة', 'farm': 'إعداد المزرعة', 'company': 'اسم الشركة',
      'farmName': 'اسم المزرعة / الموقع', 'country': 'الدولة', 'region': 'المنطقة',
      'workers': 'عدد العمال', 'vets': 'عدد الأطباء البيطريين', 'barns': 'عدد العنابر',
      'area': 'المساحة الداخلية م²', 'livestock': 'المواشي', 'poultry': 'الدواجن',
      'dogs': 'الكلاب', 'breeds': 'السلالات', 'age': 'العمر / دورة الإنتاج',
      'purpose': 'غرض التربية', 'ventilation': 'التهوية / نظام الإيواء',
      'vaccines': 'برنامج التحصينات', 'history': 'تاريخ الأمراض / النفوق',
      'software': 'البرنامج فقط', 'smart': 'البرنامج + الحساسات الذكية',
      'monthly': 'شهري', 'annual': 'سنوي', 'saveFarm': 'إنشاء المزرعة',
      'home': 'الرئيسية', 'scan': 'فحص AI', 'sensors': 'الحساسات', 'alerts': 'الإنذارات',
      'records': 'السجل', 'signout': 'تسجيل الخروج', 'camera': 'الكاميرا', 'gallery': 'الصور',
      'upload': 'رفع الحالة', 'symptoms': 'الأعراض / الملاحظات', 'noSensors': 'لا توجد حساسات متصلة حتى الآن',
      'noAlerts': 'لا توجد إنذارات', 'noHistory': 'لا توجد فحوصات حتى الآن', 'addSensor': 'إضافة حساس',
      'awaitingAi': 'تم رفع الحالة بأمان. لن ندّعي تشخيصًا حتى يتم توصيل خدمة الذكاء الاصطناعي الطبية المحمية.',
      'confirmEmail': 'افتح بريدك وأكد الحساب ثم سجل الدخول.',
      'realData': 'بيانات حقيقية فقط — بدون قراءات تجريبية', 'critical': 'مراقبة صحية حرجة',
    },
    'zh': {
      'tagline': '兽医智能与动物健康监测', 'create': '创建账户', 'signin': '登录',
      'email': '邮箱', 'password': '密码', 'name': '姓名', 'phone': '电话',
      'continue': '继续', 'farm': '农场设置', 'company': '公司名称', 'farmName': '农场名称',
      'country': '国家', 'region': '地区', 'workers': '员工数', 'vets': '兽医数',
      'barns': '栏舍数', 'area': '室内面积 m²', 'livestock': '牲畜', 'poultry': '家禽',
      'dogs': '犬', 'breeds': '品种', 'age': '年龄/生产周期', 'purpose': '饲养目的',
      'ventilation': '通风/饲养系统', 'vaccines': '免疫计划', 'history': '疾病/死亡史',
      'software': '仅软件', 'smart': '软件 + 智能传感器', 'monthly': '每月', 'annual': '每年',
      'saveFarm': '创建农场', 'home': '主页', 'scan': 'AI 检查', 'sensors': '传感器',
      'alerts': '警报', 'records': '历史', 'signout': '退出', 'camera': '相机', 'gallery': '相册',
      'upload': '上传病例', 'symptoms': '症状/备注', 'noSensors': '尚未连接传感器',
      'noAlerts': '无警报', 'noHistory': '暂无评估记录', 'addSensor': '添加传感器',
      'awaitingAi': '病例已安全上传。受保护的AI临床服务连接前不会生成诊断。',
      'confirmEmail': '请检查邮箱并确认账户，然后登录。', 'realData': '仅实时真实数据 — 无演示读数',
      'critical': '关键健康监测',
    },
    'nl': {
      'tagline': 'Veterinaire intelligentie & slimme diermonitoring', 'create': 'Account aanmaken',
      'signin': 'Inloggen', 'email': 'E-mail', 'password': 'Wachtwoord', 'name': 'Volledige naam',
      'phone': 'Telefoon', 'continue': 'Doorgaan', 'farm': 'Boerderij instellen', 'company': 'Bedrijfsnaam',
      'farmName': 'Boerderij / locatie', 'country': 'Land', 'region': 'Regio', 'workers': 'Medewerkers',
      'vets': 'Dierenartsen', 'barns': 'Stallen', 'area': 'Binnenoppervlak m²', 'livestock': 'Vee',
      'poultry': 'Pluimvee', 'dogs': 'Honden', 'breeds': 'Rassen', 'age': 'Leeftijd / productiecyclus',
      'purpose': 'Productiedoel', 'ventilation': 'Ventilatie / huisvesting', 'vaccines': 'Vaccinatieprogramma',
      'history': 'Ziekte- / sterftegeschiedenis', 'software': 'Alleen software', 'smart': 'Software + slimme sensoren',
      'monthly': 'Maandelijks', 'annual': 'Jaarlijks', 'saveFarm': 'Boerderij aanmaken', 'home': 'Home',
      'scan': 'AI-scan', 'sensors': 'Sensoren', 'alerts': 'Meldingen', 'records': 'Historie', 'signout': 'Uitloggen',
      'camera': 'Camera', 'gallery': 'Foto’s', 'upload': 'Casus uploaden', 'symptoms': 'Symptomen / notities',
      'noSensors': 'Nog geen sensoren verbonden', 'noAlerts': 'Geen meldingen', 'noHistory': 'Nog geen beoordelingen',
      'addSensor': 'Sensor toevoegen', 'awaitingAi': 'Casus veilig geüpload. Klinische AI-analyse blijft uit totdat de beveiligde AI-service is verbonden.',
      'confirmEmail': 'Bevestig je account via e-mail en log daarna in.', 'realData': 'Alleen echte live-data — geen demo-metingen',
      'critical': 'Kritieke gezondheidsmonitoring',
    },
    'de': {
      'tagline': 'Veterinärintelligenz & intelligente Tierüberwachung', 'create': 'Konto erstellen',
      'signin': 'Anmelden', 'email': 'E-Mail', 'password': 'Passwort', 'name': 'Vollständiger Name',
      'phone': 'Telefon', 'continue': 'Weiter', 'farm': 'Betrieb einrichten', 'company': 'Firmenname',
      'farmName': 'Betrieb / Standort', 'country': 'Land', 'region': 'Region', 'workers': 'Mitarbeiter',
      'vets': 'Tierärzte', 'barns': 'Ställe', 'area': 'Innenfläche m²', 'livestock': 'Nutztiere',
      'poultry': 'Geflügel', 'dogs': 'Hunde', 'breeds': 'Rassen', 'age': 'Alter / Produktionszyklus',
      'purpose': 'Produktionszweck', 'ventilation': 'Belüftung / Haltung', 'vaccines': 'Impfprogramm',
      'history': 'Krankheits- / Mortalitätsverlauf', 'software': 'Nur Software', 'smart': 'Software + intelligente Sensoren',
      'monthly': 'Monatlich', 'annual': 'Jährlich', 'saveFarm': 'Betrieb erstellen', 'home': 'Start', 'scan': 'AI-Scan',
      'sensors': 'Sensoren', 'alerts': 'Warnungen', 'records': 'Verlauf', 'signout': 'Abmelden', 'camera': 'Kamera',
      'gallery': 'Galerie', 'upload': 'Fall hochladen', 'symptoms': 'Symptome / Notizen', 'noSensors': 'Noch keine Sensoren verbunden',
      'noAlerts': 'Keine Warnungen', 'noHistory': 'Noch keine Untersuchungen', 'addSensor': 'Sensor hinzufügen',
      'awaitingAi': 'Fall sicher hochgeladen. Keine klinische AI-Diagnose, bis der geschützte AI-Dienst verbunden ist.',
      'confirmEmail': 'E-Mail bestätigen und danach anmelden.', 'realData': 'Nur echte Live-Daten — keine Demo-Messwerte', 'critical': 'Kritische Gesundheitsüberwachung',
    },
  };
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Stream<AuthState> _stream;
  @override
  void initState() {
    super.initState();
    _stream = VetBackend.instance.authChanges;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _stream,
      builder: (context, _) {
        if (!VetBackend.instance.signedIn) return const WelcomeAuthScreen();
        return FutureBuilder<Map<String, dynamic>?>(
          future: VetBackend.instance.myFarm(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            if (snapshot.hasError) {
              return Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('${snapshot.error}'))));
            }
            if (snapshot.data == null) return const FarmSetupScreen();
            return DashboardScreen(farm: snapshot.data!);
          },
        );
      },
    );
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 110});
  final double size;
  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset('assets/vet_ai_logo.svg', width: size, height: size * .68),
          const SizedBox(height: 8),
          Text.rich(TextSpan(children: [
            TextSpan(text: 'Vet ', style: TextStyle(fontSize: size * .24, fontWeight: FontWeight.w900, color: VetColors.text)),
            TextSpan(text: 'AI', style: TextStyle(fontSize: size * .24, fontWeight: FontWeight.w900, color: VetColors.primary)),
          ])),
        ],
      );
}

class WelcomeAuthScreen extends StatefulWidget {
  const WelcomeAuthScreen({super.key});
  @override
  State<WelcomeAuthScreen> createState() => _WelcomeAuthScreenState();
}

class _WelcomeAuthScreenState extends State<WelcomeAuthScreen> {
  bool createMode = true;
  bool busy = false;
  final name = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  final password = TextEditingController();

  @override
  void dispose() {
    name.dispose(); email.dispose(); phone.dispose(); password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final text = V2Text.of(context);
    if (email.text.trim().isEmpty || password.text.length < 6 || (createMode && name.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please complete the required fields. Password must be at least 6 characters.')));
      return;
    }
    setState(() => busy = true);
    try {
      if (createMode) {
        final response = await VetBackend.instance.signUp(
          email: email.text,
          password: password.text,
          fullName: name.text,
          phone: phone.text,
          preferredLanguage: Localizations.localeOf(context).languageCode,
        );
        if (!mounted) return;
        if (response.session == null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text.t('confirmEmail'))));
          setState(() => createMode = false);
        }
      } else {
        await VetBackend.instance.signIn(email: email.text, password: password.text);
      }
    } on AuthException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = V2Text.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 38, 24, 28),
          children: [
            const Center(child: BrandMark(size: 138)),
            const SizedBox(height: 12),
            Text(text.t('tagline'), textAlign: TextAlign.center, style: const TextStyle(color: VetColors.muted, fontSize: 16)),
            const SizedBox(height: 30),
            SegmentedButton<bool>(
              segments: [ButtonSegment(value: true, label: Text(text.t('create'))), ButtonSegment(value: false, label: Text(text.t('signin')))],
              selected: {createMode},
              onSelectionChanged: (value) => setState(() => createMode = value.first),
            ),
            const SizedBox(height: 20),
            if (createMode) ...[
              TextField(controller: name, textInputAction: TextInputAction.next, decoration: InputDecoration(labelText: text.t('name'))),
              const SizedBox(height: 12),
              TextField(controller: phone, keyboardType: TextInputType.phone, textInputAction: TextInputAction.next, decoration: InputDecoration(labelText: text.t('phone'))),
              const SizedBox(height: 12),
            ],
            TextField(controller: email, keyboardType: TextInputType.emailAddress, textInputAction: TextInputAction.next, autocorrect: false, decoration: InputDecoration(labelText: text.t('email'))),
            const SizedBox(height: 12),
            TextField(controller: password, obscureText: true, onSubmitted: (_) => submit(), decoration: InputDecoration(labelText: text.t('password'))),
            const SizedBox(height: 18),
            ElevatedButton(onPressed: busy ? null : submit, child: busy ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2)) : Text(createMode ? text.t('create') : text.t('signin'))),
            const SizedBox(height: 18),
            _SafeNotice(text: text.t('critical')),
          ],
        ),
      ),
    );
  }
}

class FarmSetupScreen extends StatefulWidget {
  const FarmSetupScreen({super.key});
  @override
  State<FarmSetupScreen> createState() => _FarmSetupScreenState();
}

class _FarmSetupScreenState extends State<FarmSetupScreen> {
  bool busy = false;
  String plan = 'software';
  String cycle = 'monthly';
  final company = TextEditingController(); final farmName = TextEditingController();
  final country = TextEditingController(); final region = TextEditingController();
  final workers = TextEditingController(text: '0'); final vets = TextEditingController(text: '0');
  final barns = TextEditingController(text: '1'); final area = TextEditingController(text: '0');
  final livestock = TextEditingController(text: '0'); final poultry = TextEditingController(text: '0'); final dogs = TextEditingController(text: '0');
  final breeds = TextEditingController(); final age = TextEditingController(); final purpose = TextEditingController();
  final ventilation = TextEditingController(); final vaccines = TextEditingController(); final diseaseHistory = TextEditingController();

  int i(TextEditingController c, [int fallback = 0]) => int.tryParse(c.text.trim()) ?? fallback;
  double d(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;

  Future<void> save() async {
    final text = V2Text.of(context);
    if (farmName.text.trim().isEmpty || i(barns, 1) < 1) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${text.t('farmName')} / ${text.t('barns')}')));
      return;
    }
    setState(() => busy = true);
    try {
      await VetBackend.instance.createFarm(FarmSetupPayload(
        companyName: company.text, farmName: farmName.text, country: country.text, region: region.text,
        workerCount: i(workers), veterinarianCount: i(vets), barnCount: i(barns, 1), totalIndoorAreaM2: d(area),
        livestockCount: i(livestock), poultryCount: i(poultry), dogCount: i(dogs), breeds: breeds.text,
        ageRange: age.text, productionPurpose: purpose.text, ventilationSystem: ventilation.text,
        vaccinationNotes: vaccines.text, diseaseHistory: diseaseHistory.text,
        subscriptionTier: plan, billingCycle: cycle,
      ));
      if (mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const AuthGate()), (_) => false);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(TextEditingController c, String label, {TextInputType? type, int lines = 1}) => TextField(controller: c, keyboardType: type, maxLines: lines, decoration: InputDecoration(labelText: label));

  @override
  Widget build(BuildContext context) {
    final t = V2Text.of(context);
    return Scaffold(
      appBar: AppBar(title: Row(children: [SvgPicture.asset('assets/vet_ai_logo.svg', width: 42), const SizedBox(width: 10), Text(t.t('farm'))])),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          field(company, t.t('company')), const SizedBox(height: 12), field(farmName, t.t('farmName')), const SizedBox(height: 12),
          Row(children: [Expanded(child: field(country, t.t('country'))), const SizedBox(width: 10), Expanded(child: field(region, t.t('region')))]), const SizedBox(height: 12),
          Row(children: [Expanded(child: field(workers, t.t('workers'), type: TextInputType.number)), const SizedBox(width: 10), Expanded(child: field(vets, t.t('vets'), type: TextInputType.number))]), const SizedBox(height: 12),
          Row(children: [Expanded(child: field(barns, t.t('barns'), type: TextInputType.number)), const SizedBox(width: 10), Expanded(child: field(area, t.t('area'), type: const TextInputType.numberWithOptions(decimal: true)))]), const SizedBox(height: 12),
          Row(children: [Expanded(child: field(livestock, t.t('livestock'), type: TextInputType.number)), const SizedBox(width: 8), Expanded(child: field(poultry, t.t('poultry'), type: TextInputType.number)), const SizedBox(width: 8), Expanded(child: field(dogs, t.t('dogs'), type: TextInputType.number))]),
          const SizedBox(height: 12), field(breeds, t.t('breeds')), const SizedBox(height: 12), field(age, t.t('age')), const SizedBox(height: 12), field(purpose, t.t('purpose')), const SizedBox(height: 12),
          field(ventilation, t.t('ventilation')), const SizedBox(height: 12), field(vaccines, t.t('vaccines'), lines: 3), const SizedBox(height: 12), field(diseaseHistory, t.t('history'), lines: 3),
          const SizedBox(height: 20),
          SegmentedButton<String>(segments: [ButtonSegment(value: 'software', label: Text(t.t('software'))), ButtonSegment(value: 'smart_monitoring', label: Text(t.t('smart')))], selected: {plan}, onSelectionChanged: (v) => setState(() => plan = v.first)),
          const SizedBox(height: 12),
          SegmentedButton<String>(segments: [ButtonSegment(value: 'monthly', label: Text(t.t('monthly'))), ButtonSegment(value: 'annual', label: Text(t.t('annual')))], selected: {cycle}, onSelectionChanged: (v) => setState(() => cycle = v.first)),
          const SizedBox(height: 20), ElevatedButton(onPressed: busy ? null : save, child: busy ? const CircularProgressIndicator() : Text(t.t('saveFarm'))),
          const SizedBox(height: 20), _SafeNotice(text: t.t('realData')),
        ],
      ),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.farm});
  final Map<String, dynamic> farm;
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int index = 0;
  @override
  Widget build(BuildContext context) {
    final t = V2Text.of(context);
    final farmId = widget.farm['id'] as String;
    final pages = [
      HomePanel(farm: widget.farm),
      ScanPanel(farmId: farmId),
      SensorsPanel(farmId: farmId),
      AlertsPanel(farmId: farmId),
      HistoryPanel(farmId: farmId),
    ];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: index, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (v) => setState(() => index = v),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: t.t('home')),
          NavigationDestination(icon: const Icon(Icons.document_scanner_outlined), selectedIcon: const Icon(Icons.document_scanner), label: t.t('scan')),
          NavigationDestination(icon: const Icon(Icons.sensors_outlined), selectedIcon: const Icon(Icons.sensors), label: t.t('sensors')),
          NavigationDestination(icon: const Icon(Icons.warning_amber_outlined), selectedIcon: const Icon(Icons.warning_amber), label: t.t('alerts')),
          NavigationDestination(icon: const Icon(Icons.history), label: t.t('records')),
        ],
      ),
    );
  }
}

class HomePanel extends StatelessWidget {
  const HomePanel({super.key, required this.farm});
  final Map<String, dynamic> farm;
  @override
  Widget build(BuildContext context) {
    final t = V2Text.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(children: [const BrandMark(size: 76), const Spacer(), IconButton(onPressed: () => VetBackend.instance.signOut(), tooltip: t.t('signout'), icon: const Icon(Icons.logout))]),
        const SizedBox(height: 18),
        Text(farm['farm_name']?.toString() ?? 'Vet AI', style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
        if ((farm['company_name']?.toString() ?? '').isNotEmpty) Text(farm['company_name'].toString(), style: const TextStyle(color: VetColors.muted)),
        const SizedBox(height: 20),
        _SafeNotice(text: t.t('realData')),
        const SizedBox(height: 18),
        Row(children: [Expanded(child: _CountCard(icon: Icons.agriculture, label: t.t('livestock'), value: farm['livestock_count'] ?? 0)), const SizedBox(width: 10), Expanded(child: _CountCard(icon: Icons.egg_alt_outlined, label: t.t('poultry'), value: farm['poultry_count'] ?? 0)), const SizedBox(width: 10), Expanded(child: _CountCard(icon: Icons.pets, label: t.t('dogs'), value: farm['dog_count'] ?? 0))]),
        const SizedBox(height: 18),
        Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Icon(Icons.health_and_safety, color: VetColors.primary), const SizedBox(width: 10), Text(t.t('critical'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900))]),
          const SizedBox(height: 10),
          Text('${t.t('barns')}: ${farm['barn_count'] ?? 1}\n${t.t('workers')}: ${farm['worker_count'] ?? 0}\n${t.t('vets')}: ${farm['veterinarian_count'] ?? 0}', style: const TextStyle(color: VetColors.muted, height: 1.6)),
        ]))),
      ],
    );
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({required this.icon, required this.label, required this.value});
  final IconData icon; final String label; final dynamic value;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8), child: Column(children: [Icon(icon, color: VetColors.primary, size: 30), const SizedBox(height: 8), Text('$value', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(label, textAlign: TextAlign.center, style: const TextStyle(color: VetColors.muted, fontSize: 11))])));
}

class ScanPanel extends StatefulWidget {
  const ScanPanel({super.key, required this.farmId});
  final String farmId;
  @override
  State<ScanPanel> createState() => _ScanPanelState();
}

class _ScanPanelState extends State<ScanPanel> {
  final picker = ImagePicker();
  final notes = TextEditingController();
  XFile? file; Uint8List? bytes; bool busy = false; String? result;

  Future<void> pick(ImageSource source) async {
    final chosen = await picker.pickImage(source: source, imageQuality: 88, maxWidth: 2200);
    if (chosen == null) return;
    final data = await chosen.readAsBytes();
    if (mounted) setState(() { file = chosen; bytes = data; result = null; });
  }

  Future<void> upload() async {
    if (file == null || bytes == null) return;
    setState(() => busy = true);
    try {
      final name = file!.name;
      final extension = name.contains('.') ? name.split('.').last : 'jpg';
      final path = await VetBackend.instance.uploadDiagnosticMedia(farmId: widget.farmId, bytes: bytes!, extension: extension);
      await VetBackend.instance.createDraftAssessment(farmId: widget.farmId, mediaPath: path, symptomNotes: notes.text);
      if (mounted) setState(() => result = V2Text.of(context).t('awaitingAi'));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() { notes.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final t = V2Text.of(context);
    return ListView(padding: const EdgeInsets.all(20), children: [
      _PanelHeader(title: t.t('scan'), icon: Icons.document_scanner),
      const SizedBox(height: 20),
      Container(height: 280, decoration: BoxDecoration(color: VetColors.surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0x4439E6B1))), child: bytes == null ? const Center(child: Icon(Icons.add_a_photo_outlined, size: 72, color: VetColors.muted)) : ClipRRect(borderRadius: BorderRadius.circular(24), child: Image.memory(bytes!, fit: BoxFit.cover, width: double.infinity))),
      const SizedBox(height: 14),
      Row(children: [Expanded(child: OutlinedButton.icon(onPressed: busy ? null : () => pick(ImageSource.camera), icon: const Icon(Icons.camera_alt_outlined), label: Text(t.t('camera')))), const SizedBox(width: 10), Expanded(child: OutlinedButton.icon(onPressed: busy ? null : () => pick(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: Text(t.t('gallery'))))]),
      const SizedBox(height: 14), TextField(controller: notes, maxLines: 4, decoration: InputDecoration(labelText: t.t('symptoms'))),
      const SizedBox(height: 14), ElevatedButton.icon(onPressed: file == null || busy ? null : upload, icon: const Icon(Icons.cloud_upload_outlined), label: busy ? const CircularProgressIndicator() : Text(t.t('upload'))),
      if (result != null) ...[const SizedBox(height: 16), _SafeNotice(text: result!)],
    ]);
  }
}

class SensorsPanel extends StatelessWidget {
  const SensorsPanel({super.key, required this.farmId});
  final String farmId;
  @override
  Widget build(BuildContext context) {
    final t = V2Text.of(context);
    return ListView(padding: const EdgeInsets.all(20), children: [
      _PanelHeader(title: t.t('sensors'), icon: Icons.sensors), const SizedBox(height: 20),
      const _SafeNotice(text: 'No simulated values are shown. Body temperature, activity, herd distance, barn climate and calving indicators will appear only after a verified hardware device is paired.'),
      const SizedBox(height: 20),
      Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(children: [const Icon(Icons.sensors_off_outlined, size: 68, color: VetColors.muted), const SizedBox(height: 12), Text(t.t('noSensors'), textAlign: TextAlign.center), const SizedBox(height: 16), ElevatedButton.icon(onPressed: () => showDialog(context: context, builder: (_) => AlertDialog(title: Text(t.t('addSensor')), content: const Text('Sensor provisioning will use a unique Vet AI device ID / QR code. Pairing is intentionally disabled until the first approved hardware prototype is available.'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))])), icon: const Icon(Icons.add_link), label: Text(t.t('addSensor')))]))),
    ]);
  }
}

class AlertsPanel extends StatelessWidget {
  const AlertsPanel({super.key, required this.farmId});
  final String farmId;
  @override
  Widget build(BuildContext context) {
    final t = V2Text.of(context);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: VetBackend.instance.recentAlerts(farmId),
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const <Map<String, dynamic>>[];
        return ListView(padding: const EdgeInsets.all(20), children: [
          _PanelHeader(title: t.t('alerts'), icon: Icons.warning_amber), const SizedBox(height: 20),
          if (snapshot.connectionState != ConnectionState.done) const Center(child: CircularProgressIndicator())
          else if (snapshot.hasError) Text('${snapshot.error}')
          else if (rows.isEmpty) _EmptyState(icon: Icons.verified_outlined, text: t.t('noAlerts'))
          else ...rows.map((row) => _AlertTile(row: row)),
        ]);
      },
    );
  }
}

class HistoryPanel extends StatelessWidget {
  const HistoryPanel({super.key, required this.farmId});
  final String farmId;
  @override
  Widget build(BuildContext context) {
    final t = V2Text.of(context);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: VetBackend.instance.recentAssessments(farmId),
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const <Map<String, dynamic>>[];
        return ListView(padding: const EdgeInsets.all(20), children: [
          _PanelHeader(title: t.t('records'), icon: Icons.history), const SizedBox(height: 20),
          if (snapshot.connectionState != ConnectionState.done) const Center(child: CircularProgressIndicator())
          else if (snapshot.hasError) Text('${snapshot.error}')
          else if (rows.isEmpty) _EmptyState(icon: Icons.history_toggle_off, text: t.t('noHistory'))
          else ...rows.map((row) => Card(child: ListTile(leading: const Icon(Icons.image_search, color: VetColors.primary), title: Text('Assessment ${row['id'].toString().substring(0, 8)}'), subtitle: Text('${row['status']} • ${row['risk']}\n${row['created_at']}', maxLines: 2), isThreeLine: true))),
        ]);
      },
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.row});
  final Map<String, dynamic> row;
  Color get color => switch (row['risk']) { 'red' => VetColors.red, 'orange' => VetColors.orange, 'yellow' => VetColors.yellow, _ => VetColors.muted };
  @override
  Widget build(BuildContext context) => Card(child: ListTile(leading: Icon(Icons.circle, color: color, size: 18), title: Text(row['title']?.toString() ?? 'Alert'), subtitle: Text(row['details']?.toString() ?? ''), trailing: Text(row['risk']?.toString().toUpperCase() ?? '')));
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.title, required this.icon});
  final String title; final IconData icon;
  @override
  Widget build(BuildContext context) => Row(children: [SvgPicture.asset('assets/vet_ai_logo.svg', width: 54), const SizedBox(width: 12), Icon(icon, color: VetColors.primary), const SizedBox(width: 8), Text(title, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900))]);
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});
  final IconData icon; final String text;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(34), child: Column(children: [Icon(icon, size: 62, color: VetColors.primary), const SizedBox(height: 12), Text(text, textAlign: TextAlign.center)])));
}

class _SafeNotice extends StatelessWidget {
  const _SafeNotice({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: const Color(0x1429C99A), borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0x4439E6B1))), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.shield_outlined, color: VetColors.primary), const SizedBox(width: 10), Expanded(child: Text(text, style: const TextStyle(color: VetColors.muted, height: 1.4))) ]));
}

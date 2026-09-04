import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n/vet_locale.dart';
import '../theme/app_theme.dart';

const vetStartupStrings = <String>[
  'Veterinary intelligence for faster decisions',
  'Scan an animal photo, add the symptoms and receive a cautious first assessment.',
  'Smart monitoring when sensors are connected',
  'Follow body temperature, environment, activity, feeding, rumination, resting and herd distance from real sensor data.',
  'One clear final veterinary report',
  'Answer the follow-up questions and Vet AI reviews trusted sources before preparing the final summary and PDF report.',
  'Your data stays under your control',
  'Vet AI asks before using location, camera, photos or files. You can refuse and continue where the feature allows it.',
  'Skip',
  'Next',
  'Start',
  'Share location with Vet AI?',
  'Location helps set the correct country and region for veterinary rules, disease alerts and local guidance. Vet AI only asks for access after you approve this message.',
  'Allow location',
  'Not now',
];

String _t(BuildContext context, String en, String ar, String nl) => VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

class VetStartupExperience extends StatefulWidget {
  const VetStartupExperience({super.key, required this.child});
  final Widget child;

  @override
  State<VetStartupExperience> createState() => _VetStartupExperienceState();
}

class _VetStartupExperienceState extends State<VetStartupExperience> {
  static const _introSeen = 'vet_ai_intro_seen_v1';
  static const _locationPrompted = 'vet_ai_location_prompted_v1';

  final pageController = PageController();
  int page = 0;
  bool splash = true;
  bool showIntro = false;
  bool showLocation = false;
  bool ready = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final started = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await VetLocaleController.instance.load();
    await VetTranslator.instance.load();

    final requested = VetLocaleController.instance.manualCode ?? WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    if (vetLanguages.any((l) => l.code == requested)) {
      await Future.any<void>([
        VetTranslator.instance.prepareLanguage(requested, {...vetCoreUiStrings, ...vetStartupStrings}),
        Future<void>.delayed(const Duration(seconds: 8)),
      ]);
    }

    final elapsed = DateTime.now().difference(started);
    if (elapsed < const Duration(milliseconds: 1200)) {
      await Future<void>.delayed(const Duration(milliseconds: 1200) - elapsed);
    }

    if (!mounted) return;
    setState(() {
      splash = false;
      showIntro = !(prefs.getBool(_introSeen) ?? false);
      showLocation = !showIntro && !(prefs.getBool(_locationPrompted) ?? false);
      ready = true;
    });
  }

  Future<void> _finishIntro({bool skip = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_introSeen, true);
    if (!mounted) return;
    setState(() {
      showIntro = false;
      showLocation = !(prefs.getBool(_locationPrompted) ?? false);
    });
  }

  Future<void> _locationChoice(bool allow) async {
    if (allow) {
      try {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
      } catch (_) {
        // The app continues even when location services are unavailable.
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_locationPrompted, true);
    if (mounted) setState(() => showLocation = false);
  }

  @override
  void dispose() {
    pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (splash || !ready) return const _VetBrandSplash();
    if (showIntro) return _intro(context);
    if (showLocation) return _location(context);
    return widget.child;
  }

  Widget _intro(BuildContext context) {
    final pages = <_IntroPageData>[
      _IntroPageData(
        icon: Icons.document_scanner_rounded,
        color: VetColors.blue,
        title: _t(context, 'Veterinary intelligence for faster decisions', 'ذكاء بيطري يساعدك تاخد قرار أسرع', 'Veterinaire intelligentie voor snellere beslissingen'),
        body: _t(context, 'Scan an animal photo, add the symptoms and receive a cautious first assessment.', 'صوّر الحيوان، ضيف الأعراض، وVet AI يديك تقييم أولي حذر من غير ما يدّعي تشخيص نهائي من صورة واحدة.', 'Scan een foto van het dier, voeg symptomen toe en ontvang een voorzichtige eerste beoordeling.'),
        asset: 'assets/icons/livestock_final.png',
      ),
      _IntroPageData(
        icon: Icons.sensors_rounded,
        color: VetColors.purple,
        title: _t(context, 'Smart monitoring when sensors are connected', 'مراقبة ذكية لما الحساسات الحقيقية تكون متوصلة', 'Slimme monitoring wanneer sensoren gekoppeld zijn'),
        body: _t(context, 'Follow body temperature, environment, activity, feeding, rumination, resting and herd distance from real sensor data.', 'تابع حرارة الجسم والجو، النشاط، الأكل، الاجترار، الراحة، والخروج عن القطيع من قراءات حقيقية للحساسات.', 'Volg lichaamstemperatuur, omgeving, activiteit, voeren, herkauwen, rust en afstand tot de kudde met echte sensordata.'),
        asset: 'assets/icons/livestock_final.png',
      ),
      _IntroPageData(
        icon: Icons.fact_check_rounded,
        color: VetColors.green,
        title: _t(context, 'One clear final veterinary report', 'تقرير بيطري نهائي واضح في مكان واحد', 'Eén duidelijk definitief veterinair rapport'),
        body: _t(context, 'Answer the follow-up questions and Vet AI reviews trusted sources before preparing the final summary and PDF report.', 'جاوب على أسئلة المتابعة، وبعدها Vet AI يراجع مصادر موثوقة ويجهز الخلاصة والتصرف المطلوب وتقرير PDF.', 'Beantwoord vervolgvragen; Vet AI controleert betrouwbare bronnen en maakt daarna de samenvatting en het PDF-rapport.'),
        asset: 'assets/icons/poultry_final.png',
      ),
      _IntroPageData(
        icon: Icons.privacy_tip_outlined,
        color: VetColors.orange,
        title: _t(context, 'Your data stays under your control', 'بياناتك وصورك بإذنك إنت', 'Je gegevens blijven onder jouw controle'),
        body: _t(context, 'Vet AI asks before using location, camera, photos or files. You can refuse and continue where the feature allows it.', 'قبل الموقع أو الكاميرا أو الصور أو الملفات، Vet AI هيطلب إذنك الأول. تقدر ترفض، ومش هنرفع حاجة من غير موافقتك.', 'Vet AI vraagt toestemming voordat locatie, camera, foto’s of bestanden worden gebruikt. Je kunt weigeren waar de functie dat toelaat.'),
        asset: 'assets/icons/dog_final.png',
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
              child: Row(
                children: [
                  const _StartupBrand(compact: true),
                  const Spacer(),
                  TextButton(onPressed: () => _finishIntro(skip: true), child: Text(_t(context, 'Skip', 'تخطي', 'Overslaan'))),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: pageController,
                itemCount: pages.length,
                onPageChanged: (value) => setState(() => page = value),
                itemBuilder: (context, index) => _IntroPage(data: pages[index]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 6, 22, 18),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(pages.length, (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: i == page ? 24 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: i == page ? pages[page].color : VetColors.border,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    )),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () {
                      if (page == pages.length - 1) {
                        _finishIntro();
                      } else {
                        pageController.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
                      }
                    },
                    icon: Icon(page == pages.length - 1 ? Icons.check_circle_outline_rounded : Icons.arrow_forward_rounded),
                    label: Text(page == pages.length - 1 ? _t(context, 'Start', 'ابدأ', 'Start') : _t(context, 'Next', 'التالي', 'Volgende')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _location(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
            child: Column(
              children: [
                const _StartupBrand(),
                const Spacer(),
                Container(
                  width: 118,
                  height: 118,
                  decoration: BoxDecoration(color: VetColors.softBlue, borderRadius: BorderRadius.circular(34)),
                  child: const Icon(Icons.location_on_rounded, size: 62, color: VetColors.blue),
                ),
                const SizedBox(height: 28),
                Text(_t(context, 'Share location with Vet AI?', 'تحب تسمح لـ Vet AI يعرف موقعك؟', 'Locatie delen met Vet AI?'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                const SizedBox(height: 14),
                Text(
                  _t(context, 'Location helps set the correct country and region for veterinary rules, disease alerts and local guidance. Vet AI only asks for access after you approve this message.', 'الموقع بيساعدنا نحدد الدولة والمنطقة الصح علشان التنبيهات والقواعد البيطرية تختلف من بلد لبلد. مش هنطلب صلاحية الموقع من الآيفون إلا بعد موافقتك هنا.', 'Locatie helpt het juiste land en de juiste regio te bepalen voor veterinaire regels, ziektewaarschuwingen en lokale adviezen. Vet AI vraagt pas systeemtoegang nadat je hier toestemming geeft.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, color: VetColors.muted, height: 1.55),
                ),
                const Spacer(),
                FilledButton.icon(onPressed: () => _locationChoice(true), icon: const Icon(Icons.my_location_rounded), label: Text(_t(context, 'Allow location', 'السماح بالموقع', 'Locatie toestaan'))),
                const SizedBox(height: 10),
                TextButton(onPressed: () => _locationChoice(false), child: Text(_t(context, 'Not now', 'مش دلوقتي', 'Niet nu'))),
              ],
            ),
          ),
        ),
      );
}

class _VetBrandSplash extends StatelessWidget {
  const _VetBrandSplash();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset('assets/vet_ai_logo.svg', width: 180),
                const SizedBox(height: 18),
                const Text('Vet AI', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: -.6)),
                const SizedBox(height: 8),
                Text('Veterinary Intelligence', style: TextStyle(fontSize: 15, color: VetColors.muted.withValues(alpha: .95), fontWeight: FontWeight.w700, letterSpacing: .6)),
              ],
            ),
          ),
        ),
      );
}

class _StartupBrand extends StatelessWidget {
  const _StartupBrand({this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset('assets/vet_ai_logo.svg', width: compact ? 58 : 96),
          SizedBox(width: compact ? 8 : 12),
          Text('Vet AI', style: TextStyle(fontSize: compact ? 24 : 34, fontWeight: FontWeight.w900)),
        ],
      );
}

class _IntroPageData {
  const _IntroPageData({required this.icon, required this.color, required this.title, required this.body, required this.asset});
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final String asset;
}

class _IntroPage extends StatelessWidget {
  const _IntroPage({required this.data});
  final _IntroPageData data;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 10),
        child: Column(
          children: [
            const Spacer(),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 430),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: VetColors.border),
                boxShadow: [BoxShadow(color: data.color.withValues(alpha: .12), blurRadius: 34, offset: const Offset(0, 14))],
              ),
              child: Column(
                children: [
                  Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(color: data.color.withValues(alpha: .11), borderRadius: BorderRadius.circular(40)),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Image.asset(data.asset, width: 112, height: 112, fit: BoxFit.contain, filterQuality: FilterQuality.high),
                        Positioned(right: 15, bottom: 15, child: CircleAvatar(radius: 22, backgroundColor: data.color, child: Icon(data.icon, color: Colors.white, size: 24))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(data.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, height: 1.15)),
                  const SizedBox(height: 14),
                  Text(data.body, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: VetColors.muted, height: 1.55)),
                ],
              ),
            ),
            const Spacer(),
          ],
        ),
      );
}

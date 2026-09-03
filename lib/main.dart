import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/app_strings.dart';
import 'models/vet_models.dart';
import 'services/sensor_gateway.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VetAiApp());
}

class VetAiApp extends StatelessWidget {
  const VetAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Vet AI',
      theme: buildVetTheme(),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      localeResolutionCallback: (deviceLocale, supported) =>
          AppStrings.resolve(deviceLocale, supported),
      home: const WelcomeScreen(),
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 126,
                height: 126,
                decoration: BoxDecoration(
                  color: VetColors.surface,
                  borderRadius: BorderRadius.circular(34),
                  border: Border.all(color: const Color(0x5539E6B1)),
                  boxShadow: const [
                    BoxShadow(color: Color(0x2239E6B1), blurRadius: 36, spreadRadius: 3),
                  ],
                ),
                child: const Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(Icons.pets_rounded, color: VetColors.primary, size: 70),
                    Positioned(right: 20, top: 18, child: Icon(Icons.monitor_heart_outlined, color: VetColors.primary, size: 34)),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: 'Vet ', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w900)),
                    TextSpan(text: 'AI', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w900, color: VetColors.primary)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(s.tagline, textAlign: TextAlign.center, style: const TextStyle(color: VetColors.muted, fontSize: 16, height: 1.5)),
              const SizedBox(height: 38),
              Row(
                children: [
                  _SpeciesPill(icon: Icons.agriculture_outlined, label: s.livestock),
                  const SizedBox(width: 8),
                  _SpeciesPill(icon: Icons.egg_outlined, label: s.poultry),
                  const SizedBox(width: 8),
                  _SpeciesPill(icon: Icons.pets_outlined, label: s.dogs),
                ],
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const OnboardingScreen())),
                child: Text(s.getStarted),
              ),
              const SizedBox(height: 14),
              const Text('Veterinary decision support — not a substitute for laboratory confirmation or a veterinarian.', textAlign: TextAlign.center, style: TextStyle(color: VetColors.muted, fontSize: 11, height: 1.35)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpeciesPill extends StatelessWidget {
  const _SpeciesPill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(color: VetColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0x332E8170))),
        child: Column(children: [Icon(icon, color: VetColors.primary), const SizedBox(height: 6), Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))]),
      ),
    );
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final profile = FarmProfile();
  final controller = PageController();
  int page = 0;

  void next() {
    if (page < 4) {
      controller.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    } else {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => DashboardScreen(profile: profile)));
    }
  }

  InputDecoration deco(String label, {String? hint}) => InputDecoration(labelText: label, hintText: hint);

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final titles = [s.createAccount, s.companyFarm, s.animalsHousing, s.healthBaseline, s.subscription];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(titles[page], style: const TextStyle(fontWeight: FontWeight.w800)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: LinearProgressIndicator(value: (page + 1) / 5, minHeight: 5, borderRadius: BorderRadius.circular(20), backgroundColor: VetColors.surface2),
          ),
        ),
      ),
      body: PageView(
        controller: controller,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: (v) => setState(() => page = v),
        children: [
          _pageAccount(),
          _pageCompany(),
          _pageAnimals(),
          _pageHealth(),
          _pagePlan(s),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: ElevatedButton(onPressed: next, child: Text(page == 4 ? s.dashboard : s.continueText)),
        ),
      ),
    );
  }

  Widget _pageAccount() => _FormPage(children: [
        TextField(onChanged: (v) => profile.ownerName = v, decoration: deco('Full name / الاسم الكامل')),
        TextField(onChanged: (v) => profile.email = v, keyboardType: TextInputType.emailAddress, decoration: deco('Email')),
        TextField(onChanged: (v) => profile.phone = v, keyboardType: TextInputType.phone, decoration: deco('Phone')),
        TextField(obscureText: true, decoration: deco('Password')),
        const _InfoCard(icon: Icons.language, title: 'Automatic language', text: 'Vet AI reads the phone language automatically. Translation catalogs are versioned so veterinary terminology can be medically reviewed.'),
      ]);

  Widget _pageCompany() => _FormPage(children: [
        TextField(onChanged: (v) => profile.companyName = v, decoration: deco('Company / farm company name')),
        TextField(onChanged: (v) => profile.farmName = v, decoration: deco('Farm / site name')),
        TextField(onChanged: (v) => profile.country = v, decoration: deco('Country')),
        TextField(onChanged: (v) => profile.region = v, decoration: deco('Region / governorate / state')),
        Row(children: [
          Expanded(child: TextField(onChanged: (v) => profile.workers = int.tryParse(v) ?? 0, keyboardType: TextInputType.number, decoration: deco('Workers'))),
          const SizedBox(width: 12),
          Expanded(child: TextField(onChanged: (v) => profile.veterinarians = int.tryParse(v) ?? 0, keyboardType: TextInputType.number, decoration: deco('Vets'))),
        ]),
      ]);

  Widget _pageAnimals() => _FormPage(children: [
        const Text('Select animal groups', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        _groupTile(AnimalGroup.livestock, 'Livestock / المواشي', Icons.agriculture_outlined),
        _groupTile(AnimalGroup.poultry, 'Poultry / الدواجن', Icons.egg_outlined),
        _groupTile(AnimalGroup.dogs, 'Dogs / الكلاب', Icons.pets_outlined),
        Row(children: [
          Expanded(child: TextField(onChanged: (v) => profile.barns = int.tryParse(v) ?? 1, keyboardType: TextInputType.number, decoration: deco('Barns / houses'))),
          const SizedBox(width: 12),
          Expanded(child: TextField(onChanged: (v) => profile.totalIndoorAreaM2 = double.tryParse(v) ?? 0, keyboardType: TextInputType.number, decoration: deco('Indoor m²'))),
        ]),
        Row(children: [
          Expanded(child: TextField(onChanged: (v) => profile.livestockCount = int.tryParse(v) ?? 0, keyboardType: TextInputType.number, decoration: deco('Livestock count'))),
          const SizedBox(width: 12),
          Expanded(child: TextField(onChanged: (v) => profile.poultryCount = int.tryParse(v) ?? 0, keyboardType: TextInputType.number, decoration: deco('Poultry count'))),
        ]),
        TextField(onChanged: (v) => profile.dogCount = int.tryParse(v) ?? 0, keyboardType: TextInputType.number, decoration: deco('Dogs count')),
        TextField(onChanged: (v) => profile.breeds = v, decoration: deco('Breeds / strains')),
        TextField(onChanged: (v) => profile.ageRange = v, decoration: deco('Age / production cycle')),
        TextField(onChanged: (v) => profile.productionPurpose = v, decoration: deco('Purpose', hint: 'Dairy, beef, broiler, layer, breeding…')),
        TextField(onChanged: (v) => profile.ventilation = v, decoration: deco('Ventilation / housing system')),
      ]);

  Widget _pageHealth() => _FormPage(children: [
        TextField(onChanged: (v) => profile.vaccinationNotes = v, maxLines: 4, decoration: deco('Vaccination program / التحصينات')),
        TextField(onChanged: (v) => profile.diseaseHistory = v, maxLines: 4, decoration: deco('Previous disease / mortality history')),
        const _InfoCard(icon: Icons.health_and_safety_outlined, title: 'Health baseline', text: 'Vet AI will learn normal temperature, activity, feeding, rumination, resting and movement patterns per animal or flock, then flag meaningful deviations.'),
        const _InfoCard(icon: Icons.science_outlined, title: 'Confirmed diagnoses matter', text: 'Veterinarian and laboratory-confirmed outcomes can be stored separately from AI suspicion to improve future validation without treating an AI guess as ground truth.'),
      ]);

  Widget _pagePlan(AppStrings s) => _FormPage(children: [
        const Text('Choose your monitoring level', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        _planCard(SubscriptionTier.software, s.softwareOnly, 'AI photo/video assessment, farm records, risk alerts, history and reports.', Icons.auto_awesome_outlined),
        _planCard(SubscriptionTier.smartMonitoring, s.smartMonitoring, 'Everything in Software + body/environment sensors, behavior tracking, distance-from-herd alerts and calving watch.', Icons.sensors_outlined),
        const SizedBox(height: 4),
        SegmentedButton<BillingCycle>(
          segments: [ButtonSegment(value: BillingCycle.monthly, label: Text(s.monthly)), ButtonSegment(value: BillingCycle.annual, label: Text(s.annual))],
          selected: {profile.billingCycle},
          onSelectionChanged: (v) => setState(() => profile.billingCycle = v.first),
        ),
        const _InfoCard(icon: Icons.inventory_2_outlined, title: 'Smart hardware', text: 'Sensor hardware is a separate kit; the monitoring subscription covers telemetry, analytics, alerts and cloud services.'),
      ]);

  Widget _groupTile(AnimalGroup group, String title, IconData icon) {
    final selected = profile.groups.contains(group);
    return InkWell(
      onTap: () => setState(() => selected ? profile.groups.remove(group) : profile.groups.add(group)),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: selected ? const Color(0x1939E6B1) : VetColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: selected ? VetColors.primary : const Color(0x332E8170))),
        child: Row(children: [Icon(icon, color: VetColors.primary), const SizedBox(width: 12), Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))), Icon(selected ? Icons.check_circle : Icons.circle_outlined, color: selected ? VetColors.primary : VetColors.muted)]),
      ),
    );
  }

  Widget _planCard(SubscriptionTier tier, String title, String text, IconData icon) {
    final selected = profile.subscriptionTier == tier;
    return InkWell(
      onTap: () => setState(() => profile.subscriptionTier = tier),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: selected ? const Color(0x1939E6B1) : VetColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: selected ? VetColors.primary : const Color(0x332E8170), width: selected ? 1.5 : 1)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: VetColors.primary, size: 30), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)), const SizedBox(height: 6), Text(text, style: const TextStyle(color: VetColors.muted, height: 1.45))])), const SizedBox(width: 8), Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? VetColors.primary : VetColors.muted)]),
      ),
    );
  }
}

class _FormPage extends StatelessWidget {
  const _FormPage({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(20, 28, 20, 30), children: children.expand((w) => [w, const SizedBox(height: 14)]).toList());
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0x1229C99A), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0x3339E6B1))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: VetColors.primary), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 5), Text(text, style: const TextStyle(color: VetColors.muted, height: 1.4))]))]),
      );
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.profile});
  final FarmProfile profile;
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final pages = [HomePanel(profile: widget.profile), const AiScanPanel(), const SensorsPanel(), const AlertsPanel(), const HistoryPanel()];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: index, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (v) => setState(() => index = v),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.grid_view_rounded), label: s.dashboard),
          NavigationDestination(icon: const Icon(Icons.center_focus_strong), label: s.aiScan),
          NavigationDestination(icon: const Icon(Icons.sensors), label: s.sensors),
          NavigationDestination(icon: const Icon(Icons.notifications_active_outlined), label: s.alerts),
          NavigationDestination(icon: const Icon(Icons.history), label: s.history),
        ],
      ),
    );
  }
}

class HomePanel extends StatelessWidget {
  const HomePanel({super.key, required this.profile});
  final FarmProfile profile;
  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(children: [
          Container(width: 46, height: 46, decoration: BoxDecoration(color: VetColors.surface, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.pets, color: VetColors.primary)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Vet AI', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)), Text(profile.farmName.isEmpty ? s.dashboard : profile.farmName, style: const TextStyle(color: VetColors.muted))])),
          IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none_rounded)),
        ]),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF123F3A), Color(0xFF0D292B)]), borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0x4439E6B1))),
          child: Row(children: [const Icon(Icons.verified_user_outlined, color: VetColors.green, size: 32), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s.noAlert, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)), const SizedBox(height: 4), const Text('Smart Monitoring checks behavior, temperature, movement and environment continuously when sensors are connected.', style: TextStyle(color: VetColors.muted, height: 1.4))]))]),
        ),
        const SizedBox(height: 20),
        Text('Animal groups', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        Row(children: [Expanded(child: _GroupCard(icon: Icons.agriculture_outlined, title: s.livestock, count: profile.livestockCount)), const SizedBox(width: 10), Expanded(child: _GroupCard(icon: Icons.egg_outlined, title: s.poultry, count: profile.poultryCount)), const SizedBox(width: 10), Expanded(child: _GroupCard(icon: Icons.pets_outlined, title: s.dogs, count: profile.dogCount))]),
        const SizedBox(height: 20),
        Text('Today', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        const Row(children: [Expanded(child: _MetricCard(value: '0', label: 'Red alerts', icon: Icons.warning_amber_rounded)), SizedBox(width: 10), Expanded(child: _MetricCard(value: '0', label: 'Orange alerts', icon: Icons.notifications_active_outlined)), SizedBox(width: 10), Expanded(child: _MetricCard(value: '—', label: 'Sensors online', icon: Icons.sensors))]),
        const SizedBox(height: 18),
        const _InfoCard(icon: Icons.psychology_alt_outlined, title: 'Early anomaly engine', text: 'Vet AI compares each animal or flock with its own baseline instead of relying only on a generic threshold. Large deviations can trigger an early warning before obvious clinical signs are visible.'),
      ],
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.icon, required this.title, required this.count});
  final IconData icon;
  final String title;
  final int count;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: VetColors.surface, borderRadius: BorderRadius.circular(20)), child: Column(children: [Icon(icon, color: VetColors.primary, size: 30), const SizedBox(height: 10), Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)), const SizedBox(height: 3), Text('$count', style: const TextStyle(color: VetColors.muted))]));
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.value, required this.label, required this.icon});
  final String value;
  final String label;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: VetColors.surface, borderRadius: BorderRadius.circular(18)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: VetColors.primary), const SizedBox(height: 8), Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)), Text(label, style: const TextStyle(color: VetColors.muted, fontSize: 11))]));
}

class AiScanPanel extends StatelessWidget {
  const AiScanPanel({super.key});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
        const Text('AI Health Scan', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        const Text('Use a clear photo or video. Vet AI will first verify image quality, extract visible signs, ask targeted symptom questions, and combine them with history and sensor data.', style: TextStyle(color: VetColors.muted, height: 1.5)),
        const SizedBox(height: 20),
        Container(height: 250, decoration: BoxDecoration(color: VetColors.surface, borderRadius: BorderRadius.circular(26), border: Border.all(color: const Color(0x4439E6B1))), child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_a_photo_outlined, color: VetColors.primary, size: 58), SizedBox(height: 14), Text('Take photo / video', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)), SizedBox(height: 6), Text('or upload from device', style: TextStyle(color: VetColors.muted))])),
        const SizedBox(height: 18),
        const _InfoCard(icon: Icons.rule_folder_outlined, title: 'Safety-first output', text: 'Results will show observed signs, risk level, differential possibilities, isolation guidance, next veterinary action and whether laboratory confirmation is required. The model must be allowed to answer “insufficient data”.'),
      ]);
}

class SensorsPanel extends StatefulWidget {
  const SensorsPanel({super.key});
  @override
  State<SensorsPanel> createState() => _SensorsPanelState();
}

class _SensorsPanelState extends State<SensorsPanel> {
  final gateway = DemoSensorGateway();
  late final Stream<SensorSnapshot> stream;

  @override
  void initState() {
    super.initState();
    gateway.connect();
    stream = gateway.watchAnimal('Cow A-205');
  }

  @override
  void dispose() {
    gateway.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SensorSnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        final x = snapshot.data;
        return ListView(padding: const EdgeInsets.all(20), children: [
          const Text('Smart Monitoring', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          const Text('Live sensor architecture preview — real collars/tags will replace the demo gateway without changing this screen.', style: TextStyle(color: VetColors.muted, height: 1.4)),
          const SizedBox(height: 20),
          _SensorHeader(online: x != null),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.35,
            children: [
              _SensorMetric(icon: Icons.thermostat, title: 'Body temperature', value: x == null ? '—' : '${x.bodyTemperatureC.toStringAsFixed(1)} °C'),
              _SensorMetric(icon: Icons.home_outlined, title: 'Barn climate', value: x == null ? '—' : '${x.ambientTemperatureC.toStringAsFixed(1)} °C · ${x.humidityPercent.toStringAsFixed(0)}%'),
              _SensorMetric(icon: Icons.directions_walk, title: 'Activity', value: x == null ? '—' : '${(x.activityIndex * 100).round()}% · ${x.steps} steps'),
              _SensorMetric(icon: Icons.social_distance, title: 'Distance from herd', value: x == null ? '—' : '${x.distanceFromHerdMeters.toStringAsFixed(1)} m'),
              _SensorMetric(icon: Icons.restaurant_outlined, title: 'Feeding / rumination', value: x == null ? '—' : '${x.feedingMinutesToday} / ${x.ruminationMinutesToday} min'),
              _SensorMetric(icon: Icons.child_friendly_outlined, title: 'Calving watch', value: x == null ? '—' : '${x.calvingRiskPercent.toStringAsFixed(0)}% signal score'),
            ],
          ),
          const SizedBox(height: 18),
          const _InfoCard(icon: Icons.hub_outlined, title: 'Planned telemetry', text: 'Body temperature, ambient temperature/humidity, accelerometer/IMU activity, lying/standing, feeding/rumination, herd-distance/geofencing, location, sound/environment signals and calving-related behavior can enter one normalized Sensor Gateway.'),
        ]);
      },
    );
  }
}

class _SensorHeader extends StatelessWidget {
  const _SensorHeader({required this.online});
  final bool online;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: VetColors.surface, borderRadius: BorderRadius.circular(20)), child: Row(children: [Container(width: 42, height: 42, decoration: BoxDecoration(color: const Color(0x1739E6B1), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.agriculture_outlined, color: VetColors.primary)), const SizedBox(width: 12), const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Cow A-205', style: TextStyle(fontWeight: FontWeight.w900)), Text('Smart collar + barn gateway', style: TextStyle(color: VetColors.muted, fontSize: 12))])), Icon(Icons.circle, size: 11, color: online ? VetColors.green : VetColors.muted), const SizedBox(width: 5), Text(online ? 'LIVE' : 'WAITING', style: TextStyle(color: online ? VetColors.green : VetColors.muted, fontWeight: FontWeight.w900, fontSize: 11))]));
}

class _SensorMetric extends StatelessWidget {
  const _SensorMetric({required this.icon, required this.title, required this.value});
  final IconData icon;
  final String title;
  final String value;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: VetColors.surface, borderRadius: BorderRadius.circular(18)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: VetColors.primary, size: 25), const SizedBox(height: 8), Text(title, style: const TextStyle(color: VetColors.muted, fontSize: 11)), const SizedBox(height: 3), Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))]));
}

class AlertsPanel extends StatelessWidget {
  const AlertsPanel({super.key});
  @override
  Widget build(BuildContext context) => const _EmptyPanel(icon: Icons.notifications_active_outlined, title: 'Risk Alerts', text: 'Red, orange and yellow alerts will be ranked here by urgency, animal/flock and barn. No alert is generated from a single threshold without context.');
}

class HistoryPanel extends StatelessWidget {
  const HistoryPanel({super.key});
  @override
  Widget build(BuildContext context) => const _EmptyPanel(icon: Icons.history, title: 'Health History', text: 'Scans, symptoms, veterinary assessments, lab confirmations, treatments and sensor trends will form a longitudinal record for every animal or flock.');
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(34), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: VetColors.primary, size: 66), const SizedBox(height: 18), Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)), const SizedBox(height: 10), Text(text, textAlign: TextAlign.center, style: const TextStyle(color: VetColors.muted, height: 1.5))])));
}

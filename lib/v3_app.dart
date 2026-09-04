import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/vet_backend.dart';
import 'theme/app_theme.dart';
import 'v2_app.dart'
    show
        V2Text,
        WelcomeAuthScreen,
        FarmSetupScreen,
        HomePanel,
        SensorsPanel,
        AlertsPanel;

class VetAIAppV3 extends StatelessWidget {
  const VetAIAppV3({super.key});

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
      home: const V3AuthGate(),
    );
  }
}

class V3AuthGate extends StatefulWidget {
  const V3AuthGate({super.key});

  @override
  State<V3AuthGate> createState() => _V3AuthGateState();
}

class _V3AuthGateState extends State<V3AuthGate> {
  late final Stream<AuthState> _authStream;

  @override
  void initState() {
    super.initState();
    _authStream = VetBackend.instance.authChanges;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _authStream,
      builder: (context, _) {
        if (!VetBackend.instance.signedIn) return const WelcomeAuthScreen();
        return FutureBuilder<Map<String, dynamic>?>(
          future: VetBackend.instance.myFarm(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('${snapshot.error}'),
                  ),
                ),
              );
            }
            if (snapshot.data == null) return const FarmSetupScreen();
            return V3DashboardScreen(farm: snapshot.data!);
          },
        );
      },
    );
  }
}

class V3DashboardScreen extends StatefulWidget {
  const V3DashboardScreen({super.key, required this.farm});

  final Map<String, dynamic> farm;

  @override
  State<V3DashboardScreen> createState() => _V3DashboardScreenState();
}

class _V3DashboardScreenState extends State<V3DashboardScreen> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final t = V2Text.of(context);
    final farmId = widget.farm['id'] as String;
    final pages = <Widget>[
      HomePanel(farm: widget.farm),
      V3ScanPanel(farm: widget.farm),
      SensorsPanel(farmId: farmId),
      AlertsPanel(farmId: farmId),
      V3HistoryPanel(farmId: farmId),
    ];

    return Scaffold(
      body: SafeArea(child: IndexedStack(index: index, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: t.t('home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.document_scanner_outlined),
            selectedIcon: const Icon(Icons.document_scanner),
            label: t.t('scan'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.sensors_outlined),
            selectedIcon: const Icon(Icons.sensors),
            label: t.t('sensors'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.warning_amber_outlined),
            selectedIcon: const Icon(Icons.warning_amber),
            label: t.t('alerts'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.history),
            label: t.t('records'),
          ),
        ],
      ),
    );
  }
}

class V3ScanPanel extends StatefulWidget {
  const V3ScanPanel({super.key, required this.farm});

  final Map<String, dynamic> farm;

  @override
  State<V3ScanPanel> createState() => _V3ScanPanelState();
}

class _V3ScanPanelState extends State<V3ScanPanel> {
  final ImagePicker picker = ImagePicker();
  final TextEditingController notes = TextEditingController();

  XFile? file;
  Uint8List? bytes;
  bool busy = false;
  Map<String, dynamic>? analysis;
  String? errorMessage;
  late String animalGroup;

  @override
  void initState() {
    super.initState();
    final livestock = (widget.farm['livestock_count'] as num?)?.toInt() ?? 0;
    final poultry = (widget.farm['poultry_count'] as num?)?.toInt() ?? 0;
    final dogs = (widget.farm['dog_count'] as num?)?.toInt() ?? 0;
    animalGroup = livestock > 0
        ? 'livestock'
        : poultry > 0
            ? 'poultry'
            : dogs > 0
                ? 'dogs'
                : 'livestock';
  }

  Future<void> pick(ImageSource source) async {
    final chosen = await picker.pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 2200,
    );
    if (chosen == null) return;
    final data = await chosen.readAsBytes();
    if (!mounted) return;
    setState(() {
      file = chosen;
      bytes = data;
      analysis = null;
      errorMessage = null;
    });
  }

  Future<void> analyze() async {
    if (file == null || bytes == null) return;
    setState(() {
      busy = true;
      analysis = null;
      errorMessage = null;
    });

    try {
      final name = file!.name;
      final extension = name.contains('.') ? name.split('.').last : 'jpg';
      final farmId = widget.farm['id'] as String;
      final path = await VetBackend.instance.uploadDiagnosticMedia(
        farmId: farmId,
        bytes: bytes!,
        extension: extension,
      );
      final assessmentId = await VetBackend.instance.createDraftAssessment(
        farmId: farmId,
        mediaPath: path,
        symptomNotes: notes.text,
        animalGroup: animalGroup,
      );
      final result = await VetBackend.instance.analyzeAssessment(
        assessmentId,
        language: Localizations.localeOf(context).languageCode,
      );
      if (!mounted) return;
      setState(() => analysis = result);
    } catch (error) {
      if (!mounted) return;
      setState(() => errorMessage = _friendlyError(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _friendlyError(Object error) {
    final raw = error.toString();
    if (raw.contains('429')) {
      return _l(
        'AI analysis is temporarily rate-limited. Try again shortly.',
        'تحليل الذكاء الاصطناعي مشغول مؤقتًا. حاول مرة أخرى بعد قليل.',
      );
    }
    if (raw.toLowerCase().contains('unsupported')) {
      return _l(
        'This image format is not supported. Use a JPEG, PNG or WEBP image.',
        'صيغة الصورة غير مدعومة. استخدم JPEG أو PNG أو WEBP.',
      );
    }
    return _l(
      'The analysis could not be completed. Check the connection and try again.',
      'تعذر إكمال التحليل. تأكد من الاتصال وحاول مرة أخرى.',
    );
  }

  String _l(String en, String ar) =>
      Localizations.localeOf(context).languageCode == 'ar' ? ar : en;

  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = V2Text.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            const Icon(Icons.document_scanner, color: VetColors.primary, size: 30),
            const SizedBox(width: 10),
            Text(t.t('scan'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _l(
            'Select the animal group before analysis. The result is decision support, not a definitive diagnosis.',
            'حدد نوع الحيوان قبل التحليل. النتيجة دعم لاتخاذ القرار وليست تشخيصًا نهائيًا.',
          ),
          style: const TextStyle(color: VetColors.muted, height: 1.4),
        ),
        const SizedBox(height: 16),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'livestock', label: Text(t.t('livestock')), icon: const Icon(Icons.agriculture)),
            ButtonSegment(value: 'poultry', label: Text(t.t('poultry')), icon: const Icon(Icons.egg_alt_outlined)),
            ButtonSegment(value: 'dogs', label: Text(t.t('dogs')), icon: const Icon(Icons.pets)),
          ],
          selected: {animalGroup},
          onSelectionChanged: busy ? null : (value) => setState(() => animalGroup = value.first),
        ),
        const SizedBox(height: 16),
        Container(
          height: 280,
          decoration: BoxDecoration(
            color: VetColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0x4439E6B1)),
          ),
          child: bytes == null
              ? const Center(child: Icon(Icons.add_a_photo_outlined, size: 72, color: VetColors.muted))
              : ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.memory(bytes!, fit: BoxFit.cover, width: double.infinity),
                ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : () => pick(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined),
                label: Text(t.t('camera')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : () => pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(t.t('gallery')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: notes,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: t.t('symptoms'),
            hintText: _l(
              'Examples: fever, diarrhoea, reduced feed, lameness, sudden deaths…',
              'مثال: حرارة، إسهال، قلة أكل، عرج، نفوق مفاجئ…',
            ),
          ),
        ),
        const SizedBox(height: 14),
        ElevatedButton.icon(
          onPressed: file == null || busy ? null : analyze,
          icon: busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.health_and_safety_outlined),
          label: Text(
            busy
                ? _l('Analyzing image and clinical context…', 'جاري تحليل الصورة والسياق الصحي…')
                : _l('Analyze case', 'تحليل الحالة'),
          ),
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: 16),
          _MessageCard(text: errorMessage!, isError: true),
        ],
        if (analysis != null) ...[
          const SizedBox(height: 18),
          V3AnalysisCard(result: analysis!),
        ],
      ],
    );
  }
}

class V3AnalysisCard extends StatelessWidget {
  const V3AnalysisCard({super.key, required this.result});

  final Map<String, dynamic> result;

  String _local(BuildContext context, String en, String ar) =>
      Localizations.localeOf(context).languageCode == 'ar' ? ar : en;

  @override
  Widget build(BuildContext context) {
    final risk = result['risk']?.toString() ?? 'insufficient_data';
    final observed = _stringList(result['observed_signs']);
    final actions = _stringList(result['immediate_actions']);
    final questions = _stringList(result['follow_up_questions']);
    final differentials = result['differential_diagnoses'] is List
        ? List<Map<String, dynamic>>.from(
            (result['differential_diagnoses'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
          )
        : <Map<String, dynamic>>[];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _RiskBadge(risk: risk),
                const Spacer(),
                Text(
                  (result['species_observed'] ?? '').toString(),
                  style: const TextStyle(color: VetColors.muted),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              (result['summary'] ?? result['message'] ?? '').toString(),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, height: 1.45),
            ),
            const SizedBox(height: 12),
            _FlagRow(
              urgent: result['urgent_vet_review'] == true,
              isolation: result['isolation_recommended'] == true,
              lab: result['lab_confirmation_required'] == true,
            ),
            if (observed.isNotEmpty) ...[
              const SizedBox(height: 18),
              _SectionTitle(_local(context, 'Observed signs', 'العلامات الملحوظة')),
              ...observed.map((e) => _Bullet(e)),
            ],
            if (differentials.isNotEmpty) ...[
              const SizedBox(height: 18),
              _SectionTitle(_local(context, 'Differential possibilities', 'الاحتمالات التفريقية')),
              ...differentials.map(
                (d) => Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: VetColors.surface2,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${d['name'] ?? d['catalog_slug']} • ${d['suspicion'] ?? ''}',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 5),
                      Text('${d['reasoning'] ?? ''}', style: const TextStyle(color: VetColors.muted, height: 1.4)),
                      const SizedBox(height: 5),
                      Text('${d['source_org'] ?? ''}', style: const TextStyle(fontSize: 12, color: VetColors.primary)),
                    ],
                  ),
                ),
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 18),
              _SectionTitle(_local(context, 'Immediate safety actions', 'إجراءات السلامة الفورية')),
              ...actions.map((e) => _Bullet(e)),
            ],
            if (questions.isNotEmpty) ...[
              const SizedBox(height: 18),
              _SectionTitle(_local(context, 'Questions to improve the assessment', 'أسئلة لتحسين التقييم')),
              ...questions.map((e) => _Bullet(e)),
            ],
            if ((result['confidence_statement'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                result['confidence_statement'].toString(),
                style: const TextStyle(color: VetColors.muted, fontStyle: FontStyle.italic, height: 1.4),
              ),
            ],
            const SizedBox(height: 16),
            _MessageCard(
              text: _local(
                context,
                'Vet AI provides decision support. A veterinarian and laboratory/official testing are required when indicated.',
                'Vet AI يقدم دعمًا لاتخاذ القرار. يلزم الطبيب البيطري والفحوصات المعملية أو الرسمية عندما تكون مطلوبة.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  static List<String> _stringList(dynamic value) => value is List
      ? value.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList()
      : <String>[];
}

class V3HistoryPanel extends StatelessWidget {
  const V3HistoryPanel({super.key, required this.farmId});

  final String farmId;

  @override
  Widget build(BuildContext context) {
    final t = V2Text.of(context);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: VetBackend.instance.recentAssessments(farmId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data ?? const <Map<String, dynamic>>[];
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                const Icon(Icons.history, color: VetColors.primary, size: 30),
                const SizedBox(width: 10),
                Text(t.t('records'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
              ],
            ),
            const SizedBox(height: 18),
            if (rows.isEmpty)
              _MessageCard(text: t.t('noHistory'))
            else
              ...rows.map((row) {
                final ai = row['ai_analysis'] is Map
                    ? Map<String, dynamic>.from(row['ai_analysis'] as Map)
                    : <String, dynamic>{};
                final risk = (row['risk'] ?? 'insufficient_data').toString();
                final summary = (ai['summary'] ?? row['symptom_notes'] ?? '').toString();
                final date = DateTime.tryParse((row['created_at'] ?? '').toString())?.toLocal();
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _RiskBadge(risk: risk),
                            const Spacer(),
                            Text(
                              date == null ? '' : '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(color: VetColors.muted, fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          summary.isEmpty ? t.t('noHistory') : summary,
                          style: const TextStyle(fontWeight: FontWeight.w800, height: 1.4),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${row['animal_group'] ?? ''} • ${row['status'] ?? ''}',
                          style: const TextStyle(color: VetColors.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

class _RiskBadge extends StatelessWidget {
  const _RiskBadge({required this.risk});

  final String risk;

  @override
  Widget build(BuildContext context) {
    final color = switch (risk) {
      'red' => VetColors.red,
      'orange' => VetColors.orange,
      'yellow' => VetColors.yellow,
      'none' => VetColors.green,
      _ => VetColors.muted,
    };
    final label = risk.replaceAll('_', ' ').toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color),
      ),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12)),
    );
  }
}

class _FlagRow extends StatelessWidget {
  const _FlagRow({required this.urgent, required this.isolation, required this.lab});

  final bool urgent;
  final bool isolation;
  final bool lab;

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _Flag(icon: Icons.local_hospital_outlined, active: urgent, label: ar ? 'طبيب عاجل' : 'Urgent vet'),
        _Flag(icon: Icons.shield_outlined, active: isolation, label: ar ? 'عزل/أمان حيوي' : 'Isolation'),
        _Flag(icon: Icons.biotech_outlined, active: lab, label: ar ? 'تأكيد معملي' : 'Lab confirmation'),
      ],
    );
  }
}

class _Flag extends StatelessWidget {
  const _Flag({required this.icon, required this.active, required this.label});

  final IconData icon;
  final bool active;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active ? const Color(0x2239E6B1) : VetColors.surface2,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: active ? VetColors.primary : VetColors.muted),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: active ? VetColors.text : VetColors.muted, fontSize: 12)),
          ],
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
      );
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 7),
              child: Icon(Icons.circle, size: 6, color: VetColors.primary),
            ),
            const SizedBox(width: 9),
            Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
          ],
        ),
      );
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.text, this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isError ? const Color(0x22FF4D5D) : VetColors.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isError ? VetColors.red : const Color(0x4439E6B1)),
        ),
        child: Text(text, style: const TextStyle(height: 1.4)),
      );
}

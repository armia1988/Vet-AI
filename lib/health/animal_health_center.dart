import 'package:flutter/material.dart';

import '../i18n/vet_locale.dart';
import 'animal_health_service.dart';

String _t(BuildContext context, String en, String ar, String nl) {
  return VetTranslator.instance.text(
    localeCode: Localizations.localeOf(context).languageCode,
    en: en,
    ar: ar,
    nl: nl,
  );
}

String _dateLabel(DateTime value) {
  final local = value.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(local.day)}-${two(local.month)}-${local.year} ${two(local.hour)}:${two(local.minute)}';
}

String _shortDate(DateTime value) {
  final local = value.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(local.day)}-${two(local.month)}-${local.year}';
}

DateTime? _parseDate(dynamic value) =>
    value == null ? null : DateTime.tryParse('$value')?.toLocal();

String _animalLabel(Map<String, dynamic> animal) {
  final name = '${animal['name'] ?? ''}'.trim();
  final tag = '${animal['external_id'] ?? ''}'.trim();
  final species = '${animal['species'] ?? ''}'.trim();
  if (name.isNotEmpty && tag.isNotEmpty) return '$name · $tag';
  if (name.isNotEmpty) return name;
  if (tag.isNotEmpty) return tag;
  if (species.isNotEmpty) return species;
  return 'Animal';
}

class AnimalHealthCenterPage extends StatelessWidget {
  const AnimalHealthCenterPage({super.key, required this.farmId});

  final String farmId;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _t(
              context,
              'Farm Health Center',
              'مركز صحة المزرعة',
              'Gezondheidscentrum',
            ),
          ),
          bottom: TabBar(
            tabs: [
              Tab(
                icon: const Icon(Icons.dashboard_rounded),
                text: _t(context, 'Overview', 'نظرة عامة', 'Overzicht'),
              ),
              Tab(
                icon: const Icon(Icons.pets_rounded),
                text: _t(context, 'Animals', 'الحيوانات', 'Dieren'),
              ),
              Tab(
                icon: const Icon(Icons.medication_rounded),
                text: _t(context, 'Care', 'العلاج', 'Zorg'),
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _OverviewTab(farmId: farmId),
            _AnimalsTab(farmId: farmId),
            _CareTab(farmId: farmId),
          ],
        ),
      ),
    );
  }
}

class _OverviewTab extends StatefulWidget {
  const _OverviewTab({required this.farmId});

  final String farmId;

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  late Future<Map<String, dynamic>> future;

  @override
  void initState() {
    super.initState();
    future = AnimalHealthService.instance.dashboard(widget.farmId);
  }

  Future<void> refresh() async {
    final next = AnimalHealthService.instance.dashboard(widget.farmId);
    setState(() => future = next);
    await next;
  }

  int _count(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ErrorPane(
            message: '${snapshot.error}',
            onRetry: refresh,
          );
        }

        final data = snapshot.data ?? const <String, dynamic>{};
        final cameraConfigured = _count(data, 'camera_configured');
        final cameraOnline = _count(data, 'camera_online');
        final sensorDevices = _count(data, 'sensor_devices');
        final sensorOffline = _count(data, 'sensor_offline');

        final cards = <_MetricData>[
          _MetricData(
            icon: Icons.pets_rounded,
            title: _t(context, 'Active animals', 'الحيوانات النشطة', 'Actieve dieren'),
            value: '${_count(data, 'active_animals')}',
          ),
          _MetricData(
            icon: Icons.warning_amber_rounded,
            title: _t(context, 'Critical alerts', 'التنبيهات الحرجة', 'Kritieke meldingen'),
            value: '${_count(data, 'critical_alerts')}',
            urgent: _count(data, 'critical_alerts') > 0,
          ),
          _MetricData(
            icon: Icons.vaccines_rounded,
            title: _t(context, 'Vaccines due in 7 days', 'تطعيمات خلال 7 أيام', 'Vaccins binnen 7 dagen'),
            value: '${_count(data, 'due_vaccinations')}',
          ),
          _MetricData(
            icon: Icons.event_busy_rounded,
            title: _t(context, 'Overdue vaccines', 'تطعيمات متأخرة', 'Achterstallige vaccins'),
            value: '${_count(data, 'overdue_vaccinations')}',
            urgent: _count(data, 'overdue_vaccinations') > 0,
          ),
          _MetricData(
            icon: Icons.medication_rounded,
            title: _t(context, 'Active medications', 'العلاجات النشطة', 'Actieve medicatie'),
            value: '${_count(data, 'active_medications')}',
          ),
          _MetricData(
            icon: Icons.schedule_rounded,
            title: _t(context, 'Doses due in 24h', 'جرعات خلال 24 ساعة', 'Doses binnen 24u'),
            value: '${_count(data, 'medication_doses_due')}',
          ),
          _MetricData(
            icon: Icons.monitor_heart_rounded,
            title: _t(context, 'Sensors online', 'الحساسات المتصلة', 'Sensoren online'),
            value: '${(sensorDevices - sensorOffline).clamp(0, sensorDevices)}/$sensorDevices',
            urgent: sensorOffline > 0,
          ),
          _MetricData(
            icon: Icons.videocam_rounded,
            title: _t(context, 'Cameras online', 'الكاميرات المتصلة', 'Camera’s online'),
            value: '$cameraOnline/$cameraConfigured',
            urgent: cameraConfigured > 0 && cameraOnline < cameraConfigured,
          ),
          _MetricData(
            icon: Icons.health_and_safety_rounded,
            title: _t(context, 'Vet follow-ups', 'متابعات الطبيب', 'Dierenarts follow-ups'),
            value: '${_count(data, 'urgent_followups')}',
            urgent: _count(data, 'urgent_followups') > 0,
          ),
          _MetricData(
            icon: Icons.auto_awesome_rounded,
            title: _t(context, 'AI cases · 24h', 'حالات AI · 24 ساعة', 'AI-cases · 24u'),
            value: '${_count(data, 'recent_ai_cases')}',
          ),
        ];

        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
            children: [
              Text(
                _t(
                  context,
                  'Live farm health summary',
                  'ملخص صحة المزرعة المباشر',
                  'Live gezondheidsoverzicht',
                ),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                _t(
                  context,
                  'Real data from animals, Vet AI cases, sensors, cameras, vaccinations and medication plans.',
                  'بيانات حقيقية من الحيوانات وحالات Vet AI والحساسات والكاميرات والتطعيمات وخطط العلاج.',
                  'Echte data van dieren, Vet AI-cases, sensoren, camera’s, vaccinaties en medicatieplannen.',
                ),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 700;
                  final width = wide
                      ? (constraints.maxWidth - 24) / 3
                      : (constraints.maxWidth - 12) / 2;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: cards
                        .map((item) => SizedBox(
                              width: width,
                              child: _MetricCard(data: item),
                            ))
                        .toList(),
                  );
                },
              ),
              if (_count(data, 'camera_gateways_stale') > 0) ...[
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.router_rounded,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: Text(
                      _t(
                        context,
                        'Camera gateway needs attention',
                        'بوابة الكاميرات تحتاج مراجعة',
                        'Cameragateway vereist aandacht',
                      ),
                    ),
                    subtitle: Text(
                      _t(
                        context,
                        'One or more gateways have not sent a recent heartbeat.',
                        'بوابة واحدة أو أكثر لم ترسل heartbeat حديثًا.',
                        'Een of meer gateways hebben geen recente heartbeat gestuurd.',
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _MetricData {
  const _MetricData({
    required this.icon,
    required this.title,
    required this.value,
    this.urgent = false,
  });

  final IconData icon;
  final String title;
  final String value;
  final bool urgent;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.data});

  final _MetricData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = data.urgent ? scheme.error : scheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(data.icon, color: accent, size: 28),
            const SizedBox(height: 12),
            Text(
              data.value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: accent,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              data.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimalsTab extends StatefulWidget {
  const _AnimalsTab({required this.farmId});

  final String farmId;

  @override
  State<_AnimalsTab> createState() => _AnimalsTabState();
}

class _AnimalsTabState extends State<_AnimalsTab> {
  bool loading = true;
  Object? error;
  List<Map<String, dynamic>> rows = const [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (mounted) setState(() {
      loading = true;
      error = null;
    });
    try {
      final next = await AnimalHealthService.instance.animals(widget.farmId);
      if (mounted) setState(() => rows = next);
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> addAnimal() async {
    final name = TextEditingController();
    final tag = TextEditingController();
    final species = TextEditingController();
    final breed = TextEditingController();
    final sex = TextEditingController();
    final weight = TextEditingController();
    var group = 'livestock';

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(_t(context, 'Add animal', 'إضافة حيوان', 'Dier toevoegen')),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: group,
                    decoration: InputDecoration(
                      labelText: _t(context, 'Group', 'المجموعة', 'Groep'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'livestock',
                        child: Text(_t(context, 'Livestock', 'مواشي', 'Vee')),
                      ),
                      DropdownMenuItem(
                        value: 'poultry',
                        child: Text(_t(context, 'Poultry', 'طيور', 'Pluimvee')),
                      ),
                      DropdownMenuItem(
                        value: 'dogs',
                        child: Text(_t(context, 'Dogs', 'كلاب', 'Honden')),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => group = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: tag,
                    decoration: InputDecoration(
                      labelText: _t(context, 'Tag / ID', 'رقم أو Tag', 'Tag / ID'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: name,
                    decoration: InputDecoration(
                      labelText: _t(context, 'Name', 'الاسم', 'Naam'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: species,
                    decoration: InputDecoration(
                      labelText: _t(context, 'Species', 'النوع', 'Soort'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: breed,
                    decoration: InputDecoration(
                      labelText: _t(context, 'Breed', 'السلالة', 'Ras'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: sex,
                    decoration: InputDecoration(
                      labelText: _t(context, 'Sex', 'الجنس', 'Geslacht'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: weight,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: _t(context, 'Weight (kg)', 'الوزن (كجم)', 'Gewicht (kg)'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_t(context, 'Cancel', 'إلغاء', 'Annuleren')),
            ),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty && tag.text.trim().isEmpty) {
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _t(
                          this.context,
                          'Enter a name or animal ID.',
                          'اكتب اسم الحيوان أو رقمه.',
                          'Vul een naam of dier-ID in.',
                        ),
                      ),
                    ),
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: Text(_t(context, 'Save', 'حفظ', 'Opslaan')),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      try {
        await AnimalHealthService.instance.createAnimal(
          farmId: widget.farmId,
          animalGroup: group,
          externalId: tag.text,
          name: name.text,
          species: species.text,
          breed: breed.text,
          sex: sex.text,
          weightKg: double.tryParse(weight.text.replaceAll(',', '.')),
        );
        await load();
      } catch (e) {
        if (mounted) _showError(context, e);
      }
    }

    name.dispose();
    tag.dispose();
    species.dispose();
    breed.dispose();
    sex.dispose();
    weight.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return _ErrorPane(message: '$error', onRetry: load);
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: load,
        child: rows.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 80),
                  Icon(
                    Icons.pets_rounded,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _t(
                      context,
                      'No individual animals yet',
                      'لا توجد حيوانات مسجلة حتى الآن',
                      'Nog geen individuele dieren',
                    ),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _t(
                      context,
                      'Add an animal to start its complete health timeline.',
                      'أضف حيوانًا لبدء ملفه الصحي الكامل.',
                      'Voeg een dier toe om de volledige gezondheidstijdlijn te starten.',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 90),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final animal = rows[index];
                  final weight = animal['weight_kg'];
                  final details = <String>[
                    if ('${animal['species'] ?? ''}'.trim().isNotEmpty)
                      '${animal['species']}',
                    if ('${animal['breed'] ?? ''}'.trim().isNotEmpty)
                      '${animal['breed']}',
                    if (weight != null) '$weight kg',
                  ];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: const Icon(Icons.pets_rounded),
                      ),
                      title: Text(
                        _animalLabel(animal),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: details.isEmpty ? null : Text(details.join(' · ')),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AnimalTimelinePage(
                            farmId: widget.farmId,
                            animal: animal,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: addAnimal,
        icon: const Icon(Icons.add_rounded),
        label: Text(_t(context, 'Add animal', 'إضافة حيوان', 'Dier toevoegen')),
      ),
    );
  }
}

class AnimalTimelinePage extends StatefulWidget {
  const AnimalTimelinePage({
    super.key,
    required this.farmId,
    required this.animal,
  });

  final String farmId;
  final Map<String, dynamic> animal;

  @override
  State<AnimalTimelinePage> createState() => _AnimalTimelinePageState();
}

class _AnimalTimelinePageState extends State<AnimalTimelinePage> {
  bool loading = true;
  Object? error;
  List<AnimalTimelineItem> items = const [];

  String get animalId => '${widget.animal['id']}';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (mounted) setState(() {
      loading = true;
      error = null;
    });
    try {
      final next = await AnimalHealthService.instance.timeline(
        farmId: widget.farmId,
        animalId: animalId,
      );
      if (mounted) setState(() => items = next);
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  IconData iconFor(String kind) {
    switch (kind) {
      case 'weight':
        return Icons.monitor_weight_rounded;
      case 'temperature':
        return Icons.thermostat_rounded;
      case 'diagnosis':
        return Icons.health_and_safety_rounded;
      case 'lab':
        return Icons.science_rounded;
      case 'treatment':
      case 'medication':
        return Icons.medication_rounded;
      case 'vaccination':
        return Icons.vaccines_rounded;
      case 'alert':
        return Icons.warning_amber_rounded;
      case 'procedure':
        return Icons.medical_services_rounded;
      default:
        return Icons.notes_rounded;
    }
  }

  Future<void> addEvent() async {
    final title = TextEditingController();
    final details = TextEditingController();
    final value = TextEditingController();
    final unit = TextEditingController();
    var type = 'note';

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(_t(context, 'Add health event', 'إضافة حدث صحي', 'Gezondheidsgebeurtenis toevoegen')),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: type,
                    decoration: InputDecoration(labelText: _t(context, 'Type', 'النوع', 'Type')),
                    items: const [
                      DropdownMenuItem(value: 'note', child: Text('Note')),
                      DropdownMenuItem(value: 'weight', child: Text('Weight')),
                      DropdownMenuItem(value: 'temperature', child: Text('Temperature')),
                      DropdownMenuItem(value: 'diagnosis', child: Text('Diagnosis')),
                      DropdownMenuItem(value: 'lab', child: Text('Lab')),
                      DropdownMenuItem(value: 'treatment', child: Text('Treatment')),
                      DropdownMenuItem(value: 'procedure', child: Text('Procedure')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (next) {
                      if (next != null) setDialogState(() => type = next);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: title,
                    decoration: InputDecoration(labelText: _t(context, 'Title', 'العنوان', 'Titel')),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: details,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(labelText: _t(context, 'Details', 'التفاصيل', 'Details')),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: value,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(labelText: _t(context, 'Value', 'القيمة', 'Waarde')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: unit,
                          decoration: InputDecoration(labelText: _t(context, 'Unit', 'الوحدة', 'Eenheid')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_t(context, 'Cancel', 'إلغاء', 'Annuleren')),
            ),
            FilledButton(
              onPressed: title.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: Text(_t(context, 'Save', 'حفظ', 'Opslaan')),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      try {
        await AnimalHealthService.instance.addHealthEvent(
          farmId: widget.farmId,
          animalId: animalId,
          eventType: type,
          title: title.text,
          details: details.text,
          value: num.tryParse(value.text.replaceAll(',', '.')),
          unit: unit.text,
        );
        await load();
      } catch (e) {
        if (mounted) _showError(context, e);
      }
    }

    title.dispose();
    details.dispose();
    value.dispose();
    unit.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animal = widget.animal;
    return Scaffold(
      appBar: AppBar(
        title: Text(_animalLabel(animal)),
        actions: [
          IconButton(
            onPressed: load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: _t(context, 'Refresh', 'تحديث', 'Vernieuwen'),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? _ErrorPane(message: '$error', onRetry: load)
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Wrap(
                            spacing: 20,
                            runSpacing: 10,
                            children: [
                              _AnimalFact(
                                label: _t(context, 'ID', 'الرقم', 'ID'),
                                value: '${animal['external_id'] ?? '—'}',
                              ),
                              _AnimalFact(
                                label: _t(context, 'Species', 'النوع', 'Soort'),
                                value: '${animal['species'] ?? '—'}',
                              ),
                              _AnimalFact(
                                label: _t(context, 'Breed', 'السلالة', 'Ras'),
                                value: '${animal['breed'] ?? '—'}',
                              ),
                              _AnimalFact(
                                label: _t(context, 'Weight', 'الوزن', 'Gewicht'),
                                value: animal['weight_kg'] == null ? '—' : '${animal['weight_kg']} kg',
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _t(context, 'Health timeline', 'الخط الزمني الصحي', 'Gezondheidstijdlijn'),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      if (items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Text(
                            _t(
                              context,
                              'No health events yet. Add the first note, weight, temperature or treatment.',
                              'لا توجد أحداث صحية بعد. أضف أول ملاحظة أو وزن أو حرارة أو علاج.',
                              'Nog geen gezondheidsgebeurtenissen. Voeg een notitie, gewicht, temperatuur of behandeling toe.',
                            ),
                            textAlign: TextAlign.center,
                          ),
                        )
                      else
                        ...items.map((item) => _TimelineCard(
                              item: item,
                              icon: iconFor(item.kind),
                            )),
                    ],
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: addEvent,
        icon: const Icon(Icons.add_rounded),
        label: Text(_t(context, 'Health event', 'حدث صحي', 'Gezondheidsitem')),
      ),
    );
  }
}

class _AnimalFact extends StatelessWidget {
  const _AnimalFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 135,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 3),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      );
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.item, required this.icon});

  final AnimalTimelineItem item;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final risky = item.risk == 'red' || item.risk == 'orange';
    final accent = risky ? scheme.error : scheme.primary;
    final measurement = item.value == null
        ? null
        : '${item.value}${item.unit == null || item.unit!.isEmpty ? '' : ' ${item.unit}'}';
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: accent.withValues(alpha: .12),
          child: Icon(icon, color: accent),
        ),
        title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(_dateLabel(item.occurredAt)),
            if (item.details != null && item.details!.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(item.details!),
            ],
          ],
        ),
        trailing: measurement == null
            ? null
            : Text(
                measurement,
                style: TextStyle(fontWeight: FontWeight.w900, color: accent),
              ),
      ),
    );
  }
}

class _CareTab extends StatefulWidget {
  const _CareTab({required this.farmId});

  final String farmId;

  @override
  State<_CareTab> createState() => _CareTabState();
}

class _CareTabState extends State<_CareTab> {
  bool loading = true;
  Object? error;
  List<Map<String, dynamic>> animals = const [];
  List<Map<String, dynamic>> vaccines = const [];
  List<Map<String, dynamic>> medications = const [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (mounted) setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await Future.wait([
        AnimalHealthService.instance.animals(widget.farmId),
        AnimalHealthService.instance.vaccinations(widget.farmId),
        AnimalHealthService.instance.medications(widget.farmId),
      ]);
      if (mounted) {
        setState(() {
          animals = result[0];
          vaccines = result[1];
          medications = result[2];
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Map<String, String> get labels => {
        for (final animal in animals) '${animal['id']}': _animalLabel(animal),
      };

  Future<void> addVaccine() async {
    if (animals.isEmpty) {
      _showMessage(
        context,
        _t(context, 'Add an animal first.', 'أضف حيوانًا أولًا.', 'Voeg eerst een dier toe.'),
      );
      return;
    }
    final name = TextEditingController();
    final dose = TextEditingController();
    final batch = TextEditingController();
    final notes = TextEditingController();
    var animalId = '${animals.first['id']}';
    var due = DateTime.now().add(const Duration(days: 7));

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(_t(context, 'Schedule vaccination', 'جدولة تطعيم', 'Vaccinatie plannen')),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: animalId,
                    decoration: InputDecoration(labelText: _t(context, 'Animal', 'الحيوان', 'Dier')),
                    items: animals
                        .map((animal) => DropdownMenuItem<String>(
                              value: '${animal['id']}',
                              child: Text(_animalLabel(animal)),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setDialogState(() => animalId = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: name,
                    decoration: InputDecoration(labelText: _t(context, 'Vaccine name', 'اسم التطعيم', 'Vaccinnaam')),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: dose,
                    decoration: InputDecoration(labelText: _t(context, 'Dose', 'الجرعة', 'Dosis')),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: batch,
                    decoration: InputDecoration(labelText: _t(context, 'Batch number', 'رقم التشغيلة', 'Batchnummer')),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_rounded),
                    title: Text(_t(context, 'Due date', 'تاريخ الاستحقاق', 'Vervaldatum')),
                    subtitle: Text(_shortDate(due)),
                    trailing: const Icon(Icons.edit_calendar_rounded),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: due,
                        firstDate: DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now().add(const Duration(days: 3650)),
                      );
                      if (picked != null) {
                        setDialogState(() => due = DateTime(picked.year, picked.month, picked.day, 9));
                      }
                    },
                  ),
                  TextField(
                    controller: notes,
                    minLines: 2,
                    maxLines: 3,
                    decoration: InputDecoration(labelText: _t(context, 'Notes', 'ملاحظات', 'Notities')),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_t(context, 'Cancel', 'إلغاء', 'Annuleren')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, name.text.trim().isNotEmpty),
              child: Text(_t(context, 'Save', 'حفظ', 'Opslaan')),
            ),
          ],
        ),
      ),
    );

    if (saved == true && name.text.trim().isNotEmpty) {
      try {
        await AnimalHealthService.instance.addVaccination(
          farmId: widget.farmId,
          animalId: animalId,
          vaccineName: name.text,
          dueAt: due,
          dose: dose.text,
          batchNumber: batch.text,
          notes: notes.text,
        );
        await load();
      } catch (e) {
        if (mounted) _showError(context, e);
      }
    }

    name.dispose();
    dose.dispose();
    batch.dispose();
    notes.dispose();
  }

  Future<void> addMedication() async {
    if (animals.isEmpty) {
      _showMessage(
        context,
        _t(context, 'Add an animal first.', 'أضف حيوانًا أولًا.', 'Voeg eerst een dier toe.'),
      );
      return;
    }
    final name = TextEditingController();
    final dose = TextEditingController();
    final route = TextEditingController();
    final frequency = TextEditingController();
    final notes = TextEditingController();
    var animalId = '${animals.first['id']}';
    var start = DateTime.now();
    DateTime? nextDose;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(_t(context, 'Add medication', 'إضافة دواء', 'Medicatie toevoegen')),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: animalId,
                    decoration: InputDecoration(labelText: _t(context, 'Animal', 'الحيوان', 'Dier')),
                    items: animals
                        .map((animal) => DropdownMenuItem<String>(
                              value: '${animal['id']}',
                              child: Text(_animalLabel(animal)),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setDialogState(() => animalId = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: name,
                    decoration: InputDecoration(labelText: _t(context, 'Medication', 'اسم الدواء', 'Medicatie')),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: dose,
                          decoration: InputDecoration(labelText: _t(context, 'Dose', 'الجرعة', 'Dosis')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: route,
                          decoration: InputDecoration(labelText: _t(context, 'Route', 'طريقة الإعطاء', 'Toediening')),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: frequency,
                    decoration: InputDecoration(
                      labelText: _t(context, 'Frequency', 'التكرار', 'Frequentie'),
                      hintText: _t(context, 'e.g. every 12 hours', 'مثال: كل 12 ساعة', 'bijv. elke 12 uur'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.play_circle_outline_rounded),
                    title: Text(_t(context, 'Start', 'البداية', 'Start')),
                    subtitle: Text(_dateLabel(start)),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.alarm_rounded),
                    title: Text(_t(context, 'Next dose', 'الجرعة القادمة', 'Volgende dosis')),
                    subtitle: Text(nextDose == null ? '—' : _dateLabel(nextDose!)),
                    trailing: const Icon(Icons.edit_calendar_rounded),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: nextDose ?? DateTime.now(),
                        firstDate: DateTime.now().subtract(const Duration(days: 1)),
                        lastDate: DateTime.now().add(const Duration(days: 3650)),
                      );
                      if (picked != null) {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(nextDose ?? DateTime.now()),
                        );
                        if (time != null) {
                          setDialogState(() {
                            nextDose = DateTime(picked.year, picked.month, picked.day, time.hour, time.minute);
                          });
                        }
                      }
                    },
                  ),
                  TextField(
                    controller: notes,
                    minLines: 2,
                    maxLines: 3,
                    decoration: InputDecoration(labelText: _t(context, 'Notes', 'ملاحظات', 'Notities')),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_t(context, 'Cancel', 'إلغاء', 'Annuleren')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, name.text.trim().isNotEmpty),
              child: Text(_t(context, 'Save', 'حفظ', 'Opslaan')),
            ),
          ],
        ),
      ),
    );

    if (saved == true && name.text.trim().isNotEmpty) {
      try {
        await AnimalHealthService.instance.addMedication(
          farmId: widget.farmId,
          animalId: animalId,
          medicationName: name.text,
          dose: dose.text,
          route: route.text,
          frequency: frequency.text,
          startsAt: start,
          nextDoseAt: nextDose,
          notes: notes.text,
        );
        await load();
      } catch (e) {
        if (mounted) _showError(context, e);
      }
    }

    name.dispose();
    dose.dispose();
    route.dispose();
    frequency.dispose();
    notes.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) return _ErrorPane(message: '$error', onRetry: load);

    final animalLabels = labels;
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: addVaccine,
                icon: const Icon(Icons.vaccines_rounded),
                label: Text(_t(context, 'Schedule vaccine', 'جدولة تطعيم', 'Vaccin plannen')),
              ),
              OutlinedButton.icon(
                onPressed: addMedication,
                icon: const Icon(Icons.medication_rounded),
                label: Text(_t(context, 'Add medication', 'إضافة دواء', 'Medicatie toevoegen')),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            _t(context, 'Vaccinations', 'التطعيمات', 'Vaccinaties'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          if (vaccines.isEmpty)
            _EmptyCard(
              text: _t(context, 'No vaccination schedule yet.', 'لا يوجد جدول تطعيمات بعد.', 'Nog geen vaccinatieschema.'),
            )
          else
            ...vaccines.map((row) {
              final due = _parseDate(row['due_at']);
              final administered = row['status'] == 'administered';
              final overdue = !administered && due != null && due.isBefore(DateTime.now());
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(administered ? Icons.check_rounded : Icons.vaccines_rounded),
                  ),
                  title: Text('${row['vaccine_name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text([
                    animalLabels['${row['animal_id']}'] ?? _t(context, 'Animal', 'حيوان', 'Dier'),
                    if (due != null) '${_t(context, 'Due', 'الموعد', 'Vervalt')}: ${_shortDate(due)}',
                    '${_t(context, 'Status', 'الحالة', 'Status')}: ${row['status'] ?? 'planned'}',
                  ].join('\n')),
                  isThreeLine: true,
                  trailing: administered
                      ? const Icon(Icons.verified_rounded)
                      : FilledButton(
                          style: overdue
                              ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error)
                              : null,
                          onPressed: () async {
                            try {
                              await AnimalHealthService.instance.markVaccinationAdministered(row);
                              await load();
                            } catch (e) {
                              if (mounted) _showError(context, e);
                            }
                          },
                          child: Text(_t(context, 'Done', 'تم', 'Gedaan')),
                        ),
                ),
              );
            }),
          const SizedBox(height: 22),
          Text(
            _t(context, 'Medication plans', 'خطط العلاج', 'Medicatieplannen'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          if (medications.isEmpty)
            _EmptyCard(
              text: _t(context, 'No medication plans yet.', 'لا توجد خطط علاج بعد.', 'Nog geen medicatieplannen.'),
            )
          else
            ...medications.map((row) {
              final active = row['status'] == 'active' || row['status'] == 'planned' || row['status'] == 'paused';
              final next = _parseDate(row['next_dose_at']);
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.medication_rounded)),
                  title: Text('${row['medication_name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text([
                    animalLabels['${row['animal_id']}'] ?? _t(context, 'Animal', 'حيوان', 'Dier'),
                    if (row['dose'] != null) '${_t(context, 'Dose', 'الجرعة', 'Dosis')}: ${row['dose']}',
                    if (row['frequency'] != null) '${row['frequency']}',
                    if (next != null) '${_t(context, 'Next', 'القادم', 'Volgende')}: ${_dateLabel(next)}',
                    '${_t(context, 'Status', 'الحالة', 'Status')}: ${row['status'] ?? 'active'}',
                  ].join('\n')),
                  isThreeLine: true,
                  trailing: active
                      ? IconButton.filledTonal(
                          tooltip: _t(context, 'Complete treatment', 'إنهاء العلاج', 'Behandeling afronden'),
                          onPressed: () async {
                            try {
                              await AnimalHealthService.instance.completeMedication(row);
                              await load();
                            } catch (e) {
                              if (mounted) _showError(context, e);
                            }
                          },
                          icon: const Icon(Icons.check_rounded),
                        )
                      : const Icon(Icons.check_circle_outline_rounded),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Center(child: Text(text, textAlign: TextAlign.center)),
        ),
      );
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 52, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text(
                _t(context, 'Could not load health data.', 'تعذر تحميل البيانات الصحية.', 'Gezondheidsgegevens konden niet worden geladen.'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(_t(context, 'Retry', 'إعادة المحاولة', 'Opnieuw proberen')),
              ),
            ],
          ),
        ),
      );
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

void _showError(BuildContext context, Object error) {
  final raw = error.toString();
  final clean = raw.length > 260 ? '${raw.substring(0, 260)}…' : raw;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(clean),
      backgroundColor: Theme.of(context).colorScheme.error,
    ),
  );
}
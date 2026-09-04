from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, found {count}")
    return text.replace(old, new, 1)


def replace_between(text: str, start: str, end: str, replacement: str, label: str) -> str:
    i = text.find(start)
    if i < 0:
        raise SystemExit(f"{label}: start marker not found")
    j = text.find(end, i)
    if j < 0:
        raise SystemExit(f"{label}: end marker not found")
    return text[:i] + replacement + text[j:]


# ---------------------------------------------------------------------------
# Main app: AI retry behavior, sensors/alerts reliability, icon scale, branding.
# ---------------------------------------------------------------------------
app_path = Path('lib/v5_app.dart')
app = app_path.read_text()

old_retry = """      Map<String, dynamic> response = <String, dynamic>{};
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
new_retry = """      final response = await VetBackend.instance.analyzeAssessment(
        newAssessmentId,
        language: Localizations.localeOf(context).languageCode,
      );
      // Do not automatically hammer the AI provider after a 429/timeout.
      // One explicit user action now produces one provider request.
      if (mounted) setState(() => result = response);"""
app = replace_once(app, old_retry, new_retry, 'AI rapid retry removal')

app = replace_once(
    app,
    "return tr(context, 'The AI provider is temporarily rate-limited. Retry later.', 'مزود الذكاء الاصطناعي وصل للحد المؤقت. حاول لاحقًا.', 'De AI-provider heeft tijdelijk een snelheidslimiet. Probeer later opnieuw.');",
    "return tr(context, 'The AI provider temporarily rejected this request because the API account reached a provider limit. This is not evidence of Vet AI user traffic. Try again in about a minute.', 'مزود الذكاء الاصطناعي رفض الطلب مؤقتًا لأن حساب الـ API وصل لحد من المزود. ده مش معناه إن فيه ضغط مستخدمين على Vet AI. جرّب تاني بعد حوالي دقيقة.', 'De AI-provider heeft dit verzoek tijdelijk geweigerd omdat het API-account een providerlimiet heeft bereikt. Dit betekent niet dat Vet AI veel gebruikersverkeer heeft. Probeer het over ongeveer een minuut opnieuw.');",
    'rate limit copy',
)

# Make animal group chip images visibly larger despite transparent PNG padding.
app = replace_once(
    app,
    "ChoiceChip(avatar: Image.asset(asset(g), width: 44, height: 44, fit: BoxFit.contain, filterQuality: FilterQuality.high),",
    "ChoiceChip(avatar: Transform.scale(scale: 1.45, child: Image.asset(asset(g), width: 52, height: 52, fit: BoxFit.contain, filterQuality: FilterQuality.high)),",
    'scan group chip scale',
)

sensors_class = r'''class V5SensorsPanel extends StatefulWidget {
  const V5SensorsPanel({super.key, required this.farm, required this.unlocked});
  final Map<String, dynamic> farm;
  final bool unlocked;

  @override
  State<V5SensorsPanel> createState() => _V5SensorsPanelState();
}

class _V5SensorsPanelState extends State<V5SensorsPanel> {
  late Future<List<Map<String, dynamic>>> devicesFuture;

  String get farmId => widget.farm['id'] as String;

  @override
  void initState() {
    super.initState();
    devicesFuture = widget.unlocked ? _loadDevices() : Future.value(const <Map<String, dynamic>>[]);
  }

  @override
  void didUpdateWidget(covariant V5SensorsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unlocked != widget.unlocked || oldWidget.farm['id'] != widget.farm['id']) {
      devicesFuture = widget.unlocked ? _loadDevices() : Future.value(const <Map<String, dynamic>>[]);
    }
  }

  Future<List<Map<String, dynamic>>> _loadDevices() {
    return VetBackend.instance.sensorDevices(farmId).timeout(const Duration(seconds: 12));
  }

  void _retry() {
    setState(() => devicesFuture = _loadDevices());
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.unlocked) {
      return ListView(padding: const EdgeInsets.all(20), children: [
        _StepTitle(icon: Icons.lock_rounded, title: tr(context, 'Smart sensors', 'الحساسات الذكية', 'Slimme sensoren'), subtitle: tr(context, 'Unavailable on the Software only plan.', 'غير متاحة على خطة البرنامج فقط.', 'Niet beschikbaar met het Alleen software-plan.')),
        const SizedBox(height: 18),
        _Notice(icon: Icons.workspace_premium_outlined, title: tr(context, 'Plan locked', 'الميزة مقفلة حسب الخطة', 'Functie vergrendeld'), text: tr(context, 'Choose Software + smart monitoring from Subscription to unlock real hardware data. No fake sensor values are shown.', 'اختر البرنامج + المراقبة الذكية من صفحة الاشتراك لفتح بيانات الأجهزة الحقيقية. لن نعرض أرقام حساسات وهمية.', 'Kies Software + slimme monitoring bij Abonnement om echte hardwaredata te ontgrendelen. Er worden geen nepwaarden getoond.')),
      ]);
    }
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: devicesFuture,
      builder: (context, devices) {
        final rows = devices.data ?? const <Map<String, dynamic>>[];
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _StepTitle(icon: Icons.sensors_rounded, title: tr(context, 'Smart monitoring', 'المراقبة الذكية', 'Slimme monitoring'), subtitle: tr(context, 'Only real connected hardware is shown.', 'يتم عرض الهاردوير الحقيقي المتصل فقط.', 'Alleen echt gekoppelde hardware wordt getoond.')),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SensorAlertRulesScreen(farmId: farmId))),
              icon: const Icon(Icons.notifications_active_outlined, size: 29),
              label: Text(tr(context, 'Configure real sensor alert rules', 'ضبط قواعد إنذارات الحساسات الحقيقية', 'Echte sensorwaarschuwingsregels instellen')),
            ),
            const SizedBox(height: 18),
            if (devices.connectionState != ConnectionState.done)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            if (devices.connectionState == ConnectionState.done && devices.hasError) ...[
              _Notice(
                icon: Icons.cloud_off_rounded,
                title: tr(context, 'Could not load sensors', 'تعذر تحميل الحساسات', 'Sensoren konden niet worden geladen'),
                text: tr(context, 'Vet AI stopped waiting instead of showing an endless loader. Check the connection and try again.', 'Vet AI وقف التحميل بدل ما يفضل يلف للأبد. تحقق من الاتصال وجرّب تاني.', 'Vet AI is gestopt met wachten in plaats van eindeloos te laden. Controleer de verbinding en probeer opnieuw.'),
                danger: true,
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(onPressed: _retry, icon: const Icon(Icons.refresh_rounded), label: Text(tr(context, 'Retry', 'إعادة المحاولة', 'Opnieuw proberen'))),
            ],
            if (devices.connectionState == ConnectionState.done && !devices.hasError && rows.isEmpty)
              _Notice(icon: Icons.sensors_off_outlined, title: tr(context, 'No sensors connected', 'لا توجد حساسات متصلة', 'Geen sensoren gekoppeld'), text: tr(context, 'The plan allows sensors, but no device has been provisioned yet.', 'الخطة تسمح بالحساسات لكن لم يتم ربط أي جهاز حتى الآن.', 'Het plan ondersteunt sensoren, maar er is nog geen apparaat ingericht.')),
            if (!devices.hasError)
              for (final device in rows)
                Card(margin: const EdgeInsets.only(bottom: 10), child: ListTile(leading: const Icon(Icons.sensors_rounded, size: 35, color: VetColors.primary), title: Text(device['device_uid']?.toString() ?? ''), subtitle: Text('${device['device_type'] ?? ''}\n${device['last_seen_at'] ?? tr(context, 'Never seen', 'لم يتصل بعد', 'Nog nooit gezien')}'), isThreeLine: true)),
          ],
        );
      },
    );
  }
}

'''
app = replace_between(app, 'class V5SensorsPanel extends StatelessWidget {', 'class V5AlertsPanel extends StatefulWidget {', sensors_class, 'sensors panel')

alerts_class = r'''class V5AlertsPanel extends StatefulWidget {
  const V5AlertsPanel({super.key, required this.farmId});
  final String farmId;

  @override
  State<V5AlertsPanel> createState() => _V5AlertsPanelState();
}

class _V5AlertsPanelState extends State<V5AlertsPanel> {
  final seen = <String>{};
  bool initialized = false;
  late Stream<List<Map<String, dynamic>>> alerts;

  @override
  void initState() {
    super.initState();
    alerts = VetBackend.instance.alertsStream(widget.farmId);
  }

  @override
  void didUpdateWidget(covariant V5AlertsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.farmId != widget.farmId) {
      initialized = false;
      seen.clear();
      alerts = VetBackend.instance.alertsStream(widget.farmId);
    }
  }

  void _retry() {
    setState(() {
      initialized = false;
      alerts = VetBackend.instance.alertsStream(widget.farmId);
    });
  }

  void _onRows(List<Map<String, dynamic>> rows) {
    final ids = rows.map((e) => e['id']?.toString()).whereType<String>().toSet();
    if (!initialized) {
      seen.addAll(ids);
      initialized = true;
      return;
    }
    final fresh = ids.difference(seen);
    if (fresh.isNotEmpty) {
      seen.addAll(fresh);
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
    }
  }

  String _metric(String value) => switch (value) {
        'body_temperature_c' => tr(context, 'Body temperature', 'حرارة جسم الحيوان', 'Lichaamstemperatuur'),
        'ambient_temperature_c' => tr(context, 'Barn temperature', 'حرارة العنبر', 'Staltemperatuur'),
        'humidity_percent' => tr(context, 'Humidity', 'الرطوبة', 'Luchtvochtigheid'),
        'activity_index' => tr(context, 'Activity', 'النشاط', 'Activiteit'),
        'steps' => tr(context, 'Steps', 'الخطوات', 'Stappen'),
        'distance_from_herd_m' => tr(context, 'Distance from herd', 'البعد عن القطيع', 'Afstand tot kudde'),
        'lying_minutes' => tr(context, 'Lying / resting', 'الرقاد / الراحة', 'Liggen / rusten'),
        'feeding_minutes' => tr(context, 'Feeding', 'الأكل', 'Voeren'),
        'rumination_minutes' => tr(context, 'Rumination', 'الاجترار', 'Herkauwen'),
        _ => value.replaceAll('_', ' '),
      };

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: alerts,
        builder: (context, snapshot) {
          final rows = snapshot.data ?? const <Map<String, dynamic>>[];
          if (snapshot.hasData) WidgetsBinding.instance.addPostFrameCallback((_) => _onRows(rows));
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _StepTitle(
                icon: Icons.warning_amber_rounded,
                title: tr(context, 'Health & sensor alerts', 'إنذارات الصحة والحساسات', 'Gezondheids- & sensormeldingen'),
                subtitle: tr(context, 'AI risk alerts plus real configured sensor thresholds. New alerts make a sound while Vet AI is active.', 'إنذارات خطورة AI + حدود الحساسات الحقيقية اللي إنت ضابطها. الإنذار الجديد يطلع صوت واهتزاز وVet AI مفتوح.', 'AI-risicomeldingen plus echte ingestelde sensordrempels. Nieuwe meldingen geven geluid/trilling terwijl Vet AI actief is.'),
              ),
              const SizedBox(height: 18),
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData)
                const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
              if (snapshot.hasError) ...[
                _Notice(
                  icon: Icons.cloud_off_rounded,
                  title: tr(context, 'Could not load alerts', 'تعذر تحميل الإنذارات', 'Meldingen konden niet worden geladen'),
                  text: tr(context, 'The live alert connection failed. Vet AI will not leave this page loading forever; retry the connection.', 'فشل اتصال الإنذارات المباشر. Vet AI مش هيسيب الصفحة تحمل للأبد؛ جرّب إعادة الاتصال.', 'De live meldingsverbinding is mislukt. Vet AI blijft niet eindeloos laden; probeer opnieuw te verbinden.'),
                  danger: true,
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(onPressed: _retry, icon: const Icon(Icons.refresh_rounded), label: Text(tr(context, 'Reconnect', 'إعادة الاتصال', 'Opnieuw verbinden'))),
              ],
              if (!snapshot.hasError && snapshot.hasData && rows.isEmpty)
                _Notice(
                  icon: Icons.check_circle_outline_rounded,
                  title: tr(context, 'No active alerts', 'لا توجد إنذارات حالية', 'Geen actieve meldingen'),
                  text: tr(context, 'No AI or configured real-sensor alert is stored for this farm.', 'مفيش إنذار AI أو إنذار حساس حقيقي متضبط محفوظ للمزرعة دي.', 'Er is geen AI- of ingestelde echte-sensormelding voor deze boerderij opgeslagen.'),
                ),
              if (!snapshot.hasError)
                for (final a in rows)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: Icon(
                        a['risk'] == 'red' ? Icons.error_rounded : Icons.warning_rounded,
                        size: 36,
                        color: a['risk'] == 'red' ? VetColors.red : a['risk'] == 'orange' ? VetColors.orange : VetColors.history,
                      ),
                      title: Text(a['title']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w900)),
                      subtitle: a['source'] == 'sensor'
                          ? Text('${_metric(a['metric']?.toString() ?? '')}: ${a['value_numeric'] ?? '—'}\n${tr(context, 'Configured threshold', 'الحد المتضبط', 'Ingestelde drempel')}: ${a['threshold_text'] ?? '—'}')
                          : Text(a['details']?.toString() ?? ''),
                      isThreeLine: a['source'] == 'sensor',
                    ),
                  ),
              const SizedBox(height: 10),
              Text(
                tr(context, 'Background push notifications when the app is fully closed require APNs/push credentials and are a separate deployment step. This screen never fabricates sensor alerts.', 'الإشعارات في الخلفية والتطبيق مقفول تمامًا محتاجة إعداد APNs/Push منفصل. الشاشة دي ما بتختلقش إنذارات حساسات.', 'Achtergrond-pushmeldingen wanneer de app volledig gesloten is vereisen aparte APNs/pushconfiguratie. Dit scherm verzint nooit sensormeldingen.'),
                style: const TextStyle(color: VetColors.muted, fontSize: 11.5, height: 1.4),
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
      );
}

'''
app = replace_between(app, 'class V5AlertsPanel extends StatefulWidget {', 'class V5HistoryPanel extends StatelessWidget {', alerts_class, 'alerts panel')

animal_count = r'''class _AnimalCount extends StatelessWidget {
  const _AnimalCount({required this.asset, required this.label, required this.value});
  final String asset;
  final String label;
  final dynamic value;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                height: 112,
                child: Center(
                  child: Transform.scale(
                    scale: 1.7,
                    child: Image.asset(asset, width: 100, height: 100, fit: BoxFit.contain, filterQuality: FilterQuality.high),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text('$value', style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(label, textAlign: TextAlign.center, style: const TextStyle(color: VetColors.muted, fontSize: 13)),
            ],
          ),
        ),
      );
}

'''
app = replace_between(app, 'class _AnimalCount extends StatelessWidget {', 'class _MenuTile extends StatelessWidget {', animal_count, 'animal count card')

header_brand = r'''class _HeaderBrand extends StatelessWidget {
  const _HeaderBrand();
  @override
  Widget build(BuildContext context) => Row(
        textDirection: TextDirection.ltr,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Transform.translate(
            offset: const Offset(5, 0),
            child: SvgPicture.asset('assets/vet_ai_logo.svg', width: 74, height: 51, colorFilter: const ColorFilter.mode(VetColors.primary, BlendMode.srcIn)),
          ),
          const SizedBox(width: 1),
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Vet ', style: TextStyle(color: VetColors.text)),
              const TextSpan(text: 'AI', style: TextStyle(color: VetColors.primary)),
            ]),
            style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w900, letterSpacing: .1),
          ),
        ],
      );
}

'''
app = replace_between(app, 'class _HeaderBrand extends StatelessWidget {', 'class _BrandLockup extends StatelessWidget {', header_brand, 'header brand')

# Scale the banner/onboarding animal images where the PNGs have generous transparent margins.
app = app.replace(
    "Image.asset(asset, width: 90, height: 90, fit: BoxFit.contain, filterQuality: FilterQuality.high),",
    "Transform.scale(scale: 1.45, child: Image.asset(asset, width: 90, height: 90, fit: BoxFit.contain, filterQuality: FilterQuality.high)),",
)
app = app.replace(
    "Image.asset(asset,width:78,height:78,fit:BoxFit.contain,filterQuality:FilterQuality.high)",
    "Transform.scale(scale:1.35,child:Image.asset(asset,width:78,height:78,fit:BoxFit.contain,filterQuality:FilterQuality.high))",
)

# Slightly larger bottom-navigation symbols for easier recognition.
app = replace_once(
    app,
    "icon: Icon(icon, size: 30, color: color.withValues(alpha: .78)),",
    "icon: Icon(icon, size: 32, color: color.withValues(alpha: .78)),",
    'nav icon size',
)
app = replace_once(
    app,
    "width: 48,\n          height: 40,",
    "width: 52,\n          height: 42,",
    'nav selected box size',
)
app = replace_once(
    app,
    "child: Icon(selected, size: 32, color: color),",
    "child: Icon(selected, size: 34, color: color),",
    'nav selected icon size',
)

app_path.write_text(app)


# ---------------------------------------------------------------------------
# Sensor alert rules: timeout + explicit error state instead of endless spinner.
# ---------------------------------------------------------------------------
rules_path = Path('lib/monitoring/sensor_alert_rules.dart')
rules = rules_path.read_text()
rules = replace_once(
    rules,
    """  @override
  void initState() {
    super.initState();
    future = VetBackend.instance.sensorAlertRules(widget.farmId);
  }

  Future<void> refresh() async {
    setState(() => future = VetBackend.instance.sensorAlertRules(widget.farmId));
    await future;
  }""",
    """  @override
  void initState() {
    super.initState();
    future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() {
    return VetBackend.instance.sensorAlertRules(widget.farmId).timeout(const Duration(seconds: 12));
  }

  Future<void> refresh() async {
    setState(() => future = _load());
    try {
      await future;
    } catch (_) {
      // FutureBuilder presents the recoverable error state.
    }
  }""",
    'sensor rule loader',
)
rules = replace_once(
    rules,
    """          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final rows = snapshot.data!;
            return RefreshIndicator(""",
    """          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_rounded, size: 54, color: VetColors.red),
                      const SizedBox(height: 12),
                      Text(_rt(context, 'Could not load sensor alert rules', 'تعذر تحميل قواعد إنذارات الحساسات', 'Sensorwaarschuwingsregels konden niet worden geladen'), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                      const SizedBox(height: 8),
                      Text(_rt(context, 'Vet AI stopped the request instead of leaving an endless loader. Try again.', 'Vet AI أوقف الطلب بدل ما يفضل التحميل شغال للأبد. جرّب تاني.', 'Vet AI heeft het verzoek gestopt in plaats van eindeloos te laden. Probeer opnieuw.'), textAlign: TextAlign.center, style: const TextStyle(color: VetColors.muted, height: 1.4)),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(onPressed: refresh, icon: const Icon(Icons.refresh_rounded), label: Text(_rt(context, 'Retry', 'إعادة المحاولة', 'Opnieuw proberen'))),
                    ],
                  ),
                ),
              );
            }
            final rows = snapshot.data ?? const <Map<String, dynamic>>[];
            return RefreshIndicator(""",
    'sensor rule error state',
)
rules_path.write_text(rules)


# ---------------------------------------------------------------------------
# Home live vitals: stop waiting after timeout and show a real error state.
# ---------------------------------------------------------------------------
vitals_path = Path('lib/monitoring/smart_home_vitals.dart')
vitals = vitals_path.read_text()
vitals = replace_once(
    vitals,
    """    final results = await Future.wait([
      VetBackend.instance.sensorDevices(widget.farmId),
      VetBackend.instance.latestSensorReadings(widget.farmId),
    ]);""",
    """    final results = await Future.wait([
      VetBackend.instance.sensorDevices(widget.farmId),
      VetBackend.instance.latestSensorReadings(widget.farmId),
    ]).timeout(const Duration(seconds: 12));""",
    'vitals timeout',
)
old_states = """                if (snapshot.connectionState != ConnectionState.done)
                  const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
                if (snapshot.connectionState == ConnectionState.done && data != null && data.devices.isEmpty)
                  _EmptyState(
                    icon: Icons.sensors_off_rounded,
                    title: widget.translate('No monitoring device connected yet', 'لسه مفيش جهاز مراقبة متوصل', 'Nog geen monitoringapparaat gekoppeld'),
                    text: widget.translate('This section will stay empty until a real Vet AI sensor device is provisioned.', 'القسم ده هيفضل فاضي لحد ما يتربط حساس Vet AI حقيقي. مش هنحط أرقام تجريبية.', 'Dit gedeelte blijft leeg totdat een echt Vet AI-sensorapparaat is ingericht.'),
                  ),
                if (snapshot.connectionState == ConnectionState.done && data != null && data.devices.isNotEmpty && data.readings.isEmpty)
                  _EmptyState(
                    icon: Icons.schedule_rounded,
                    title: widget.translate('Sensor connected — waiting for first reading', 'الحساس متوصل — مستنيين أول قراءة', 'Sensor gekoppeld — wachten op eerste meting'),
                    text: widget.translate('No fake values are shown while the device has not reported data.', 'مش هنعرض أي قيم وهمية قبل ما الجهاز يبعت بيانات فعلية.', 'Er worden geen nepwaarden getoond zolang het apparaat nog geen gegevens heeft gestuurd.'),
                  ),
                if (snapshot.connectionState == ConnectionState.done && data != null && data.readings.isNotEmpty)
                  _LiveContent(reading: data.readings.first, translate: widget.translate),"""
new_states = """                if (snapshot.connectionState != ConnectionState.done)
                  const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
                if (snapshot.connectionState == ConnectionState.done && snapshot.hasError)
                  _EmptyState(
                    icon: Icons.cloud_off_rounded,
                    title: widget.translate('Monitoring data could not be loaded', 'تعذر تحميل بيانات المراقبة', 'Monitoringgegevens konden niet worden geladen'),
                    text: widget.translate('Vet AI stopped waiting after the request timeout. Use the refresh button to try again.', 'Vet AI وقف الانتظار بعد مهلة الطلب. استخدم زر التحديث وجرّب تاني.', 'Vet AI is na de aanvraagtime-out gestopt met wachten. Gebruik vernieuwen om opnieuw te proberen.'),
                  ),
                if (snapshot.connectionState == ConnectionState.done && !snapshot.hasError && data != null && data.devices.isEmpty)
                  _EmptyState(
                    icon: Icons.sensors_off_rounded,
                    title: widget.translate('No monitoring device connected yet', 'لسه مفيش جهاز مراقبة متوصل', 'Nog geen monitoringapparaat gekoppeld'),
                    text: widget.translate('This section will stay empty until a real Vet AI sensor device is provisioned.', 'القسم ده هيفضل فاضي لحد ما يتربط حساس Vet AI حقيقي. مش هنحط أرقام تجريبية.', 'Dit gedeelte blijft leeg totdat een echt Vet AI-sensorapparaat is ingericht.'),
                  ),
                if (snapshot.connectionState == ConnectionState.done && !snapshot.hasError && data != null && data.devices.isNotEmpty && data.readings.isEmpty)
                  _EmptyState(
                    icon: Icons.schedule_rounded,
                    title: widget.translate('Sensor connected — waiting for first reading', 'الحساس متوصل — مستنيين أول قراءة', 'Sensor gekoppeld — wachten op eerste meting'),
                    text: widget.translate('No fake values are shown while the device has not reported data.', 'مش هنعرض أي قيم وهمية قبل ما الجهاز يبعت بيانات فعلية.', 'Er worden geen nepwaarden getoond zolang het apparaat nog geen gegevens heeft gestuurd.'),
                  ),
                if (snapshot.connectionState == ConnectionState.done && !snapshot.hasError && data != null && data.readings.isNotEmpty)
                  _LiveContent(reading: data.readings.first, translate: widget.translate),"""
vitals = replace_once(vitals, old_states, new_states, 'vitals states')
vitals_path.write_text(vitals)


# ---------------------------------------------------------------------------
# New TestFlight version/build.
# ---------------------------------------------------------------------------
pubspec_path = Path('pubspec.yaml')
pubspec = pubspec_path.read_text()
if 'version: 0.6.3+13' in pubspec:
    pubspec = pubspec.replace('version: 0.6.3+13', 'version: 0.6.4+14', 1)
elif 'version: 0.6.4+14' not in pubspec:
    raise SystemExit('pubspec version changed unexpectedly; refusing to guess a build number')
pubspec_path.write_text(pubspec)

print('V20 UI/reliability patch applied successfully.')

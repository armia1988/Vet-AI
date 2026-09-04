from pathlib import Path

p = Path('lib/v5_app.dart')
s = p.read_text()

# Imports.
s = s.replace("import 'package:flutter_svg/flutter_svg.dart';\n", "import 'package:flutter_svg/flutter_svg.dart';\nimport 'package:flutter/services.dart';\n")
s = s.replace("import 'package:image_picker/image_picker.dart';\n", "import 'package:image_picker/image_picker.dart';\nimport 'package:shared_preferences/shared_preferences.dart';\n")
s = s.replace("import 'services/vet_backend.dart';\n", "import 'services/vet_backend.dart';\nimport 'services/vet_operations.dart';\n")
s = s.replace("import 'support/support_chat_v6.dart';\n", "import 'support/support_chat_v6.dart';\nimport 'support/support_console.dart';\n")
s = s.replace("import 'monitoring/smart_home_vitals.dart';\n", "import 'monitoring/smart_home_vitals.dart';\nimport 'monitoring/sensor_alert_rules.dart';\nimport 'legal/vet_legal_pages.dart';\n")

# Home header: brand + farm/company together, mirrored by RTL/LTR.
old_home = '''        SizedBox(\n          height: 74,\n          child: Row(\n            crossAxisAlignment: CrossAxisAlignment.center,\n            children: [\n              const _HeaderBrand(),\n              const Spacer(),\n              IconButton.filledTonal(\n                tooltip: tr(context, 'Language', 'اللغة', 'Taal'),\n                style: IconButton.styleFrom(backgroundColor: VetColors.surface3),\n                icon: const Icon(Icons.language_rounded, size: 30, color: VetColors.blue),\n                onPressed: () => showVetLanguagePicker(context),\n              ),\n              const SizedBox(width: 6),\n              IconButton.filledTonal(\n                tooltip: tr(context, 'Account & settings', 'الحساب والإعدادات', 'Account & instellingen'),\n                style: IconButton.styleFrom(backgroundColor: VetColors.surface3),\n                icon: const Icon(Icons.account_circle_outlined, size: 31, color: VetColors.primary),\n                onPressed: onAccount,\n              ),\n            ],\n          ),\n        ),\n        const SizedBox(height: 2),\n        Text(farm['farm_name']?.toString() ?? 'Vet AI', textAlign: TextAlign.center, style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w900)),\n        if ((farm['company_name']?.toString() ?? '').isNotEmpty)\n          Padding(padding: const EdgeInsets.only(top: 4), child: Text(farm['company_name'].toString(), textAlign: TextAlign.center, style: const TextStyle(color: VetColors.muted, fontSize: 16, fontWeight: FontWeight.w600))),\n        const SizedBox(height: 18),'''
new_home = '''        SizedBox(\n          height: 116,\n          child: Row(\n            crossAxisAlignment: CrossAxisAlignment.start,\n            children: [\n              Expanded(\n                child: Column(\n                  crossAxisAlignment: Directionality.of(context) == TextDirection.rtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,\n                  children: [\n                    const _HeaderBrand(),\n                    const SizedBox(height: 3),\n                    Text(\n                      farm['farm_name']?.toString() ?? 'Vet AI',\n                      maxLines: 1,\n                      overflow: TextOverflow.ellipsis,\n                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),\n                    ),\n                    if ((farm['company_name']?.toString() ?? '').isNotEmpty)\n                      Text(\n                        farm['company_name'].toString(),\n                        maxLines: 1,\n                        overflow: TextOverflow.ellipsis,\n                        style: const TextStyle(color: VetColors.muted, fontSize: 14, fontWeight: FontWeight.w700),\n                      ),\n                  ],\n                ),\n              ),\n              const SizedBox(width: 10),\n              Row(\n                mainAxisSize: MainAxisSize.min,\n                children: [\n                  IconButton.filledTonal(\n                    tooltip: tr(context, 'Language', 'اللغة', 'Taal'),\n                    style: IconButton.styleFrom(backgroundColor: VetColors.surface3),\n                    icon: const Icon(Icons.language_rounded, size: 30, color: VetColors.blue),\n                    onPressed: () => showVetLanguagePicker(context),\n                  ),\n                  const SizedBox(width: 6),\n                  IconButton.filledTonal(\n                    tooltip: tr(context, 'Account & settings', 'الحساب والإعدادات', 'Account & instellingen'),\n                    style: IconButton.styleFrom(backgroundColor: VetColors.surface3),\n                    icon: const Icon(Icons.account_circle_outlined, size: 31, color: VetColors.primary),\n                    onPressed: onAccount,\n                  ),\n                ],\n              ),\n            ],\n          ),\n        ),\n        const SizedBox(height: 8),'''
if old_home not in s:
    raise SystemExit('home header target not found')
s = s.replace(old_home, new_home, 1)

# One-time custom camera explanation per signed-in account.
old_media = '''  Future<bool> _confirmMedia(ImageSource source) => _confirmAccess(\n        title: source == ImageSource.camera ? tr(context, 'Open camera?', 'فتح الكاميرا؟', 'Camera openen?') : tr(context, 'Open photos?', 'فتح الصور؟', 'Foto’s openen?'),\n        message: source == ImageSource.camera\n            ? tr(context, 'Vet AI will open the camera only after your approval. The photo is not uploaded until you explicitly start the health analysis.', 'Vet AI هيفتح الكاميرا بعد موافقتك بس. الصورة مش هتترفع إلا لما تضغط بنفسك على تحليل الحالة.', 'Vet AI opent de camera pas na jouw toestemming. De foto wordt pas geüpload wanneer je zelf de gezondheidsanalyse start.')\n            : tr(context, 'Vet AI will let you choose a photo only after your approval. It will not upload the selected image until you explicitly start the health analysis.', 'Vet AI هيسمحلك تختار صورة بعد موافقتك بس، ومش هيرفع الصورة المختارة إلا لما تضغط بنفسك على تحليل الحالة.', 'Vet AI laat je pas na toestemming een foto kiezen. De gekozen foto wordt pas geüpload wanneer je zelf de gezondheidsanalyse start.'),\n        icon: source == ImageSource.camera ? Icons.photo_camera_rounded : Icons.photo_library_rounded,\n      );'''
new_media = '''  Future<bool> _confirmMedia(ImageSource source) async {\n    if (source == ImageSource.camera) {\n      final userId = VetBackend.instance.currentUser?.id;\n      final prefs = await SharedPreferences.getInstance();\n      final key = 'vet_ai_camera_intro_seen_${userId ?? 'signed_out'}';\n      if (prefs.getBool(key) == true) return true;\n      final approved = await _confirmAccess(\n        title: tr(context, 'Open camera?', 'فتح الكاميرا؟', 'Camera openen?'),\n        message: tr(context, 'This one-time Vet AI explanation appears for a new account before camera use. The photo is not uploaded until you explicitly start the health analysis.', 'الشرح ده بيظهر مرة واحدة بس للحساب الجديد قبل استخدام الكاميرا. الصورة مش هتترفع إلا لما تضغط بنفسك على تحليل الحالة.', 'Deze eenmalige Vet AI-uitleg verschijnt voor een nieuw account vóór cameragebruik. De foto wordt pas geüpload wanneer je zelf de gezondheidsanalyse start.'),\n        icon: Icons.photo_camera_rounded,\n      );\n      if (approved) await prefs.setBool(key, true);\n      return approved;\n    }\n    return _confirmAccess(\n      title: tr(context, 'Open photos?', 'فتح الصور؟', 'Foto’s openen?'),\n      message: tr(context, 'Vet AI will let you choose a photo only after your approval. It will not upload the selected image until you explicitly start the health analysis.', 'Vet AI هيسمحلك تختار صورة بعد موافقتك بس، ومش هيرفع الصورة المختارة إلا لما تضغط بنفسك على تحليل الحالة.', 'Vet AI laat je pas na toestemming een foto kiezen. De gekozen foto wordt pas geüpload wanneer je zelf de gezondheidsanalyse start.'),\n      icon: Icons.photo_library_rounded,\n    );\n  }'''
if old_media not in s:
    raise SystemExit('scan confirm media target not found')
s = s.replace(old_media, new_media, 1)

# Sensors: add real threshold manager.
sensor_marker = """            _StepTitle(icon: Icons.sensors_rounded, title: tr(context, 'Smart monitoring', 'المراقبة الذكية', 'Slimme monitoring'), subtitle: tr(context, 'Only real connected hardware is shown.', 'يتم عرض الهاردوير الحقيقي المتصل فقط.', 'Alleen echt gekoppelde hardware wordt getoond.')),\n            const SizedBox(height: 18),"""
sensor_repl = """            _StepTitle(icon: Icons.sensors_rounded, title: tr(context, 'Smart monitoring', 'المراقبة الذكية', 'Slimme monitoring'), subtitle: tr(context, 'Only real connected hardware is shown.', 'يتم عرض الهاردوير الحقيقي المتصل فقط.', 'Alleen echt gekoppelde hardware wordt getoond.')),\n            const SizedBox(height: 12),\n            OutlinedButton.icon(\n              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SensorAlertRulesScreen(farmId: farmId))),\n              icon: const Icon(Icons.notifications_active_outlined, size: 27),\n              label: Text(tr(context, 'Configure real sensor alert rules', 'ضبط قواعد إنذارات الحساسات الحقيقية', 'Echte sensorwaarschuwingsregels instellen')),\n            ),\n            const SizedBox(height: 18),"""
if sensor_marker not in s:
    raise SystemExit('sensor marker not found')
s = s.replace(sensor_marker, sensor_repl, 1)

# Alerts panel: realtime all alerts + actual sensor value/threshold + sound/haptic for NEW alerts while app is active.
start = s.index('class V5AlertsPanel extends StatelessWidget {')
end = s.index('class V5HistoryPanel extends StatelessWidget {', start)
new_alerts = r'''class V5AlertsPanel extends StatefulWidget {
  const V5AlertsPanel({super.key, required this.farmId});
  final String farmId;

  @override
  State<V5AlertsPanel> createState() => _V5AlertsPanelState();
}

class _V5AlertsPanelState extends State<V5AlertsPanel> {
  final seen = <String>{};
  bool initialized = false;

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
        stream: VetBackend.instance.alertsStream(widget.farmId),
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
              if (!snapshot.hasData) const Center(child: CircularProgressIndicator()),
              if (snapshot.hasData && rows.isEmpty)
                _Notice(
                  icon: Icons.check_circle_outline_rounded,
                  title: tr(context, 'No active alerts', 'لا توجد إنذارات حالية', 'Geen actieve meldingen'),
                  text: tr(context, 'No AI or configured real-sensor alert is stored for this farm.', 'مفيش إنذار AI أو إنذار حساس حقيقي متضبط محفوظ للمزرعة دي.', 'Er is geen AI- of ingestelde echte-sensormelding voor deze boerderij opgeslagen.'),
                ),
              for (final a in rows)
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: Icon(
                      a['risk'] == 'red' ? Icons.error_rounded : Icons.warning_rounded,
                      size: 34,
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
s = s[:start] + new_alerts + s[end:]

# Account: support console only for authorized agents, legal hub replaces tiny About.
old_about_tile = """        _MenuTile(icon: Icons.info_outline_rounded, title: tr(context, 'About Vet AI', 'عن Vet AI', 'Over Vet AI'), subtitle: tr(context, 'Safety scope, data policy and product purpose.', 'نطاق الأمان وسياسة البيانات وهدف المنتج.', 'Veiligheidsbereik, databeleid en productdoel.'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const V5AboutScreen()))),"""
new_about_tile = """        FutureBuilder<bool>(\n          future: VetBackend.instance.isSupportAgent(),\n          builder: (context, agent) => agent.data == true\n              ? _MenuTile(\n                  icon: Icons.admin_panel_settings_outlined,\n                  title: tr(context, 'Company support console', 'كونسول دعم الشركة', 'Bedrijfssupportconsole'),\n                  subtitle: tr(context, 'See customer support threads and reply as Vet AI Support.', 'شوف محادثات العملاء ورد عليهم باسم دعم Vet AI.', 'Bekijk klantgesprekken en antwoord als Vet AI Support.'),\n                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VetSupportConsoleScreen())),\n                )\n              : const SizedBox.shrink(),\n        ),\n        _MenuTile(icon: Icons.info_outline_rounded, title: tr(context, 'Vet AI information & legal', 'معلومات وسياسات Vet AI', 'Vet AI informatie & juridisch'), subtitle: tr(context, 'About, mission, safety, knowledge, privacy and terms.', 'عن Vet AI والهدف والأمان والمعرفة والخصوصية والشروط.', 'Over Vet AI, missie, veiligheid, kennis, privacy en voorwaarden.'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VetLegalHubScreen()))),"""
if old_about_tile not in s:
    raise SystemExit('about tile target not found')
s = s.replace(old_about_tile, new_about_tile, 1)

p.write_text(s)

# Support camera explanation: once per account, same account key as AI scan.
p = Path('lib/support/support_chat_v6.dart')
s = p.read_text()
s = s.replace("import 'package:image_picker/image_picker.dart';\n", "import 'package:image_picker/image_picker.dart';\nimport 'package:shared_preferences/shared_preferences.dart';\n")
old_pick = '''  Future<void> _pickImage(ImageSource source) async {\n    final access = await _confirmAccess(\n      title: source == ImageSource.camera ? _t(context, 'Open camera?', 'فتح الكاميرا؟', 'Camera openen?') : _t(context, 'Open photos?', 'فتح الصور؟', 'Foto’s openen?'),\n      message: source == ImageSource.camera\n          ? _t(context, 'Vet AI Support will open the camera only after your approval. Nothing is sent until you approve the upload after editing.', 'دعم Vet AI هيفتح الكاميرا بعد موافقتك بس. مش هيتبعت أي حاجة إلا بعد ما توافق كمان على الرفع بعد التعديل.', 'Vet AI Support opent de camera pas na jouw toestemming. Er wordt niets verstuurd totdat je na het bewerken ook de upload bevestigt.')\n          : _t(context, 'Vet AI Support will open your photo picker only after your approval. Nothing is sent until you approve the upload.', 'دعم Vet AI هيفتح اختيار الصور بعد موافقتك بس. مش هيتبعت أي ملف إلا لما توافق على الرفع.', 'Vet AI Support opent de fotokiezer pas na jouw toestemming. Er wordt niets verstuurd totdat je de upload bevestigt.'),\n      icon: source == ImageSource.camera ? Icons.photo_camera_rounded : Icons.photo_library_rounded,\n    );\n    if (!access || !mounted) return;'''
new_pick = '''  Future<void> _pickImage(ImageSource source) async {\n    bool access = true;\n    if (source == ImageSource.camera) {\n      final prefs = await SharedPreferences.getInstance();\n      final key = 'vet_ai_camera_intro_seen_${VetBackend.instance.currentUser?.id ?? 'signed_out'}';\n      if (prefs.getBool(key) != true) {\n        access = await _confirmAccess(\n          title: _t(context, 'Open camera?', 'فتح الكاميرا؟', 'Camera openen?'),\n          message: _t(context, 'This one-time camera explanation is shared across Vet AI for this account. Nothing is sent until you approve an upload.', 'شرح الكاميرا ده بيظهر مرة واحدة للحساب في Vet AI كله. مش هيتبعت أي حاجة إلا لما توافق على الرفع.', 'Deze eenmalige camera-uitleg geldt voor heel Vet AI voor dit account. Er wordt niets verstuurd voordat je een upload bevestigt.'),\n          icon: Icons.photo_camera_rounded,\n        );\n        if (access) await prefs.setBool(key, true);\n      }\n    } else {\n      access = await _confirmAccess(\n        title: _t(context, 'Open photos?', 'فتح الصور؟', 'Foto’s openen?'),\n        message: _t(context, 'Vet AI Support will open your photo picker only after your approval. Nothing is sent until you approve the upload.', 'دعم Vet AI هيفتح اختيار الصور بعد موافقتك بس. مش هيتبعت أي ملف إلا لما توافق على الرفع.', 'Vet AI Support opent de fotokiezer pas na jouw toestemming. Er wordt niets verstuurd totdat je de upload bevestigt.'),\n        icon: Icons.photo_library_rounded,\n      );\n    }\n    if (!access || !mounted) return;'''
if old_pick not in s:
    raise SystemExit('support pick image target not found')
s = s.replace(old_pick, new_pick, 1)
p.write_text(s)

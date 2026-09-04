from pathlib import Path

p = Path('lib/v5_app.dart')
s = p.read_text()

# Imports and non-blocking app startup.
s = s.replace("import 'i18n/vet_locale.dart';\n", "import 'i18n/vet_locale.dart';\nimport 'startup/vet_startup_experience.dart';\nimport 'monitoring/smart_home_vitals.dart';\n", 1)
s = s.replace("  bool ready = false;\n", "", 1)
s = s.replace("    _bootstrap();\n", "    localeController.load();\n    translator.load();\n", 1)
start = s.find('  Future<void> _bootstrap() async {')
if start >= 0:
    end = s.find('  void _refresh()', start)
    if end < 0: raise SystemExit('bootstrap end not found')
    s = s[:start] + s[end:]
start = s.find('    if (!ready) {\n      return MaterialApp(')
if start >= 0:
    end = s.find('    return MaterialApp(', start + 20)
    if end < 0: raise SystemExit('normal material app not found')
    s = s[:start] + s[end:]
s = s.replace(
    "      theme: buildVetTheme(),\n      locale: localeController.locale,",
    "      theme: buildVetTheme(),\n      builder: (context, child) => GestureDetector(\n        behavior: HitTestBehavior.translucent,\n        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),\n        child: child ?? const SizedBox.shrink(),\n      ),\n      locale: localeController.locale,",
    1,
)
s = s.replace("      home: const V5AuthGate(),", "      home: const VetStartupExperience(child: V5AuthGate()),", 1)

# Home receives plan state.
s = s.replace("      V5Home(farm: farm, onAccount: openAccount),", "      V5Home(farm: farm, onAccount: openAccount, smart: smart),", 1)
s = s.replace(
    "class V5Home extends StatelessWidget {\n  const V5Home({super.key, required this.farm, required this.onAccount});\n  final Map<String, dynamic> farm;\n  final VoidCallback onAccount;",
    "class V5Home extends StatelessWidget {\n  const V5Home({super.key, required this.farm, required this.onAccount, required this.smart});\n  final Map<String, dynamic> farm;\n  final VoidCallback onAccount;\n  final bool smart;",
    1,
)

home_start = s.index('class V5Home extends StatelessWidget')
home_end = s.index('class V5ScanPanel extends StatefulWidget', home_start)
h = s[home_start:home_end]
old_header = """        Row(children: [
          const _BrandLockup(markWidth: 132, compact: true),
          const Spacer(),
          IconButton.filledTonal(
            tooltip: tr(context, 'Language', 'اللغة', 'Taal'),
            style: IconButton.styleFrom(backgroundColor: VetColors.surface3),
            icon: const Icon(Icons.language_rounded, size: 33, color: VetColors.blue),
            onPressed: () => showVetLanguagePicker(context),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: tr(context, 'Account & settings', 'الحساب والإعدادات', 'Account & instellingen'),
            style: IconButton.styleFrom(backgroundColor: VetColors.surface3),
            icon: const Icon(Icons.account_circle_outlined, size: 34, color: VetColors.primary),
            onPressed: onAccount,
          ),
        ]),
        const SizedBox(height: 22),"""
new_header = """        SizedBox(
          height: 108,
          child: Stack(
            children: [
              const Align(
                alignment: Alignment.topCenter,
                child: _BrandLockup(markWidth: 118, compact: true),
              ),
              PositionedDirectional(
                top: 0,
                end: 0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton.filledTonal(
                      tooltip: tr(context, 'Language', 'اللغة', 'Taal'),
                      style: IconButton.styleFrom(backgroundColor: VetColors.surface3),
                      icon: const Icon(Icons.language_rounded, size: 30, color: VetColors.blue),
                      onPressed: () => showVetLanguagePicker(context),
                    ),
                    const SizedBox(width: 5),
                    IconButton.filledTonal(
                      tooltip: tr(context, 'Account & settings', 'الحساب والإعدادات', 'Account & instellingen'),
                      style: IconButton.styleFrom(backgroundColor: VetColors.surface3),
                      icon: const Icon(Icons.account_circle_outlined, size: 31, color: VetColors.primary),
                      onPressed: onAccount,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),"""
if old_header not in h: raise SystemExit('home header target not found')
h = h.replace(old_header, new_header, 1)
h = h.replace(
    "        Text(farm['farm_name']?.toString() ?? 'Vet AI', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),",
    "        Text(farm['farm_name']?.toString() ?? 'Vet AI', textAlign: TextAlign.center, style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w900)),",
    1,
)
h = h.replace(
    "          Padding(padding: const EdgeInsets.only(top: 4), child: Text(farm['company_name'].toString(), style: const TextStyle(color: VetColors.muted, fontSize: 16))),",
    "          Padding(padding: const EdgeInsets.only(top: 4), child: Text(farm['company_name'].toString(), textAlign: TextAlign.center, style: const TextStyle(color: VetColors.muted, fontSize: 16, fontWeight: FontWeight.w600))),",
    1,
)
health_card = """        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [const Icon(Icons.monitor_heart_outlined, color: VetColors.primary, size: 32),"""
if health_card not in h: raise SystemExit('health card target not found')
h = h.replace(
    health_card,
    """        if (smart) ...[
          SmartHomeVitals(
            farmId: farm['id'] as String,
            translate: (en, ar, nl) => tr(context, en, ar, nl),
          ),
          const SizedBox(height: 18),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [const Icon(Icons.monitor_heart_outlined, color: VetColors.primary, size: 32),""",
    1,
)
s = s[:home_start] + h + s[home_end:]

# Explicit permission/consent before camera/photo access and before upload.
scan_start = s.index('class _V5ScanPanelState extends State<V5ScanPanel>')
scan_end = s.index('class V5SensorsPanel extends StatelessWidget', scan_start)
scan = s[scan_start:scan_end]
helper = r'''  Future<bool> _confirmAccess({required String title, required String message, required IconData icon}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(icon, size: 38, color: VetColors.primary),
        title: Text(title, textAlign: TextAlign.center),
        content: Text(message, textAlign: TextAlign.center, style: const TextStyle(height: 1.45)),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(tr(context, 'Cancel', 'إلغاء', 'Annuleren'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(tr(context, 'Allow', 'سماح', 'Toestaan'))),
        ],
      ),
    );
    return approved == true;
  }

  Future<bool> _confirmMedia(ImageSource source) => _confirmAccess(
        title: source == ImageSource.camera ? tr(context, 'Open camera?', 'فتح الكاميرا؟', 'Camera openen?') : tr(context, 'Open photos?', 'فتح الصور؟', 'Foto’s openen?'),
        message: source == ImageSource.camera
            ? tr(context, 'Vet AI will open the camera only after your approval. The photo is not uploaded until you explicitly start the health analysis.', 'Vet AI هيفتح الكاميرا بعد موافقتك بس. الصورة مش هتترفع إلا لما تضغط بنفسك على تحليل الحالة.', 'Vet AI opent de camera pas na jouw toestemming. De foto wordt pas geüpload wanneer je zelf de gezondheidsanalyse start.')
            : tr(context, 'Vet AI will let you choose a photo only after your approval. It will not upload the selected image until you explicitly start the health analysis.', 'Vet AI هيسمحلك تختار صورة بعد موافقتك بس، ومش هيرفع الصورة المختارة إلا لما تضغط بنفسك على تحليل الحالة.', 'Vet AI laat je pas na toestemming een foto kiezen. De gekozen foto wordt pas geüpload wanneer je zelf de gezondheidsanalyse start.'),
        icon: source == ImageSource.camera ? Icons.photo_camera_rounded : Icons.photo_library_rounded,
      );

'''
needle = '  Future<void> pick(ImageSource source) async {'
if needle not in scan: raise SystemExit('pick target not found')
scan = scan.replace(needle, helper + needle, 1)
scan = scan.replace("  Future<void> pick(ImageSource source) async {\n    final chosen = await picker.pickImage(", "  Future<void> pick(ImageSource source) async {\n    if (!await _confirmMedia(source)) return;\n    final chosen = await picker.pickImage(", 1)
scan = scan.replace(
    "  Future<void> analyze() async {\n    if (file == null || bytes == null) return;\n    setState(() { busy = true; result = null; });",
    """  Future<void> analyze() async {
    if (file == null || bytes == null) return;
    final approved = await _confirmAccess(
      title: tr(context, 'Upload for secure analysis?', 'رفع الصورة للتحليل الآمن؟', 'Uploaden voor beveiligde analyse?'),
      message: tr(context, 'The selected animal image and symptom notes will be uploaded to your protected Vet AI account for analysis. Continue?', 'الصورة اللي اخترتها وملاحظات الأعراض هيتـرفعوا لحساب Vet AI المحمي بتاعك علشان نحلل الحالة. تكمل؟', 'De gekozen dierfoto en symptoomnotities worden naar je beveiligde Vet AI-account geüpload voor analyse. Doorgaan?'),
      icon: Icons.cloud_upload_outlined,
    );
    if (!approved || !mounted) return;
    setState(() { busy = true; result = null; });""",
    1,
)
scan = scan.replace("    return ListView(\n      padding: const EdgeInsets.all(20),", "    return ListView(\n      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,\n      padding: const EdgeInsets.all(20),", 1)
scan = scan.replace(
    "              onFinalized: (finalReport) { if (mounted) setState(() => result = finalReport); },\n            )",
    """              onFinalized: (finalReport) { if (mounted) setState(() => result = finalReport); },
              onBack: () {
                FocusManager.instance.primaryFocus?.unfocus();
                if (mounted) setState(() => result = null);
              },
            )""",
    1,
)
s = s[:scan_start] + scan + s[scan_end:]

p.write_text(s)

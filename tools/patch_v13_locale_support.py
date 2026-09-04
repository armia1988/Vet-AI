from pathlib import Path

# --- Language picker: no visible loading overlay; atomic switch after batch is ready. ---
p = Path('lib/i18n/vet_locale.dart')
s = p.read_text()
start = s.index('class _VetLanguagePickerSheetState extends State<_VetLanguagePickerSheet> {')
new_tail = r'''class _VetLanguagePickerSheetState extends State<_VetLanguagePickerSheet> {
  bool _bundled(String code) => code == 'en' || code == 'ar' || code == 'nl';

  Future<void> _choose(String code) async {
    final controller = VetLocaleController.instance;
    final translator = VetTranslator.instance;
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.pop(context);

    if (_bundled(code)) {
      await controller.choose(code);
      return;
    }

    bool prepared = false;
    try {
      prepared = await translator
          .prepareLanguage(code, vetCoreUiStrings)
          .timeout(const Duration(seconds: 12), onTimeout: () => false);
    } catch (_) {
      prepared = false;
    }
    if (prepared) {
      await controller.choose(code);
    } else {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            _pickerText(
              messenger.context,
              'This language could not be prepared right now. Your current language was kept.',
              'اللغة دي ماقدرتش تجهز دلوقتي، فسيبنا اللغة الحالية زي ما هي بدل ما نعرض كلام ناقص أو مختلط.',
              'Deze taal kon nu niet worden voorbereid. De huidige taal is behouden.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _automatic() async {
    final controller = VetLocaleController.instance;
    final translator = VetTranslator.instance;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final device = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    Navigator.pop(context);

    if (!vetLanguages.any((l) => l.code == device)) {
      await controller.automatic();
      return;
    }
    if (_bundled(device)) {
      await controller.automatic();
      return;
    }

    bool prepared = false;
    try {
      prepared = await translator
          .prepareLanguage(device, vetCoreUiStrings)
          .timeout(const Duration(seconds: 12), onTimeout: () => false);
    } catch (_) {
      prepared = false;
    }
    if (prepared) {
      await controller.automatic();
    } else {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            _pickerText(
              messenger.context,
              'The device language could not be prepared right now. Your current language was kept.',
              'لغة الهاتف ماقدرتش تجهز دلوقتي، فسيبنا اللغة الحالية بدل ما نعرض ترجمة ناقصة.',
              'De apparaattaal kon nu niet worden voorbereid. De huidige taal is behouden.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = VetLocaleController.instance;
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: .84,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(width: 44, height: 4, decoration: BoxDecoration(color: VetColors.border, borderRadius: BorderRadius.circular(4))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(children: [
                const Icon(Icons.language_rounded, color: VetColors.blue, size: 31),
                const SizedBox(width: 12),
                Text(_pickerText(context, 'Language', 'اللغة', 'Taal'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              ]),
            ),
            ListTile(
              leading: const Icon(Icons.phone_iphone_rounded, size: 30, color: VetColors.primary),
              title: Text(_pickerText(context, 'Automatic', 'تلقائي', 'Automatisch'), style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(_pickerText(context, 'Device language', 'حسب لغة الموبايل', 'Taal van apparaat')),
              trailing: controller.isAutomatic ? const Icon(Icons.check_circle_rounded, color: VetColors.primary) : null,
              onTap: _automatic,
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: vetLanguages.length,
                itemBuilder: (context, i) {
                  final language = vetLanguages[i];
                  final selected = controller.manualCode == language.code;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: VetColors.surface3,
                      child: Text(language.code.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: VetColors.primaryDark)),
                    ),
                    title: Text(language.nativeName, style: const TextStyle(fontWeight: FontWeight.w800)),
                    trailing: selected ? const Icon(Icons.check_circle_rounded, color: VetColors.primary) : null,
                    onTap: () => _choose(language.code),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
              child: Text(
                _pickerText(
                  context,
                  'English, Arabic and Dutch are built in. Other languages are prepared in one batch and the app switches only when the complete pack is ready.',
                  'العربي والإنجليزي والهولندي موجودين جوه التطبيق. باقي اللغات بتتجهز دفعة واحدة، والبرنامج بيحوّل عليها بس لما الحزمة تكون كاملة علشان مايبقاش فيه نص عربي ونص إنجليزي.',
                  'Engels, Arabisch en Nederlands zijn ingebouwd. Andere talen worden als één pakket voorbereid; de app schakelt pas om wanneer het volledige pakket klaar is.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(color: VetColors.muted, fontSize: 12, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
'''
s = s[:start] + new_tail
p.write_text(s)

# --- Support chat: anti-double-send, dedupe, permission confirmation, keyboard behavior. ---
p = Path('lib/support/support_chat_v6.dart')
s = p.read_text()
s = s.replace(
    "  String? threadId;\n  bool sending = false;",
    "  String? threadId;\n  bool sending = false;\n  String? lastSentText;\n  DateTime? lastSentAt;",
    1,
)
old_send = r'''  Future<void> _sendText() async {
    if (threadId == null || message.text.trim().isEmpty || sending) return;
    final text = message.text;
    message.clear();
    setState(() => sending = true);
    try {
      await VetBackend.instance.sendSupportMessage(threadId!, text);
    } catch (_) {
      if (mounted) _error(_t(context, 'Message could not be sent.', 'تعذر إرسال الرسالة.', 'Bericht kon niet worden verzonden.'));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }
'''
new_send = r'''  Future<void> _sendText() async {
    final text = message.text.trim();
    if (threadId == null || text.isEmpty || sending) return;
    final now = DateTime.now();
    if (lastSentText == text && lastSentAt != null && now.difference(lastSentAt!) < const Duration(seconds: 2)) {
      return;
    }
    lastSentText = text;
    lastSentAt = now;
    message.clear();
    setState(() => sending = true);
    try {
      await VetBackend.instance.sendSupportMessage(threadId!, text);
    } catch (_) {
      lastSentText = null;
      lastSentAt = null;
      if (mounted) {
        message.text = text;
        message.selection = TextSelection.collapsed(offset: message.text.length);
        _error(_t(context, 'Message could not be sent.', 'الرسالة مااتبعتتش. جرّب تاني.', 'Bericht kon niet worden verzonden.'));
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }
'''
if old_send not in s: raise SystemExit('support send target not found')
s = s.replace(old_send, new_send, 1)

choose_marker = '  Future<void> _chooseAttachment() async {'
helper = r'''  Future<bool> _confirmAccess({required String title, required String message, required IconData icon}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(icon, size: 38, color: VetColors.primary),
        title: Text(title, textAlign: TextAlign.center),
        content: Text(message, textAlign: TextAlign.center, style: const TextStyle(height: 1.45)),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_t(context, 'Cancel', 'إلغاء', 'Annuleren'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_t(context, 'Allow', 'سماح', 'Toestaan'))),
        ],
      ),
    );
    return ok == true;
  }

'''
if choose_marker not in s: raise SystemExit('support attachment marker not found')
s = s.replace(choose_marker, helper + choose_marker, 1)
s = s.replace(
    "  Future<void> _pickImage(ImageSource source) async {\n    final selected = await picker.pickImage(",
    """  Future<void> _pickImage(ImageSource source) async {
    final access = await _confirmAccess(
      title: source == ImageSource.camera ? _t(context, 'Open camera?', 'فتح الكاميرا؟', 'Camera openen?') : _t(context, 'Open photos?', 'فتح الصور؟', 'Foto’s openen?'),
      message: source == ImageSource.camera
          ? _t(context, 'Vet AI Support will open the camera only after your approval. Nothing is sent until you approve the upload after editing.', 'دعم Vet AI هيفتح الكاميرا بعد موافقتك بس. مش هيتبعت أي حاجة إلا بعد ما توافق كمان على الرفع بعد التعديل.', 'Vet AI Support opent de camera pas na jouw toestemming. Er wordt niets verstuurd totdat je na het bewerken ook de upload bevestigt.')
          : _t(context, 'Vet AI Support will open your photo picker only after your approval. Nothing is sent until you approve the upload.', 'دعم Vet AI هيفتح اختيار الصور بعد موافقتك بس. مش هيتبعت أي ملف إلا لما توافق على الرفع.', 'Vet AI Support opent de fotokiezer pas na jouw toestemming. Er wordt niets verstuurd totdat je de upload bevestigt.'),
      icon: source == ImageSource.camera ? Icons.photo_camera_rounded : Icons.photo_library_rounded,
    );
    if (!access || !mounted) return;
    final selected = await picker.pickImage(""",
    1,
)
s = s.replace(
    "  Future<void> _pickFile() async {\n    final file = await FilePicker.pickFile(",
    """  Future<void> _pickFile() async {
    final access = await _confirmAccess(
      title: _t(context, 'Open files?', 'فتح الملفات؟', 'Bestanden openen?'),
      message: _t(context, 'Vet AI Support will open the system file picker after your approval. The chosen file is not uploaded until you confirm the upload.', 'دعم Vet AI هيفتح ملفات الجهاز بعد موافقتك. الملف اللي تختاره مش هيرتفع إلا لما تأكد الرفع.', 'Vet AI Support opent de systeembestandskiezer na jouw toestemming. Het gekozen bestand wordt pas geüpload nadat je de upload bevestigt.'),
      icon: Icons.folder_open_rounded,
    );
    if (!access || !mounted) return;
    final file = await FilePicker.pickFile(""",
    1,
)
s = s.replace(
    """  }) async {
    if (threadId == null || sending) return;
    setState(() => sending = true);""",
    """  }) async {
    if (threadId == null || sending) return;
    final upload = await _confirmAccess(
      title: _t(context, 'Upload this attachment?', 'رفع المرفق ده؟', 'Deze bijlage uploaden?'),
      message: _t(context, 'This attachment will be uploaded to your private Vet AI Support thread and shared with the support team. Continue?', 'المرفق ده هيتـرفع في شات دعم Vet AI الخاص بحسابك وهيبقى ظاهر لفريق الدعم. تكمل؟', 'Deze bijlage wordt naar je privé Vet AI Support-chat geüpload en met het supportteam gedeeld. Doorgaan?'),
      icon: Icons.cloud_upload_outlined,
    );
    if (!upload || !mounted) return;
    setState(() => sending = true);""",
    1,
)
s = s.replace("    return Scaffold(\n      appBar: AppBar(", "    return Scaffold(\n      resizeToAvoidBottomInset: true,\n      appBar: AppBar(", 1)
s = s.replace(
    """                    final rows = snapshot.data!;
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),""",
    """                    final seen = <String>{};
                    final rows = snapshot.data!
                        .where((row) => seen.add(row['id']?.toString() ?? ''))
                        .toList(growable: false);
                    return ListView.builder(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),""",
    1,
)
s = s.replace(
    """                        controller: message,
                        minLines: 1,""",
    """                        controller: message,
                        scrollPadding: const EdgeInsets.only(bottom: 140),
                        minLines: 1,""",
    1,
)
p.write_text(s)

# --- Codemagic: location permission + iOS framework support required by Printing. ---
p = Path('codemagic.yaml')
s = p.read_text()
s = s.replace(
    """          /usr/libexec/PlistBuddy -c \"Add :NSPhotoLibraryUsageDescription string 'Vet AI uses selected photos to create veterinary assessment cases.'\" ios/Runner/Info.plist || /usr/libexec/PlistBuddy -c \"Set :NSPhotoLibraryUsageDescription 'Vet AI uses selected photos to create veterinary assessment cases.'\" ios/Runner/Info.plist
          python3 - <<'PY'""",
    """          /usr/libexec/PlistBuddy -c \"Add :NSPhotoLibraryUsageDescription string 'Vet AI uses selected photos to create veterinary assessment cases.'\" ios/Runner/Info.plist || /usr/libexec/PlistBuddy -c \"Set :NSPhotoLibraryUsageDescription 'Vet AI uses selected photos to create veterinary assessment cases.'\" ios/Runner/Info.plist
          /usr/libexec/PlistBuddy -c \"Add :NSLocationWhenInUseUsageDescription string 'Vet AI uses your location, after your approval, to apply the correct local veterinary guidance and animal-health rules.'\" ios/Runner/Info.plist || /usr/libexec/PlistBuddy -c \"Set :NSLocationWhenInUseUsageDescription 'Vet AI uses your location, after your approval, to apply the correct local veterinary guidance and animal-health rules.'\" ios/Runner/Info.plist
          sed -i '' \"/target 'Runner' do/a\\
            use_frameworks!\n          \" ios/Podfile
          python3 - <<'PY'""",
    1,
)
p.write_text(s)

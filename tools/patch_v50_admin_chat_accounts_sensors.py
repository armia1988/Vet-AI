from pathlib import Path

# 1) Wire full account/invitation center into the existing Admin staff destination.
p = Path('lib/admin/admin_dashboard.dart')
s = p.read_text(encoding='utf-8')
anchor = "import 'admin_service.dart';\n"
if "import 'admin_account_center.dart';" not in s:
    s = s.replace(anchor, anchor + "import 'admin_account_center.dart';\n", 1)
s = s.replace("_at(context, 'Admin staff', 'فريق الإدارة', 'Adminteam')", "_at(context, 'Accounts & staff', 'الحسابات والموظفون', 'Accounts & medewerkers')")
s = s.replace("return VetAdminStaffCenter(key: ValueKey('admins-$refreshTick'));", "return VetAdminAccountCenter(key: ValueKey('admins-$refreshTick'));")
p.write_text(s, encoding='utf-8')

# 2) Route support inbox to the WhatsApp-style realtime agent thread.
p = Path('lib/admin/admin_support_center.dart')
s = p.read_text(encoding='utf-8')
if "../support/support_agent_thread_v2.dart" not in s:
    s = s.replace("import '../support/support_console.dart';\n", "import '../support/support_console.dart';\nimport '../support/support_agent_thread_v2.dart';\n", 1)
s = s.replace("VetSupportAgentThreadScreen(thread: enriched)", "VetSupportAgentThreadV2(thread: enriched)")
p.write_text(s, encoding='utf-8')

# 3) Secure account invitation route on the web admin URL.
p = Path('lib/admin/admin_web_root.dart')
s = p.read_text(encoding='utf-8')
if "import 'admin_invite_signup.dart';" not in s:
    s = s.replace("import 'admin_entry.dart';\n", "import 'admin_entry.dart';\nimport 'admin_invite_signup.dart';\n", 1)
old = """  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return const _AdminWebLoginApp();
"""
new = """  Widget build(BuildContext context) {
    final inviteToken = Uri.base.queryParameters['invite']?.trim() ?? '';
    final inviteEmail = Uri.base.queryParameters['email']?.trim() ?? '';
    if (inviteToken.isNotEmpty) {
      return VetAdminInviteApp(token: inviteToken, email: inviteEmail);
    }
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return const _AdminWebLoginApp();
"""
if old in s:
    s = s.replace(old, new, 1)
elif "final inviteToken = Uri.base.queryParameters['invite']" not in s:
    raise SystemExit('V50: admin web invite route anchor missing')
p.write_text(s, encoding='utf-8')

# 4) Add real sensor creation/provisioning from the admin sensor center.
p = Path('lib/admin/admin_sensor_center.dart')
s = p.read_text(encoding='utf-8')
if 'Future<void> _createDevice(' not in s:
    marker = "  Future<void> _editDevice(\n"
    if marker not in s:
        raise SystemExit('V50: sensor edit marker missing')
    method = r'''  Future<void> _createDevice(
    _SensorCenterData data, {
    String? initialFarmId,
  }) async {
    if (data.farms.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_st(context, 'Create a company/farm first.', 'أنشئ شركة/مزرعة الأول.', 'Maak eerst een bedrijf/boerderij.'))));
      return;
    }
    String? farmId = initialFarmId ?? data.farms.first['id']?.toString();
    final uid = TextEditingController();
    final name = TextEditingController();
    final type = TextEditingController(text: 'vetai_sensor_hub');
    final section = TextEditingController();
    final firmware = TextEditingController();
    final notes = TextEditingController();
    var active = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(_st(context, 'Add sensor device', 'إضافة حساس جديد', 'Sensor toevoegen')),
          content: SizedBox(
            width: 650,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  initialValue: farmId,
                  decoration: InputDecoration(labelText: _st(context, 'Customer company / farm', 'شركة / مزرعة العميل', 'Klantbedrijf / boerderij')),
                  items: [for (final f in data.farms) DropdownMenuItem(value: f['id'].toString(), child: Text('${f['company_name'] ?? ''} / ${f['farm_name'] ?? ''}'))],
                  onChanged: (v) => setLocal(() => farmId = v),
                ),
                const SizedBox(height: 10),
                TextField(controller: uid, decoration: InputDecoration(labelText: _st(context, 'Device UID / serial number', 'UID / الرقم التسلسلي', 'Apparaat-UID / serienummer'))),
                const SizedBox(height: 10),
                TextField(controller: name, decoration: InputDecoration(labelText: _st(context, 'Display name', 'اسم الحساس', 'Weergavenaam'))),
                const SizedBox(height: 10),
                TextField(controller: type, decoration: InputDecoration(labelText: _st(context, 'Device type', 'نوع الجهاز', 'Apparaattype'))),
                const SizedBox(height: 10),
                TextField(controller: section, decoration: InputDecoration(labelText: _st(context, 'Section / barn', 'القسم / الحظيرة', 'Afdeling / stal'))),
                const SizedBox(height: 10),
                TextField(controller: firmware, decoration: const InputDecoration(labelText: 'Firmware')),
                const SizedBox(height: 10),
                TextField(controller: notes, minLines: 2, maxLines: 5, decoration: InputDecoration(labelText: _st(context, 'Private admin notes', 'ملاحظات الإدارة', 'Privé-adminnotities'))),
                SwitchListTile(contentPadding: EdgeInsets.zero, value: active, onChanged: (v) => setLocal(() => active = v), title: Text(_st(context, 'Enable device immediately', 'تفعيل الحساس فورًا', 'Apparaat direct activeren'))),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_st(context, 'Cancel', 'إلغاء', 'Annuleren'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_st(context, 'Add sensor', 'إضافة الحساس', 'Sensor toevoegen'))),
          ],
        ),
      ),
    );
    if (ok != true || farmId == null) return;
    if (uid.text.trim().isEmpty || type.text.trim().isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_st(context, 'Device UID and type are required.', 'UID ونوع الجهاز مطلوبين.', 'Apparaat-UID en type zijn verplicht.'))));
      return;
    }
    try {
      await admin.client.rpc('admin_create_sensor_device', params: {
        'p_farm_id': farmId,
        'p_device_uid': uid.text.trim(),
        'p_display_name': name.text.trim(),
        'p_device_type': type.text.trim(),
        'p_section_name': section.text.trim(),
        'p_firmware_version': firmware.text.trim(),
        'p_active': active,
        'p_admin_notes': notes.text.trim(),
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_st(context, 'Sensor added to the customer account.', 'تم إضافة الحساس لحساب العميل.', 'Sensor toegevoegd aan het klantaccount.'))));
      reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_st(context, 'Could not add sensor', 'تعذر إضافة الحساس', 'Sensor kon niet worden toegevoegd')}: $e'), backgroundColor: VetColors.red));
    }
  }

'''
    s = s.replace(marker, method + marker, 1)

old_devices = """  Widget _devices(BuildContext context, _SensorCenterData data, Map<String, String> farmNames) => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          for (final row in data.sensors)
"""
new_devices = """  Widget _devices(BuildContext context, _SensorCenterData data, Map<String, String> farmNames) => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_st(context, 'All sensor devices', 'كل الحساسات', 'Alle sensoren'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              Text(_st(context, 'Add, move, rename, enable or block any customer sensor.', 'أضف أو انقل أو غيّر اسم أو فعّل/افصل أي حساس للعميل.', 'Voeg sensoren toe, verplaats, hernoem, activeer of blokkeer ze.'), style: const TextStyle(color: VetColors.muted)),
            ])),
            FilledButton.icon(onPressed: () => _createDevice(data), icon: const Icon(Icons.add_rounded), label: Text(_st(context, 'Add sensor', 'إضافة حساس', 'Sensor toevoegen'))),
          ]),
          const SizedBox(height: 14),
          for (final row in data.sensors)
"""
if old_devices in s:
    s = s.replace(old_devices, new_devices, 1)
elif "onPressed: () => _createDevice(data)" not in s:
    raise SystemExit('V50: sensor devices list anchor missing')
p.write_text(s, encoding='utf-8')

# 5) Customer support chat: force chronological order, keep newest at bottom,
# auto-scroll, and add voice/video call controls + incoming call bar.
p = Path('lib/support/support_chat_v6.dart')
s = p.read_text(encoding='utf-8')
if "support_call_service.dart" not in s:
    s = s.replace("import '../theme/app_theme.dart';\n", "import '../theme/app_theme.dart';\nimport 'support_call_bar.dart';\nimport 'support_call_service.dart';\n", 1)
fields = """  final message = TextEditingController();
  final picker = ImagePicker();
  String? threadId;
"""
if fields in s and "final scroll = ScrollController();" not in s:
    s = s.replace(fields, """  final message = TextEditingController();
  final picker = ImagePicker();
  final scroll = ScrollController();
  int lastMessageCount = -1;
  bool firstMessageScroll = true;
  String? threadId;
""", 1)
if "Future<void> _startSupportCall(" not in s:
    marker = "  void _error(String text) {\n"
    method = r'''  Future<void> _startSupportCall(String type) async {
    if (threadId == null) return;
    try {
      final call = await VetSupportCallService.instance.startCall(threadId: threadId!, callerRole: 'user', callType: type);
      await VetSupportCallService.instance.openMediaRoom(call);
    } catch (e) {
      if (mounted) _error('${_t(context, 'Call could not start.', 'المكالمة ما بدأتش.', 'Oproep kon niet starten.')} $e');
    }
  }

  void _scrollToNewest({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.hasClients) return;
      final target = scroll.position.maxScrollExtent;
      if (animated) {
        scroll.animateTo(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      } else {
        scroll.jumpTo(target);
      }
    });
  }

'''
    if marker not in s:
        raise SystemExit('V50: customer call method anchor missing')
    s = s.replace(marker, method + marker, 1)
s = s.replace("    message.dispose();\n    super.dispose();", "    message.dispose();\n    scroll.dispose();\n    super.dispose();")
old_appbar = """        title: Row(children: [
          const Icon(Icons.support_agent_rounded, size: 32, color: VetColors.primary),
          const SizedBox(width: 10),
          Text(_t(context, 'Vet AI Support', 'دعم Vet AI', 'Vet AI Support')),
        ]),
      ),
"""
new_appbar = """        title: Row(children: [
          const Icon(Icons.support_agent_rounded, size: 32, color: VetColors.primary),
          const SizedBox(width: 10),
          Text(_t(context, 'Vet AI Support', 'دعم Vet AI', 'Vet AI Support')),
        ]),
        actions: [
          IconButton(tooltip: _t(context, 'Video call', 'مكالمة فيديو', 'Videogesprek'), onPressed: threadId == null ? null : () => _startSupportCall('video'), icon: const Icon(Icons.videocam_rounded)),
          IconButton(tooltip: _t(context, 'Voice call', 'مكالمة صوتية', 'Spraakoproep'), onPressed: threadId == null ? null : () => _startSupportCall('voice'), icon: const Icon(Icons.call_rounded)),
        ],
      ),
"""
if old_appbar in s:
    s = s.replace(old_appbar, new_appbar, 1)
elif "_startSupportCall('video')" not in s:
    raise SystemExit('V50: customer appbar anchor missing')
column_anchor = """          : Column(children: [
              Padding(
"""
if column_anchor in s and "SupportCallBar(threadId: threadId!, role: 'user')" not in s:
    s = s.replace(column_anchor, """          : Column(children: [
              SupportCallBar(threadId: threadId!, role: 'user'),
              Padding(
""", 1)
old_rows = """                    final rows = snapshot.data!
                        .where((row) => seen.add(row['id']?.toString() ?? ''))
                        .toList(growable: false);
                    return ListView.builder(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
"""
new_rows = """                    final rows = snapshot.data!
                        .where((row) => seen.add(row['id']?.toString() ?? ''))
                        .toList(growable: true)
                      ..sort((a, b) {
                        final at = DateTime.tryParse('${a['created_at'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0);
                        final bt = DateTime.tryParse('${b['created_at'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0);
                        return at.compareTo(bt);
                      });
                    if (rows.length != lastMessageCount) {
                      lastMessageCount = rows.length;
                      _scrollToNewest(animated: !firstMessageScroll);
                      firstMessageScroll = false;
                    }
                    return ListView.builder(
                      controller: scroll,
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
"""
if old_rows in s:
    s = s.replace(old_rows, new_rows, 1)
elif "controller: scroll," not in s:
    raise SystemExit('V50: customer chat rows anchor missing')
p.write_text(s, encoding='utf-8')

print('Vet AI V50 wired: account invites, customer/staff access, sensor create/edit, chronological chat, call controls')

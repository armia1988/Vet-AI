from pathlib import Path


def add_after(text: str, anchor: str, addition: str, label: str) -> str:
    if addition.strip() in text:
        return text
    if anchor not in text:
        raise SystemExit(f'V55: {label} anchor missing')
    return text.replace(anchor, anchor + addition, 1)


# ---------------------------------------------------------------------------
# 1) Customer support: WhatsApp-style rich attachment menu and message cards.
# ---------------------------------------------------------------------------
p = Path('lib/support/support_chat_v6.dart')
s = p.read_text(encoding='utf-8')
s = add_after(s, "import 'package:flutter/rendering.dart';\n", "import 'package:geolocator/geolocator.dart';\nimport 'package:intl/intl.dart';\n", 'customer package imports')
s = add_after(s, "import '../theme/app_theme.dart';\n", "import 'support_rich_service.dart';\nimport 'support_rich_widgets.dart';\n", 'customer rich imports')

choose_start = s.find('  Future<void> _chooseAttachment() async {')
choose_end = s.find('  Future<void> _pickImage(', choose_start)
if choose_start < 0 or choose_end < 0:
    raise SystemExit('V55: customer attachment method markers missing')

customer_rich_methods = r'''  Future<void> _chooseAttachment() async {
    if (threadId == null || sending) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFFE9EDEF),
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SupportAttachmentGrid(
        onPhotos: () {
          Navigator.pop(sheetContext);
          _pickImage(ImageSource.gallery);
        },
        onCamera: () {
          Navigator.pop(sheetContext);
          _pickImage(ImageSource.camera);
        },
        onLocation: () {
          Navigator.pop(sheetContext);
          _sendLocation();
        },
        onDocument: () {
          Navigator.pop(sheetContext);
          _pickFile();
        },
        onPoll: () {
          Navigator.pop(sheetContext);
          _createPoll();
        },
        onEvent: () {
          Navigator.pop(sheetContext);
          _createEvent();
        },
      ),
    );
  }

  Future<void> _sendLocation() async {
    if (threadId == null || sending) return;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError(_t(context, 'Location services are disabled.', 'خدمة الموقع مقفولة.', 'Locatieservices zijn uitgeschakeld.'));
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw StateError(_t(context, 'Location permission is required to share your location.', 'لازم تسمح بالموقع علشان تبعته.', 'Locatietoestemming is nodig om je locatie te delen.'));
      }
      setState(() => sending = true);
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      await VetSupportRichService.instance.sendRichMessage(
        threadId: threadId!,
        senderRole: 'user',
        messageType: 'location',
        metadata: {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy_m': position.accuracy,
          'label': _t(context, 'Current location', 'الموقع الحالي', 'Huidige locatie'),
        },
      );
      _scrollToNewest();
    } catch (e) {
      if (mounted) _error('$e');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _createPoll() async {
    if (threadId == null || sending) return;
    final question = TextEditingController();
    final first = TextEditingController();
    final second = TextEditingController();
    final third = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t(context, 'Create poll', 'إنشاء استطلاع', 'Peiling maken')),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: question, decoration: InputDecoration(labelText: _t(context, 'Question', 'السؤال', 'Vraag'))),
              const SizedBox(height: 10),
              TextField(controller: first, decoration: InputDecoration(labelText: '${_t(context, 'Option', 'اختيار', 'Optie')} 1')),
              const SizedBox(height: 10),
              TextField(controller: second, decoration: InputDecoration(labelText: '${_t(context, 'Option', 'اختيار', 'Optie')} 2')),
              const SizedBox(height: 10),
              TextField(controller: third, decoration: InputDecoration(labelText: '${_t(context, 'Option', 'اختيار', 'Optie')} 3 (${_t(context, 'optional', 'اختياري', 'optioneel')})')),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_t(context, 'Cancel', 'إلغاء', 'Annuleren'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_t(context, 'Send', 'إرسال', 'Versturen'))),
        ],
      ),
    );
    if (ok != true) return;
    final options = [first.text.trim(), second.text.trim(), third.text.trim()].where((e) => e.isNotEmpty).toList();
    if (question.text.trim().isEmpty || options.length < 2) {
      if (mounted) _error(_t(context, 'Add a question and at least two options.', 'اكتب سؤال واختيارين على الأقل.', 'Voeg een vraag en minstens twee opties toe.'));
      return;
    }
    await VetSupportRichService.instance.sendRichMessage(
      threadId: threadId!,
      senderRole: 'user',
      messageType: 'poll',
      message: question.text,
      metadata: {'question': question.text.trim(), 'options': options},
    );
    _scrollToNewest();
  }

  Future<void> _createEvent() async {
    if (threadId == null || sending) return;
    final title = TextEditingController();
    final place = TextEditingController();
    DateTime date = DateTime.now().add(const Duration(hours: 1));
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(_t(context, 'Create event', 'إنشاء حدث', 'Evenement maken')),
          content: SizedBox(
            width: 520,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: title, decoration: InputDecoration(labelText: _t(context, 'Event title', 'اسم الحدث', 'Naam evenement'))),
              const SizedBox(height: 10),
              TextField(controller: place, decoration: InputDecoration(labelText: _t(context, 'Place (optional)', 'المكان (اختياري)', 'Plaats (optioneel)'))),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_rounded),
                title: Text('${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}  ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'),
                trailing: TextButton(
                  onPressed: () async {
                    final pickedDate = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 3650)), initialDate: date);
                    if (pickedDate == null || !context.mounted) return;
                    final pickedTime = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(date));
                    if (pickedTime == null) return;
                    setLocal(() => date = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute));
                  },
                  child: Text(_t(context, 'Change', 'تغيير', 'Wijzigen')),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_t(context, 'Cancel', 'إلغاء', 'Annuleren'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_t(context, 'Send', 'إرسال', 'Versturen'))),
          ],
        ),
      ),
    );
    if (ok != true || title.text.trim().isEmpty) return;
    await VetSupportRichService.instance.sendRichMessage(
      threadId: threadId!,
      senderRole: 'user',
      messageType: 'event',
      message: title.text,
      metadata: {'title': title.text.trim(), 'place': place.text.trim(), 'starts_at': date.toUtc().toIso8601String()},
    );
    _scrollToNewest();
  }

'''
s = s[:choose_start] + customer_rich_methods + s[choose_end:]

# WhatsApp-like surface and remove the non-WhatsApp banner card above the chat.
s = s.replace(
    "return Scaffold(\n      resizeToAvoidBottomInset: true,\n      appBar: AppBar(",
    "return Scaffold(\n      resizeToAvoidBottomInset: true,\n      backgroundColor: const Color(0xFFEFEAE2),\n      appBar: AppBar(\n        backgroundColor: const Color(0xFFF0F2F5),\n        foregroundColor: const Color(0xFF111B21),\n        scrolledUnderElevation: 0,",
    1,
)

banner_start = s.find("              Padding(\n                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),")
banner_end = s.find("              Expanded(\n                child: StreamBuilder<List<Map<String, dynamic>>>(", banner_start)
if banner_start >= 0 and banner_end > banner_start:
    s = s[:banner_start] + s[banner_end:]

s = s.replace(
    "color: mine ? VetColors.softBlue : VetColors.surface,\n          borderRadius: BorderRadius.circular(18),\n          border: Border.all(color: mine ? VetColors.blue : VetColors.border),",
    "color: mine ? const Color(0xFFD9FDD3) : Colors.white,\n          borderRadius: BorderRadius.only(\n            topLeft: const Radius.circular(8),\n            topRight: const Radius.circular(8),\n            bottomLeft: Radius.circular(mine ? 8 : 2),\n            bottomRight: Radius.circular(mine ? 2 : 8),\n          ),",
    1,
)

bubble_column = """        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [\n          if (isImage)\n"""
if bubble_column in s:
    s = s.replace(
        bubble_column,
        """        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [\n          if ({'location', 'poll', 'event'}.contains(row['message_type'])) ...[\n            SupportRichMessageBody(row: row),\n            const SizedBox(height: 4),\n          ],\n          if (isImage)\n""",
        1,
    )
elif 'SupportRichMessageBody(row: row)' not in s:
    raise SystemExit('V55: customer bubble body anchor missing')

role_footer_start = s.find("          Row(mainAxisSize: MainAxisSize.min, children: [\n            Icon(role == 'support'")
role_footer_end = s.find("          ]),\n        ]),", role_footer_start)
if role_footer_start >= 0 and role_footer_end > role_footer_start:
    role_footer_end += len("          ]),\n")
    replacement = r'''          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(
                DateTime.tryParse('${row['created_at'] ?? ''}') == null
                    ? ''
                    : DateFormat.Hm().format(DateTime.parse('${row['created_at']}').toLocal()),
                style: const TextStyle(fontSize: 10.5, color: Color(0xFF667781)),
              ),
              if (mine) ...[
                const SizedBox(width: 3),
                const Icon(Icons.done_all_rounded, size: 15, color: Color(0xFF53BDEB)),
              ],
            ]),
          ),
'''
    s = s[:role_footer_start] + replacement + s[role_footer_end:]

# Smaller WhatsApp-style send button.
s = s.replace(
    """                    IconButton.filled(
                      onPressed: sending ? null : _sendText,
                      icon: sending
                          ? const SizedBox.square(dimension: 21, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send_rounded, size: 29),
                    ),
""",
    """                    SizedBox.square(
                      dimension: 43,
                      child: IconButton.filled(
                        style: IconButton.styleFrom(backgroundColor: const Color(0xFF00A884), padding: EdgeInsets.zero),
                        onPressed: sending ? null : _sendText,
                        icon: sending
                            ? const SizedBox.square(dimension: 17, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.send_rounded, size: 23, color: Colors.white),
                      ),
                    ),
""",
    1,
)
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# 2) Company support agent chat: same rich attachment options and farm avatar.
# ---------------------------------------------------------------------------
p = Path('lib/support/support_agent_thread_v2.dart')
s = p.read_text(encoding='utf-8')
s = add_after(s, "import 'package:flutter/material.dart';\n", "import 'package:geolocator/geolocator.dart';\nimport 'package:image_picker/image_picker.dart';\n", 'agent package imports')
s = add_after(s, "import 'support_call_service.dart';\n", "import 'support_rich_service.dart';\nimport 'support_rich_widgets.dart';\n", 'agent rich imports')

field_anchor = "  final message = TextEditingController();\n  final scroll = ScrollController();\n"
if field_anchor in s and 'final imagePicker = ImagePicker();' not in s:
    s = s.replace(field_anchor, field_anchor + "  final imagePicker = ImagePicker();\n", 1)

agent_insert_anchor = '  Future<void> _sendFile() async {\n'
if 'Future<void> _showAttachmentMenu() async' not in s:
    if agent_insert_anchor not in s:
        raise SystemExit('V55: agent attachment anchor missing')
    agent_methods = r'''  Future<void> _showAttachmentMenu() async {
    if (sending) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFFE9EDEF),
      showDragHandle: true,
      builder: (sheetContext) => SupportAttachmentGrid(
        onPhotos: () { Navigator.pop(sheetContext); _sendPhoto(ImageSource.gallery); },
        onCamera: () { Navigator.pop(sheetContext); _sendPhoto(ImageSource.camera); },
        onLocation: () { Navigator.pop(sheetContext); _sendLocation(); },
        onDocument: () { Navigator.pop(sheetContext); _sendFile(); },
        onPoll: () { Navigator.pop(sheetContext); _createPoll(); },
        onEvent: () { Navigator.pop(sheetContext); _createEvent(); },
      ),
    );
  }

  Future<void> _sendPhoto(ImageSource source) async {
    if (sending) return;
    final selected = await imagePicker.pickImage(source: source, imageQuality: 92, maxWidth: 2400);
    if (selected == null) return;
    setState(() => sending = true);
    try {
      final bytes = await selected.readAsBytes();
      final name = selected.name.isEmpty ? 'photo.jpg' : selected.name;
      final uploaded = await backend.uploadSupportAttachment(
        threadId: threadId,
        bytes: bytes,
        fileName: name,
        mimeType: name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg',
      );
      final user = backend.currentUser;
      if (user == null) throw StateError('Support login required');
      await backend.client.from('support_messages').insert({
        'thread_id': threadId,
        'sender_id': user.id,
        'sender_role': 'support',
        'message_type': 'image',
        'message': message.text.trim().isEmpty ? null : message.text.trim(),
        'attachment_path': uploaded['path'],
        'attachment_name': uploaded['name'],
        'attachment_mime': uploaded['mime'],
        'attachment_size_bytes': uploaded['size'],
      });
      message.clear();
      await backend.client.from('support_threads').update({'status': 'open', 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', threadId);
      _toBottom();
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _sendLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) throw StateError(_wt(context, 'Location services are disabled.', 'خدمة الموقع مقفولة.', 'Locatieservices zijn uitgeschakeld.'));
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) throw StateError(_wt(context, 'Location permission is required.', 'لازم تسمح بالموقع.', 'Locatietoestemming is vereist.'));
      setState(() => sending = true);
      final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      await VetSupportRichService.instance.sendRichMessage(
        threadId: threadId,
        senderRole: 'support',
        messageType: 'location',
        metadata: {'latitude': position.latitude, 'longitude': position.longitude, 'accuracy_m': position.accuracy, 'label': _wt(context, 'Vet AI Support location', 'موقع دعم Vet AI', 'Locatie Vet AI Support')},
      );
      _toBottom();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: VetColors.red));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _createPoll() async {
    final q = TextEditingController();
    final a = TextEditingController();
    final b = TextEditingController();
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_wt(context, 'Create poll', 'إنشاء استطلاع', 'Peiling maken')),
        content: SizedBox(width: 520, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: q, decoration: InputDecoration(labelText: _wt(context, 'Question', 'السؤال', 'Vraag'))),
          const SizedBox(height: 9),
          TextField(controller: a, decoration: InputDecoration(labelText: '${_wt(context, 'Option', 'اختيار', 'Optie')} 1')),
          const SizedBox(height: 9),
          TextField(controller: b, decoration: InputDecoration(labelText: '${_wt(context, 'Option', 'اختيار', 'Optie')} 2')),
          const SizedBox(height: 9),
          TextField(controller: c, decoration: InputDecoration(labelText: '${_wt(context, 'Option', 'اختيار', 'Optie')} 3')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_wt(context, 'Cancel', 'إلغاء', 'Annuleren'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_wt(context, 'Send', 'إرسال', 'Versturen'))),
        ],
      ),
    );
    if (ok != true) return;
    final options = [a.text.trim(), b.text.trim(), c.text.trim()].where((e) => e.isNotEmpty).toList();
    if (q.text.trim().isEmpty || options.length < 2) return;
    await VetSupportRichService.instance.sendRichMessage(threadId: threadId, senderRole: 'support', messageType: 'poll', message: q.text, metadata: {'question': q.text.trim(), 'options': options});
    _toBottom();
  }

  Future<void> _createEvent() async {
    final title = TextEditingController();
    final place = TextEditingController();
    DateTime date = DateTime.now().add(const Duration(hours: 1));
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(_wt(context, 'Create event', 'إنشاء حدث', 'Evenement maken')),
          content: SizedBox(width: 520, child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: title, decoration: InputDecoration(labelText: _wt(context, 'Event title', 'اسم الحدث', 'Naam evenement'))),
            const SizedBox(height: 9),
            TextField(controller: place, decoration: InputDecoration(labelText: _wt(context, 'Place', 'المكان', 'Plaats'))),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_rounded),
              title: Text('${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'),
              trailing: TextButton(onPressed: () async {
                final d = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 3650)), initialDate: date);
                if (d == null || !context.mounted) return;
                final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(date));
                if (t != null) setLocal(() => date = DateTime(d.year, d.month, d.day, t.hour, t.minute));
              }, child: Text(_wt(context, 'Change', 'تغيير', 'Wijzigen'))),
            ),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_wt(context, 'Cancel', 'إلغاء', 'Annuleren'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_wt(context, 'Send', 'إرسال', 'Versturen'))),
          ],
        ),
      ),
    );
    if (ok != true || title.text.trim().isEmpty) return;
    await VetSupportRichService.instance.sendRichMessage(threadId: threadId, senderRole: 'support', messageType: 'event', message: title.text, metadata: {'title': title.text.trim(), 'place': place.text.trim(), 'starts_at': date.toUtc().toIso8601String()});
    _toBottom();
  }

'''
    s = s.replace(agent_insert_anchor, agent_methods + agent_insert_anchor, 1)

# Farm/company picture in the support header; tap opens full-size viewer.
s = s.replace(
    """            const CircleAvatar(
              radius: 18,
              backgroundColor: Color(0xFFD9FDD3),
              child: Icon(Icons.person_rounded, color: _waGreen),
            ),
""",
    """            VetFarmAvatar(
              photoPath: farm['profile_photo_path']?.toString(),
              radius: 18,
              fallbackIcon: Icons.domain_rounded,
            ),
""",
    1,
)

s = s.replace("onPressed: sending ? null : _sendFile,", "onPressed: sending ? null : _showAttachmentMenu,", 1)
s = s.replace("radius: 24,\n                    backgroundColor: _waGreen,", "radius: 21,\n                    backgroundColor: _waGreen,", 1)
s = s.replace("icon: const Icon(Icons.add_rounded, size: 28),", "icon: const Icon(Icons.add_rounded, size: 27),", 1)

agent_bubble_anchor = """            children: [
              if (hasAttachment)
                _AttachmentPreview(row: row, onOpen: onAttachment),
"""
if agent_bubble_anchor in s:
    s = s.replace(
        agent_bubble_anchor,
        """            children: [
              if ({'location', 'poll', 'event'}.contains(row['message_type'])) ...[
                SupportRichMessageBody(row: row),
                const SizedBox(height: 5),
              ],
              if (hasAttachment)
                _AttachmentPreview(row: row, onOpen: onAttachment),
""",
        1,
    )
elif 'SupportRichMessageBody(row: row)' not in s:
    raise SystemExit('V55: agent rich bubble anchor missing')
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# 3) Company/farm profile pictures in Admin and farm-owner profile.
# ---------------------------------------------------------------------------
p = Path('lib/admin/admin_company_center.dart')
s = p.read_text(encoding='utf-8')
s = add_after(s, "import '../i18n/vet_locale.dart';\n", "import '../support/farm_profile_photo_editor.dart';\nimport '../support/support_rich_widgets.dart';\n", 'admin company profile imports')
s = s.replace(
    "const CircleAvatar(radius: 24, child: Icon(Icons.domain_rounded)),",
    "VetFarmAvatar(photoPath: farm['profile_photo_path']?.toString(), radius: 24, fallbackIcon: Icons.domain_rounded),",
    1,
)
# V52 has already rebuilt the detail screen before V55 executes.
overview_anchor = """            _detailList(context, [
              _line(_ct(context, 'Company', 'الشركة', 'Bedrijf'), farm['company_name']),
"""
if overview_anchor in s:
    s = s.replace(
        overview_anchor,
        """            _detailList(context, [
              VetFarmProfilePhotoEditor(farm: farm, onChanged: reload),
              const SizedBox(height: 10),
              _line(_ct(context, 'Company', 'الشركة', 'Bedrijf'), farm['company_name']),
""",
        1,
    )
elif 'VetFarmProfilePhotoEditor(farm: farm, onChanged: reload)' not in s:
    raise SystemExit('V55: V52 company overview anchor missing')
p.write_text(s, encoding='utf-8')

p = Path('lib/v5_app.dart')
s = p.read_text(encoding='utf-8')
s = add_after(s, "import 'support/support_console.dart';\n", "import 'support/farm_profile_photo_editor.dart';\n", 'farm owner profile import')
profile_anchor = """          _ProfileHeroCard(
            name: c['full_name']!.text,
            email: VetBackend.instance.currentUser?.email ?? '',
            farmName: c['farm_name']!.text,
          ),
          const SizedBox(height: 18),
"""
if profile_anchor in s:
    s = s.replace(
        profile_anchor,
        """          VetFarmProfilePhotoEditor(farm: widget.farm),
          const SizedBox(height: 18),
          _ProfileHeroCard(
            name: c['full_name']!.text,
            email: VetBackend.instance.currentUser?.email ?? '',
            farmName: c['farm_name']!.text,
          ),
          const SizedBox(height: 18),
""",
        1,
    )
elif 'VetFarmProfilePhotoEditor(farm: widget.farm)' not in s:
    raise SystemExit('V55: farm owner profile card anchor missing')
p.write_text(s, encoding='utf-8')

# Old in-app company support console should also receive the farm photo field.
p = Path('lib/services/vet_operations.dart')
s = p.read_text(encoding='utf-8')
s = s.replace(
    'farms(farm_name,company_name)',
    'farms(farm_name,company_name,profile_photo_path)',
    1,
)
p.write_text(s, encoding='utf-8')

# Admin support inbox list uses the same clickable farm avatar.
p = Path('lib/admin/admin_support_center.dart')
s = p.read_text(encoding='utf-8')
s = add_after(s, "import '../support/support_console.dart';\n", "import '../support/support_rich_widgets.dart';\n", 'admin support avatar import')
old_leading = r'''        leading: Badge(
          isLabelVisible: unread > 0,
          label: Text('$unread'),
          child: CircleAvatar(
            backgroundColor: priority == 'urgent' ? VetColors.red.withValues(alpha: .12) : VetColors.softGreen,
            child: Icon(Icons.chat_bubble_rounded, color: priority == 'urgent' ? VetColors.red : VetColors.green),
          ),
        ),
'''
new_leading = r'''        leading: Badge(
          isLabelVisible: unread > 0,
          label: Text('$unread'),
          child: VetFarmAvatar(
            photoPath: farm['profile_photo_path']?.toString(),
            radius: 22,
            fallbackIcon: Icons.domain_rounded,
          ),
        ),
'''
if old_leading in s:
    s = s.replace(old_leading, new_leading, 1)
elif "photoPath: farm['profile_photo_path']" not in s:
    raise SystemExit('V55: support inbox avatar anchor missing')
p.write_text(s, encoding='utf-8')

# Explicit P2P-first ICE policy: direct host/srflx candidates remain available;
# TURN, when configured later, is fallback rather than mandatory relay.
p = Path('lib/support/support_webrtc_call_page.dart')
s = p.read_text(encoding='utf-8')
if "'iceTransportPolicy': 'all'," not in s:
    anchor = "        'sdpSemantics': 'unified-plan',\n"
    if anchor not in s:
        raise SystemExit('V55: WebRTC peer config anchor missing')
    s = s.replace(anchor, anchor + "        'iceTransportPolicy': 'all',\n        'iceCandidatePoolSize': 2,\n", 1)
p.write_text(s, encoding='utf-8')

# Android location permission for generated native projects.
manifest = Path('android/app/src/main/AndroidManifest.xml')
if manifest.exists():
    text = manifest.read_text(encoding='utf-8')
    permission = 'android.permission.ACCESS_FINE_LOCATION'
    if permission not in text:
        marker = '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
        if marker not in text:
            raise SystemExit('V55: Android manifest marker missing')
        text = text.replace(marker, marker + f'    <uses-permission android:name="{permission}" />\n', 1)
        manifest.write_text(text, encoding='utf-8')

print('Vet AI V55 applied: farm profile photos, WhatsApp rich attachments, smaller send control, P2P-first WebRTC')

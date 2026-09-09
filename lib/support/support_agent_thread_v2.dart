import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n/vet_locale.dart';
import '../services/vet_backend.dart';
import '../theme/app_theme.dart';
import 'support_call_service.dart';

String _wt(BuildContext context, String en, String ar, String nl) =>
    VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

const _waGreen = Color(0xFF00A884);
const _waOutgoing = Color(0xFFD9FDD3);
const _waIncoming = Color(0xFFFFFFFF);
const _waChatBackground = Color(0xFFEFEAE2);
const _waChrome = Color(0xFFF0F2F5);
const _waMuted = Color(0xFF667781);

class VetSupportAgentThreadV2 extends StatefulWidget {
  const VetSupportAgentThreadV2({super.key, required this.thread});
  final Map<String, dynamic> thread;

  @override
  State<VetSupportAgentThreadV2> createState() =>
      _VetSupportAgentThreadV2State();
}

class _VetSupportAgentThreadV2State extends State<VetSupportAgentThreadV2> {
  final message = TextEditingController();
  final scroll = ScrollController();
  bool sending = false;
  int lastCount = -1;
  bool firstScroll = true;

  String get threadId => widget.thread['id'].toString();
  VetBackend get backend => VetBackend.instance;
  VetSupportCallService get calls => VetSupportCallService.instance;

  @override
  void dispose() {
    message.dispose();
    scroll.dispose();
    super.dispose();
  }

  DateTime _time(Map<String, dynamic> row) =>
      DateTime.tryParse('${row['created_at'] ?? ''}')?.toLocal() ??
      DateTime.fromMillisecondsSinceEpoch(0);

  void _toBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.hasClients) return;
      final target = scroll.position.maxScrollExtent;
      if (animated) {
        scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      } else {
        scroll.jumpTo(target);
      }
    });
  }

  Future<void> _send() async {
    final clean = message.text.trim();
    if (clean.isEmpty || sending) return;
    setState(() => sending = true);
    message.clear();
    try {
      await backend.sendSupportAgentMessage(threadId, clean);
      _toBottom();
    } catch (_) {
      if (mounted) {
        message.text = clean;
        message.selection = TextSelection.collapsed(offset: clean.length);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _wt(
                context,
                'Message could not be sent.',
                'الرسالة مااتبعتتش.',
                'Bericht kon niet worden verzonden.',
              ),
            ),
            backgroundColor: VetColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _sendFile() async {
    if (sending) return;
    final f = await FilePicker.pickFile();
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (bytes.length > 25 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _wt(
                context,
                'Maximum attachment size is 25 MB.',
                'أقصى حجم للمرفق 25 ميجابايت.',
                'Maximale bijlagegrootte is 25 MB.',
              ),
            ),
          ),
        );
      }
      return;
    }
    setState(() => sending = true);
    try {
      final uploaded = await backend.uploadSupportAttachment(
        threadId: threadId,
        bytes: bytes,
        fileName: f.name,
        mimeType: _mime(f.name),
      );
      final user = backend.currentUser;
      if (user == null) throw StateError('Support login required');
      await backend.client.from('support_messages').insert({
        'thread_id': threadId,
        'sender_id': user.id,
        'sender_role': 'support',
        'message': message.text.trim().isEmpty ? null : message.text.trim(),
        'attachment_path': uploaded['path'],
        'attachment_name': uploaded['name'],
        'attachment_mime': uploaded['mime'],
        'attachment_size_bytes': uploaded['size'],
      });
      message.clear();
      await backend.client.from('support_threads').update({
        'status': 'open',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', threadId);
      _toBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_wt(context, 'Attachment could not be sent.', 'المرفق مااتبعتش.', 'Bijlage kon niet worden verzonden.')} $e',
            ),
            backgroundColor: VetColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  String _mime(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      'pdf' => 'application/pdf',
      'doc' => 'application/msword',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'csv' => 'text/csv',
      'txt' => 'text/plain',
      _ => 'application/octet-stream',
    };
  }

  Future<void> _openAttachment(Map<String, dynamic> row) async {
    final path = row['attachment_path']?.toString() ?? '';
    if (path.isEmpty) return;
    final url = await backend.signedSupportAttachmentUrl(path);
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _startCall(String type) async {
    try {
      final call = await calls.startCall(
        threadId: threadId,
        callerRole: 'support',
        callType: type,
      );
      await calls.openMediaRoom(call);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_wt(context, 'Call could not start.', 'المكالمة ما بدأتش.', 'Oproep kon niet starten.')} $e',
            ),
            backgroundColor: VetColors.red,
          ),
        );
      }
    }
  }

  Future<void> _join(Map<String, dynamic> call) async {
    try {
      await calls.accept(call['id'].toString());
      await calls.openMediaRoom(call);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: VetColors.red),
        );
      }
    }
  }

  Future<void> _closeThread() async {
    await backend.setSupportThreadStatus(threadId, 'closed');
    if (mounted) Navigator.pop(context);
  }

  Future<void> _messageOptions(Map<String, dynamic> row) async {
    final text = '${row['message'] ?? ''}'.trim();
    final hasAttachment = '${row['attachment_path'] ?? ''}'.isNotEmpty;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (text.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: Text(_wt(context, 'Copy', 'نسخ', 'Kopiëren')),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
              ),
            if (hasAttachment)
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded),
                title: Text(
                  _wt(
                    context,
                    'Open attachment',
                    'فتح المرفق',
                    'Bijlage openen',
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openAttachment(row);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final farm = widget.thread['farms'] is Map
        ? Map<String, dynamic>.from(widget.thread['farms'] as Map)
        : <String, dynamic>{};
    final title =
        '${farm['company_name'] ?? farm['farm_name'] ?? _wt(context, 'Customer', 'العميل', 'Klant')}';

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: _waChatBackground,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: _waChrome,
        foregroundColor: const Color(0xFF111B21),
        titleSpacing: 0,
        title: Row(
          children: [
            const CircleAvatar(
              radius: 18,
              backgroundColor: Color(0xFFD9FDD3),
              child: Icon(Icons.person_rounded, color: _waGreen),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _wt(context, 'Customer support', 'دعم العميل', 'Klantensupport'),
                    style: const TextStyle(fontSize: 11.5, color: _waMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _wt(context, 'Video call', 'مكالمة فيديو', 'Videogesprek'),
            onPressed: () => _startCall('video'),
            icon: const Icon(Icons.videocam_outlined),
          ),
          IconButton(
            tooltip: _wt(context, 'Voice call', 'مكالمة صوتية', 'Spraakoproep'),
            onPressed: () => _startCall('voice'),
            icon: const Icon(Icons.call_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'close') _closeThread();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'close',
                child: Text(
                  _wt(
                    context,
                    'Close conversation',
                    'إغلاق المحادثة',
                    'Gesprek sluiten',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: calls.callsStream(threadId),
            builder: (context, snap) {
              final active = (snap.data ?? const <Map<String, dynamic>>[])
                  .where((call) => call['status'] == 'ringing')
                  .toList();
              if (active.isEmpty) return const SizedBox.shrink();
              final call = active.first;
              final incoming = call['caller_role'] != 'support';
              if (!incoming) {
                return Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  color: const Color(0xFFD9FDD3),
                  child: Row(
                    children: [
                      const Icon(Icons.call_rounded, color: _waGreen),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _wt(
                            context,
                            'Calling customer…',
                            'جاري الاتصال بالعميل…',
                            'Klant wordt gebeld…',
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton(
                        onPressed: () => calls.end(call['id'].toString()),
                        child: Text(_wt(context, 'End', 'إنهاء', 'Stop')),
                      ),
                    ],
                  ),
                );
              }
              return Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: const Color(0xFFD9FDD3),
                child: Row(
                  children: [
                    Icon(
                      call['call_type'] == 'video'
                          ? Icons.video_call_rounded
                          : Icons.call_rounded,
                      color: _waGreen,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        call['call_type'] == 'video'
                            ? _wt(
                                context,
                                'Incoming video call',
                                'مكالمة فيديو واردة',
                                'Inkomend videogesprek',
                              )
                            : _wt(
                                context,
                                'Incoming voice call',
                                'مكالمة صوتية واردة',
                                'Inkomende spraakoproep',
                              ),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    TextButton(
                      onPressed: () => calls.decline(call['id'].toString()),
                      child: Text(_wt(context, 'Decline', 'رفض', 'Weigeren')),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: _waGreen),
                      onPressed: () => _join(call),
                      icon: const Icon(Icons.call_rounded),
                      label: Text(_wt(context, 'Answer', 'رد', 'Opnemen')),
                    ),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: Container(
              color: _waChatBackground,
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: backend.supportAgentMessagesStream(threadId),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final seen = <String>{};
                  final rows = snapshot.data!
                      .where((row) => seen.add('${row['id']}'))
                      .toList(growable: true)
                    ..sort((a, b) => _time(a).compareTo(_time(b)));
                  if (rows.length != lastCount) {
                    lastCount = rows.length;
                    _toBottom(animated: !firstScroll);
                    firstScroll = false;
                  }
                  if (rows.isEmpty) {
                    return Center(
                      child: Container(
                        margin: const EdgeInsets.all(24),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF5C4),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          _wt(
                            context,
                            'No messages yet. Start the conversation below.',
                            'مفيش رسائل لسه. ابدأ المحادثة من تحت.',
                            'Nog geen berichten. Start hieronder het gesprek.',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: _waMuted,
                          ),
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    controller: scroll,
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: ClampingScrollPhysics(),
                    ),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final day = DateUtils.dateOnly(_time(row));
                      final previousDay = index == 0
                          ? null
                          : DateUtils.dateOnly(_time(rows[index - 1]));
                      return Column(
                        children: [
                          if (previousDay == null || day != previousDay)
                            _DayChip(date: day),
                          _MessageBubble(
                            row: row,
                            mine: row['sender_role'] == 'support',
                            onAttachment: () => _openAttachment(row),
                            onLongPress: () => _messageOptions(row),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              color: _waChrome,
              padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: _wt(context, 'Attach', 'إرفاق', 'Bijvoegen'),
                    onPressed: sending ? null : _sendFile,
                    icon: const Icon(Icons.add_rounded, size: 28),
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: message,
                        minLines: 1,
                        maxLines: 6,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.newline,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          hintText: _wt(context, 'Message', 'رسالة', 'Bericht'),
                          hintStyle: const TextStyle(color: _waMuted),
                          contentPadding:
                              const EdgeInsets.fromLTRB(16, 11, 12, 11),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: _waGreen,
                    child: IconButton(
                      onPressed: sending ? null : _send,
                      icon: sending
                          ? const SizedBox.square(
                              dimension: 19,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.send_rounded,
                              color: Colors.white,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));
    final text = date == today
        ? _wt(context, 'Today', 'اليوم', 'Vandaag')
        : date == yesterday
            ? _wt(context, 'Yesterday', 'أمس', 'Gisteren')
            : DateFormat.yMMMd(
                Localizations.localeOf(context).toLanguageTag(),
              ).format(date);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF).withValues(alpha: .92),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .05),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: _waMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.row,
    required this.mine,
    required this.onAttachment,
    required this.onLongPress,
  });

  final Map<String, dynamic> row;
  final bool mine;
  final VoidCallback onAttachment;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final time = DateTime.tryParse('${row['created_at'] ?? ''}')?.toLocal();
    final hasAttachment = '${row['attachment_path'] ?? ''}'.isNotEmpty;
    final text = '${row['message'] ?? ''}'.trim();
    final width = MediaQuery.sizeOf(context).width;

    return Align(
      alignment:
          mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: const EdgeInsets.only(bottom: 3),
          constraints: BoxConstraints(
            maxWidth: width > 900 ? 560 : width * .78,
          ),
          padding: const EdgeInsets.fromLTRB(9, 7, 8, 5),
          decoration: BoxDecoration(
            color: mine ? _waOutgoing : _waIncoming,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(8),
              topRight: const Radius.circular(8),
              bottomLeft: Radius.circular(mine ? 8 : 2),
              bottomRight: Radius.circular(mine ? 2 : 8),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .08),
                blurRadius: 1.5,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasAttachment)
                _AttachmentPreview(row: row, onOpen: onAttachment),
              if (hasAttachment && text.isNotEmpty) const SizedBox(height: 5),
              if (text.isNotEmpty)
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 15.5,
                    height: 1.28,
                    color: Color(0xFF111B21),
                  ),
                ),
              const SizedBox(height: 2),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      time == null ? '' : DateFormat.Hm().format(time),
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: _waMuted,
                      ),
                    ),
                    if (mine) ...[
                      const SizedBox(width: 3),
                      const Icon(
                        Icons.done_all_rounded,
                        size: 15,
                        color: Color(0xFF53BDEB),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentPreview extends StatefulWidget {
  const _AttachmentPreview({required this.row, required this.onOpen});
  final Map<String, dynamic> row;
  final VoidCallback onOpen;

  @override
  State<_AttachmentPreview> createState() => _AttachmentPreviewState();
}

class _AttachmentPreviewState extends State<_AttachmentPreview> {
  late Future<String> urlFuture;

  @override
  void initState() {
    super.initState();
    final path = widget.row['attachment_path']?.toString() ?? '';
    urlFuture = VetBackend.instance.signedSupportAttachmentUrl(path);
  }

  @override
  Widget build(BuildContext context) {
    final mime = '${widget.row['attachment_mime'] ?? ''}'.toLowerCase();
    final name = '${widget.row['attachment_name'] ?? _wt(context, 'Attachment', 'مرفق', 'Bijlage')}';
    final image = mime.startsWith('image/');

    if (image) {
      return InkWell(
        onTap: widget.onOpen,
        borderRadius: BorderRadius.circular(7),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: FutureBuilder<String>(
            future: urlFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return Container(
                  width: 280,
                  height: 180,
                  color: const Color(0xFFE9EDEF),
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                );
              }
              return Image.network(
                snapshot.data!,
                width: 310,
                height: 220,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 280,
                  height: 140,
                  color: const Color(0xFFE9EDEF),
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_outlined, size: 34),
                ),
              );
            },
          ),
        ),
      );
    }

    return InkWell(
      onTap: widget.onOpen,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFE9EDEF),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file_rounded, size: 28),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

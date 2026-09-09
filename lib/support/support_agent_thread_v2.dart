import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n/vet_locale.dart';
import '../services/vet_backend.dart';
import '../services/vet_operations.dart';
import '../theme/app_theme.dart';
import 'support_call_service.dart';

String _wt(BuildContext context, String en, String ar, String nl) => VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

class VetSupportAgentThreadV2 extends StatefulWidget {
  const VetSupportAgentThreadV2({super.key, required this.thread});
  final Map<String, dynamic> thread;

  @override
  State<VetSupportAgentThreadV2> createState() => _VetSupportAgentThreadV2State();
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

  void _toBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.hasClients) return;
      final target = scroll.position.maxScrollExtent;
      if (animated) {
        scroll.animateTo(target, duration: const Duration(milliseconds: 230), curve: Curves.easeOut);
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_wt(context, 'Message could not be sent.', 'الرسالة مااتبعتتش.', 'Bericht kon niet worden verzonden.')), backgroundColor: VetColors.red));
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _sendFile() async {
    if (sending) return;
    final picked = await FilePicker.platform.pickFiles(withData: true, allowMultiple: false);
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.single;
    final bytes = f.bytes;
    if (bytes == null) return;
    if (bytes.length > 25 * 1024 * 1024) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_wt(context, 'Maximum attachment size is 25 MB.', 'أقصى حجم للمرفق 25 ميجابايت.', 'Maximale bijlagegrootte is 25 MB.'))));
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
      await backend.client.from('support_threads').update({'status': 'open', 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', threadId);
      _toBottom();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_wt(context, 'Attachment could not be sent.', 'المرفق مااتبعتش.', 'Bijlage kon niet worden verzonden.')} $e'), backgroundColor: VetColors.red));
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
      'pdf' => 'application/pdf',
      'doc' => 'application/msword',
      'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'csv' => 'text/csv',
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
      final call = await calls.startCall(threadId: threadId, callerRole: 'support', callType: type);
      await calls.openMediaRoom(call);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_wt(context, 'Call could not start.', 'المكالمة ما بدأتش.', 'Oproep kon niet starten.')} $e'), backgroundColor: VetColors.red));
    }
  }

  Future<void> _join(Map<String, dynamic> call) async {
    try {
      await calls.accept(call['id'].toString());
      await calls.openMediaRoom(call);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: VetColors.red));
    }
  }

  Future<void> _closeThread() async {
    await backend.setSupportThreadStatus(threadId, 'closed');
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final farm = widget.thread['farms'] is Map ? Map<String, dynamic>.from(widget.thread['farms'] as Map) : <String, dynamic>{};
    final title = '${farm['company_name'] ?? farm['farm_name'] ?? _wt(context, 'Customer', 'العميل', 'Klant')}';
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        titleSpacing: 4,
        title: Row(children: [
          const CircleAvatar(radius: 18, backgroundColor: VetColors.softGreen, child: Icon(Icons.person_rounded, color: VetColors.green)),
          const SizedBox(width: 9),
          Expanded(child: Text(title, overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          IconButton(tooltip: _wt(context, 'Video call', 'مكالمة فيديو', 'Videogesprek'), onPressed: () => _startCall('video'), icon: const Icon(Icons.videocam_rounded)),
          IconButton(tooltip: _wt(context, 'Voice call', 'مكالمة صوتية', 'Spraakoproep'), onPressed: () => _startCall('voice'), icon: const Icon(Icons.call_rounded)),
          PopupMenuButton<String>(
            onSelected: (v) { if (v == 'close') _closeThread(); },
            itemBuilder: (_) => [PopupMenuItem(value: 'close', child: Text(_wt(context, 'Close conversation', 'إغلاق المحادثة', 'Gesprek sluiten')))],
          ),
        ],
      ),
      body: Column(children: [
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: calls.callsStream(threadId),
          builder: (context, snap) {
            final active = (snap.data ?? const <Map<String, dynamic>>[]).where((c) => c['status'] == 'ringing').toList();
            if (active.isEmpty) return const SizedBox.shrink();
            final call = active.first;
            final incoming = call['caller_role'] != 'support';
            if (!incoming) {
              return Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), color: VetColors.softGreen, child: Row(children: [const Icon(Icons.call_rounded, color: VetColors.green), const SizedBox(width: 8), Expanded(child: Text(_wt(context, 'Calling customer…', 'جاري الاتصال بالعميل…', 'Klant wordt gebeld…'), style: const TextStyle(fontWeight: FontWeight.w800))), TextButton(onPressed: () => calls.end(call['id'].toString()), child: Text(_wt(context, 'End', 'إنهاء', 'Stop')))]));
            }
            return Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), color: VetColors.softGreen, child: Row(children: [
              Icon(call['call_type'] == 'video' ? Icons.video_call_rounded : Icons.call_rounded, color: VetColors.green),
              const SizedBox(width: 8),
              Expanded(child: Text(call['call_type'] == 'video' ? _wt(context, 'Incoming video call', 'مكالمة فيديو واردة', 'Inkomend videogesprek') : _wt(context, 'Incoming voice call', 'مكالمة صوتية واردة', 'Inkomende spraakoproep'), style: const TextStyle(fontWeight: FontWeight.w900))),
              TextButton(onPressed: () => calls.decline(call['id'].toString()), child: Text(_wt(context, 'Decline', 'رفض', 'Weigeren'))),
              FilledButton.icon(onPressed: () => _join(call), icon: const Icon(Icons.call_rounded), label: Text(_wt(context, 'Answer', 'رد', 'Opnemen'))),
            ]));
          },
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: backend.supportAgentMessagesStream(threadId),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final seen = <String>{};
              final rows = snapshot.data!.where((r) => seen.add('${r['id']}')).toList();
              rows.sort((a, b) => _time(a).compareTo(_time(b)));
              if (rows.length != lastCount) {
                lastCount = rows.length;
                _toBottom(animated: !firstScroll);
                firstScroll = false;
              }
              return ListView.builder(
                controller: scroll,
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final row = rows[i];
                  final day = DateUtils.dateOnly(_time(row));
                  final previousDay = i == 0 ? null : DateUtils.dateOnly(_time(rows[i - 1]));
                  return Column(children: [
                    if (previousDay == null || day != previousDay) _DayChip(date: day),
                    _MessageBubble(row: row, mine: row['sender_role'] == 'support', onAttachment: () => _openAttachment(row)),
                  ]);
                },
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 10),
            decoration: const BoxDecoration(color: VetColors.surface, border: Border(top: BorderSide(color: VetColors.border))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              IconButton(onPressed: sending ? null : _sendFile, icon: const Icon(Icons.add_circle_outline_rounded)),
              Expanded(child: TextField(
                controller: message,
                minLines: 1,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(hintText: _wt(context, 'Message', 'رسالة', 'Bericht'), prefixIcon: const Icon(Icons.emoji_emotions_outlined)),
              )),
              const SizedBox(width: 7),
              CircleAvatar(
                radius: 25,
                backgroundColor: VetColors.green,
                child: IconButton(onPressed: sending ? null : _send, icon: sending ? const SizedBox.square(dimension: 19, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded, color: Colors.white)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  DateTime _time(Map<String, dynamic> row) => DateTime.tryParse('${row['created_at'] ?? ''}')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.date});
  final DateTime date;
  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));
    final text = date == today ? _wt(context, 'Today', 'اليوم', 'Vandaag') : date == yesterday ? _wt(context, 'Yesterday', 'أمس', 'Gisteren') : DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag()).format(date);
    return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5), decoration: BoxDecoration(color: VetColors.surface2, borderRadius: BorderRadius.circular(10), border: Border.all(color: VetColors.border)), child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)))));
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.row, required this.mine, required this.onAttachment});
  final Map<String, dynamic> row;
  final bool mine;
  final VoidCallback onAttachment;

  @override
  Widget build(BuildContext context) {
    final time = DateTime.tryParse('${row['created_at'] ?? ''}')?.toLocal();
    final hasAttachment = '${row['attachment_path'] ?? ''}'.isNotEmpty;
    final text = '${row['message'] ?? ''}'.trim();
    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width > 700 ? 520 : MediaQuery.sizeOf(context).width * .78),
        padding: const EdgeInsets.fromLTRB(11, 8, 9, 6),
        decoration: BoxDecoration(
          color: mine ? VetColors.softGreen : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(15), topRight: const Radius.circular(15),
            bottomLeft: Radius.circular(mine ? 15 : 4), bottomRight: Radius.circular(mine ? 4 : 15),
          ),
          border: Border.all(color: mine ? VetColors.green.withValues(alpha: .25) : VetColors.border),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .035), blurRadius: 4, offset: const Offset(0, 1))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (text.isNotEmpty) Text(text, style: const TextStyle(fontSize: 15.5, height: 1.32)),
          if (hasAttachment) ...[
            if (text.isNotEmpty) const SizedBox(height: 6),
            InkWell(onTap: onAttachment, borderRadius: BorderRadius.circular(10), child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: VetColors.surface2, borderRadius: BorderRadius.circular(10)), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.attach_file_rounded, size: 19), const SizedBox(width: 6), Flexible(child: Text('${row['attachment_name'] ?? _wt(context, 'Attachment', 'مرفق', 'Bijlage')}', overflow: TextOverflow.ellipsis))]))),
          ],
          const SizedBox(height: 3),
          Align(alignment: AlignmentDirectional.centerEnd, child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(time == null ? '' : DateFormat.Hm().format(time), style: const TextStyle(fontSize: 10.5, color: VetColors.muted)),
            if (mine) ...[const SizedBox(width: 3), const Icon(Icons.done_all_rounded, size: 15, color: VetColors.green)],
          ])),
        ]),
      ),
    );
  }
}

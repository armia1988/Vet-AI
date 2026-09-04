import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n/vet_locale.dart';
import '../services/vet_backend.dart';
import '../services/vet_operations.dart';
import '../theme/app_theme.dart';

String _ct(BuildContext context, String en, String ar, String nl) => VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

class VetSupportConsoleScreen extends StatefulWidget {
  const VetSupportConsoleScreen({super.key});

  @override
  State<VetSupportConsoleScreen> createState() => _VetSupportConsoleScreenState();
}

class _VetSupportConsoleScreenState extends State<VetSupportConsoleScreen> {
  late Future<bool> allowed;
  late Future<List<Map<String, dynamic>>> threads;

  @override
  void initState() {
    super.initState();
    allowed = VetBackend.instance.isSupportAgent();
    threads = VetBackend.instance.supportAgentThreads();
  }

  Future<void> refresh() async {
    setState(() => threads = VetBackend.instance.supportAgentThreads());
    await threads;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_ct(context, 'Vet AI company support', 'دعم شركة Vet AI', 'Vet AI bedrijfsupport'))),
        body: FutureBuilder<bool>(
          future: allowed,
          builder: (context, permission) {
            if (!permission.hasData) return const Center(child: CircularProgressIndicator());
            if (permission.data != true) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.admin_panel_settings_outlined, size: 68, color: VetColors.red),
                    const SizedBox(height: 14),
                    Text(_ct(context, 'Company support authorization required', 'لازم تصريح حساب دعم الشركة', 'Bedrijfssupportautorisatie vereist'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Text(_ct(context, 'Only accounts explicitly approved as Vet AI support agents can see customer support threads. Farm users cannot browse other customers.', 'فقط الحسابات المصرح لها صراحة كموظفي دعم Vet AI تقدر تشوف محادثات العملاء. حساب المزرعة العادي ما يقدرش يشوف عملاء تانيين.', 'Alleen expliciet goedgekeurde Vet AI-supportaccounts kunnen klantgesprekken zien. Gewone boerderijaccounts kunnen geen andere klanten bekijken.'), textAlign: TextAlign.center, style: const TextStyle(color: VetColors.muted, height: 1.5)),
                  ]),
                ),
              );
            }
            return FutureBuilder<List<Map<String, dynamic>>>(
              future: threads,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final rows = snapshot.data!;
                return RefreshIndicator(
                  onRefresh: refresh,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: VetColors.softGreen, borderRadius: BorderRadius.circular(16), border: Border.all(color: VetColors.green.withValues(alpha: .3))),
                        child: Row(children: [
                          const Icon(Icons.verified_user_outlined, color: VetColors.green, size: 30),
                          const SizedBox(width: 10),
                          Expanded(child: Text(_ct(context, 'Authorized company console • customer threads update from the protected support database.', 'كونسول شركة مصرح • محادثات العملاء جاية من قاعدة الدعم المحمية.', 'Geautoriseerde bedrijfsconsole • klantgesprekken komen uit de beveiligde supportdatabase.'), style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4))),
                        ]),
                      ),
                      const SizedBox(height: 15),
                      if (rows.isEmpty)
                        Card(child: Padding(padding: const EdgeInsets.all(22), child: Column(children: [
                          const Icon(Icons.inbox_outlined, size: 52, color: VetColors.muted),
                          const SizedBox(height: 10),
                          Text(_ct(context, 'No customer support threads yet', 'لسه مفيش محادثات دعم عملاء', 'Nog geen klantsupportgesprekken'), style: const TextStyle(fontWeight: FontWeight.w900)),
                        ]))),
                      for (final row in rows) _ThreadTile(row: row),
                    ],
                  ),
                );
              },
            );
          },
        ),
      );
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({required this.row});
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final farm = row['farms'] is Map ? Map<String, dynamic>.from(row['farms'] as Map) : <String, dynamic>{};
    final farmName = (farm['farm_name'] ?? farm['company_name'] ?? row['farm_id'] ?? '').toString();
    final status = row['status']?.toString() ?? 'open';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        leading: CircleAvatar(
          backgroundColor: status == 'closed' ? VetColors.surface3 : VetColors.softGreen,
          child: Icon(status == 'closed' ? Icons.check_circle_outline_rounded : Icons.chat_bubble_outline_rounded, color: status == 'closed' ? VetColors.muted : VetColors.green),
        ),
        title: Text(farmName.isEmpty ? _ct(context, 'Customer thread', 'محادثة عميل', 'Klantgesprek') : farmName, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text('${row['subject'] ?? ''}\n$status', maxLines: 2),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VetSupportAgentThreadScreen(thread: row))),
      ),
    );
  }
}

class VetSupportAgentThreadScreen extends StatefulWidget {
  const VetSupportAgentThreadScreen({super.key, required this.thread});
  final Map<String, dynamic> thread;

  @override
  State<VetSupportAgentThreadScreen> createState() => _VetSupportAgentThreadScreenState();
}

class _VetSupportAgentThreadScreenState extends State<VetSupportAgentThreadScreen> {
  final message = TextEditingController();
  bool sending = false;

  String get threadId => widget.thread['id'].toString();

  @override
  void dispose() {
    message.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final clean = message.text.trim();
    if (clean.isEmpty || sending) return;
    setState(() => sending = true);
    try {
      await VetBackend.instance.sendSupportAgentMessage(threadId, clean);
      message.clear();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_ct(context, 'Reply could not be sent.', 'الرد مااتبعتش.', 'Antwoord kon niet worden verzonden.')), backgroundColor: VetColors.red));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> closeThread() async {
    await VetBackend.instance.setSupportThreadStatus(threadId, 'closed');
    if (mounted) Navigator.pop(context);
  }

  Future<void> openAttachment(Map<String, dynamic> row) async {
    final path = row['attachment_path']?.toString();
    if (path == null || path.isEmpty) return;
    try {
      final url = await VetBackend.instance.signedSupportAttachmentUrl(path);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_ct(context, 'Attachment could not be opened.', 'المرفق مااتفتحش.', 'Bijlage kon niet worden geopend.'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final farm = widget.thread['farms'] is Map ? Map<String, dynamic>.from(widget.thread['farms'] as Map) : <String, dynamic>{};
    final title = (farm['farm_name'] ?? farm['company_name'] ?? _ct(context, 'Customer', 'العميل', 'Klant')).toString();
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [IconButton(tooltip: _ct(context, 'Close thread', 'إغلاق المحادثة', 'Gesprek sluiten'), onPressed: closeThread, icon: const Icon(Icons.task_alt_rounded))],
      ),
      body: Column(children: [
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: VetBackend.instance.supportAgentMessagesStream(threadId),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final rows = snapshot.data!;
              return ListView.builder(
                reverse: false,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final row = rows[i];
                  final support = row['sender_role'] == 'support';
                  final hasAttachment = (row['attachment_path']?.toString() ?? '').isNotEmpty;
                  return Align(
                    alignment: support ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 9),
                      constraints: const BoxConstraints(maxWidth: 340),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: support ? VetColors.softGreen : VetColors.surface2,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: support ? VetColors.green.withValues(alpha: .35) : VetColors.border),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if ((row['message']?.toString() ?? '').isNotEmpty) Text(row['message'].toString(), style: const TextStyle(height: 1.4)),
                        if (hasAttachment) ...[
                          if ((row['message']?.toString() ?? '').isNotEmpty) const SizedBox(height: 8),
                          OutlinedButton.icon(onPressed: () => openAttachment(row), icon: const Icon(Icons.attach_file_rounded), label: Text(row['attachment_name']?.toString() ?? _ct(context, 'Open attachment', 'فتح المرفق', 'Bijlage openen'))),
                        ],
                        const SizedBox(height: 5),
                        Text(support ? _ct(context, 'Vet AI Support', 'دعم Vet AI', 'Vet AI Support') : _ct(context, 'Customer', 'العميل', 'Klant'), style: const TextStyle(fontSize: 11, color: VetColors.muted, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Row(children: [
              Expanded(child: TextField(controller: message, minLines: 1, maxLines: 4, decoration: InputDecoration(hintText: _ct(context, 'Reply as Vet AI Support…', 'رد باسم دعم Vet AI…', 'Antwoord als Vet AI Support…')))),
              const SizedBox(width: 8),
              IconButton.filled(onPressed: sending ? null : send, icon: sending ? const SizedBox.square(dimension: 19, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded)),
            ]),
          ),
        ),
      ]),
    );
  }
}

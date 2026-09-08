import 'package:flutter/material.dart';

import '../i18n/vet_locale.dart';
import '../support/support_console.dart';
import '../theme/app_theme.dart';
import 'admin_service.dart';

String _sp(BuildContext context, String en, String ar, String nl) =>
    VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

class VetAdminSupportCenter extends StatefulWidget {
  const VetAdminSupportCenter({super.key});

  @override
  State<VetAdminSupportCenter> createState() => _VetAdminSupportCenterState();
}

class _VetAdminSupportCenterState extends State<VetAdminSupportCenter> {
  final admin = VetAdminService.instance;
  late Future<_SupportData> future = _load();
  String filter = 'all';
  String query = '';

  Future<_SupportData> _load() async {
    final values = await Future.wait([
      admin.supportThreads(),
      admin.farms(),
      admin.profiles(),
      admin.admins(),
    ]);
    return _SupportData(
      threads: values[0],
      farms: values[1],
      profiles: values[2],
      admins: values[3],
    );
  }

  void reload() => setState(() => future = _load());

  Future<void> _manage(Map<String, dynamic> thread, _SupportData data) async {
    String status = '${thread['status'] ?? 'open'}';
    String priority = '${thread['priority'] ?? 'normal'}';
    String? assignedTo = thread['assigned_to']?.toString();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(_sp(context, 'Manage support case', 'إدارة محادثة الدعم', 'Supportcase beheren')),
          content: SizedBox(
            width: 560,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: InputDecoration(labelText: _sp(context, 'Status', 'الحالة', 'Status')),
                items: [
                  DropdownMenuItem(value: 'open', child: Text(_sp(context, 'Open', 'مفتوح', 'Open'))),
                  DropdownMenuItem(value: 'pending', child: Text(_sp(context, 'Waiting', 'بانتظار', 'Wachtend'))),
                  DropdownMenuItem(value: 'closed', child: Text(_sp(context, 'Closed', 'مغلق', 'Gesloten'))),
                ],
                onChanged: (value) => setLocal(() => status = value ?? 'open'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: priority,
                decoration: InputDecoration(labelText: _sp(context, 'Priority', 'الأولوية', 'Prioriteit')),
                items: [
                  DropdownMenuItem(value: 'low', child: Text(_sp(context, 'Low', 'منخفضة', 'Laag'))),
                  DropdownMenuItem(value: 'normal', child: Text(_sp(context, 'Normal', 'عادية', 'Normaal'))),
                  DropdownMenuItem(value: 'high', child: Text(_sp(context, 'High', 'عالية', 'Hoog'))),
                  DropdownMenuItem(value: 'urgent', child: Text(_sp(context, 'Urgent', 'عاجلة', 'Urgent'))),
                ],
                onChanged: (value) => setLocal(() => priority = value ?? 'normal'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String?>(
                initialValue: assignedTo,
                decoration: InputDecoration(labelText: _sp(context, 'Assigned staff', 'الموظف المسؤول', 'Toegewezen medewerker')),
                items: [
                  DropdownMenuItem<String?>(value: null, child: Text(_sp(context, 'Unassigned', 'غير معيّن', 'Niet toegewezen'))),
                  for (final account in data.admins)
                    DropdownMenuItem<String?>(value: account['user_id'].toString(), child: Text('${data.profileNames[account['user_id'].toString()] ?? account['user_id']} • ${account['role']}')),
                ],
                onChanged: (value) => setLocal(() => assignedTo = value),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_sp(context, 'Cancel', 'إلغاء', 'Annuleren'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_sp(context, 'Save', 'حفظ', 'Opslaan'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await admin.updateSupportThread(thread['id'].toString(), {
      'status': status,
      'priority': priority,
      'assigned_to': assignedTo,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    reload();
  }

  Future<void> _openThread(Map<String, dynamic> thread, _SupportData data) async {
    await admin.markSupportRead(thread['id'].toString());
    if (!mounted) return;
    final enriched = Map<String, dynamic>.from(thread);
    enriched['farms'] = data.farmById[thread['farm_id'].toString()] ?? <String, dynamic>{};
    await Navigator.push(context, MaterialPageRoute(builder: (_) => VetSupportAgentThreadScreen(thread: enriched)));
    reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_SupportData>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('${snapshot.error}', style: const TextStyle(color: VetColors.red)));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!;
          final rows = data.threads.where((thread) {
            if (filter != 'all' && '${thread['status']}' != filter) return false;
            final farm = data.farmById[thread['farm_id'].toString()] ?? const <String, dynamic>{};
            final haystack = '${thread['subject'] ?? ''} ${farm['company_name'] ?? ''} ${farm['farm_name'] ?? ''}'.toLowerCase();
            return query.trim().isEmpty || haystack.contains(query.trim().toLowerCase());
          }).toList();
          final unread = data.threads.fold<int>(0, (sum, e) => sum + ((e['unread_by_admin'] as num?)?.toInt() ?? 0));
          final urgent = data.threads.where((e) => e['priority'] == 'urgent' && e['status'] != 'closed').length;

          return Column(children: [
            Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
              color: VetColors.surface2,
              child: Column(children: [
                Row(children: [
                  Expanded(child: TextField(onChanged: (value) => setState(() => query = value), decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: _sp(context, 'Search customer, farm or subject…', 'ابحث بالعميل أو المزرعة أو الموضوع…', 'Zoek klant, boerderij of onderwerp…')))),
                  const SizedBox(width: 10),
                  IconButton.filledTonal(onPressed: reload, icon: const Icon(Icons.refresh_rounded)),
                ]),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _FilterChip(label: _sp(context, 'All', 'الكل', 'Alle'), selected: filter == 'all', onTap: () => setState(() => filter = 'all')),
                  _FilterChip(label: _sp(context, 'Open', 'مفتوح', 'Open'), selected: filter == 'open', onTap: () => setState(() => filter = 'open')),
                  _FilterChip(label: _sp(context, 'Waiting', 'بانتظار', 'Wachtend'), selected: filter == 'pending', onTap: () => setState(() => filter = 'pending')),
                  _FilterChip(label: _sp(context, 'Closed', 'مغلق', 'Gesloten'), selected: filter == 'closed', onTap: () => setState(() => filter = 'closed')),
                  Chip(avatar: const Icon(Icons.mark_chat_unread_rounded, size: 17), label: Text('$unread ${_sp(context, 'unread', 'غير مقروء', 'ongelezen')}')),
                  Chip(avatar: const Icon(Icons.priority_high_rounded, size: 17, color: VetColors.red), label: Text('$urgent ${_sp(context, 'urgent', 'عاجل', 'urgent')}')),
                ]),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  for (final thread in rows)
                    _SupportThreadCard(
                      thread: thread,
                      farm: data.farmById[thread['farm_id'].toString()] ?? const <String, dynamic>{},
                      assignedName: thread['assigned_to'] == null ? '' : (data.profileNames[thread['assigned_to'].toString()] ?? ''),
                      onOpen: () => _openThread(thread, data),
                      onManage: () => _manage(thread, data),
                    ),
                  if (rows.isEmpty) Center(child: Padding(padding: const EdgeInsets.all(40), child: Text(_sp(context, 'No support conversations match this view.', 'لا توجد محادثات دعم مطابقة.', 'Geen supportgesprekken in deze weergave.')))),
                ],
              ),
            ),
          ]);
        },
      );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap());
}

class _SupportThreadCard extends StatelessWidget {
  const _SupportThreadCard({required this.thread, required this.farm, required this.assignedName, required this.onOpen, required this.onManage});
  final Map<String, dynamic> thread;
  final Map<String, dynamic> farm;
  final String assignedName;
  final VoidCallback onOpen;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final unread = (thread['unread_by_admin'] as num?)?.toInt() ?? 0;
    final priority = '${thread['priority'] ?? 'normal'}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onOpen,
        leading: Badge(
          isLabelVisible: unread > 0,
          label: Text('$unread'),
          child: CircleAvatar(
            backgroundColor: priority == 'urgent' ? VetColors.red.withValues(alpha: .12) : VetColors.softGreen,
            child: Icon(Icons.chat_bubble_rounded, color: priority == 'urgent' ? VetColors.red : VetColors.green),
          ),
        ),
        title: Text('${farm['company_name'] ?? ''} / ${farm['farm_name'] ?? thread['farm_id']}', style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text('${thread['subject'] ?? ''}\n${thread['status']} • $priority${assignedName.trim().isEmpty ? '' : ' • $assignedName'} • ${thread['last_message_at'] ?? thread['updated_at'] ?? ''}'),
        isThreeLine: true,
        trailing: IconButton(onPressed: onManage, icon: const Icon(Icons.manage_accounts_rounded)),
      ),
    );
  }
}

class _SupportData {
  const _SupportData({required this.threads, required this.farms, required this.profiles, required this.admins});
  final List<Map<String, dynamic>> threads;
  final List<Map<String, dynamic>> farms;
  final List<Map<String, dynamic>> profiles;
  final List<Map<String, dynamic>> admins;
  Map<String, Map<String, dynamic>> get farmById => {for (final f in farms) f['id'].toString(): f};
  Map<String, String> get profileNames => {for (final p in profiles) p['id'].toString(): '${p['full_name'] ?? ''}'};
}

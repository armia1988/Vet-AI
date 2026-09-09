import 'dart:convert';

import 'package:flutter/material.dart';

import '../i18n/vet_locale.dart';
import '../theme/app_theme.dart';
import 'admin_service.dart';

String _adt(BuildContext context, String en, String ar, String nl) =>
    VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

class VetAdminAuditCenter extends StatefulWidget {
  const VetAdminAuditCenter({super.key});

  @override
  State<VetAdminAuditCenter> createState() => _VetAdminAuditCenterState();
}

class _VetAdminAuditCenterState extends State<VetAdminAuditCenter> {
  final admin = VetAdminService.instance;
  final search = TextEditingController();
  String action = 'all';
  String table = 'all';
  late Future<_AuditData> future = _load();

  Future<_AuditData> _load() async {
    final values = await Future.wait([admin.auditLog(), admin.profiles()]);
    return _AuditData(logs: values[0], profiles: values[1]);
  }

  void reload() => setState(() => future = _load());

  String pretty(dynamic value) {
    if (value == null) return '-';
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return '$value';
    }
  }

  void _open(Map<String, dynamic> row, Map<String, Map<String, dynamic>> profiles) {
    final actor = profiles[row['actor_user_id']?.toString()];
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${row['action']} • ${row['table_name']}'),
        content: SizedBox(
          width: 820,
          height: 600,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _line(_adt(context, 'Actor', 'الموظف', 'Actor'), '${actor?['full_name'] ?? row['actor_user_id'] ?? '-'}'),
              _line(_adt(context, 'Record ID', 'رقم السجل', 'Record-ID'), '${row['record_id'] ?? '-'}'),
              _line(_adt(context, 'Time', 'الوقت', 'Tijd'), '${row['created_at'] ?? '-'}'),
              const SizedBox(height: 14),
              Text(_adt(context, 'Before', 'قبل التعديل', 'Voor'), style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              _jsonBox(pretty(row['old_data'])),
              const SizedBox(height: 14),
              Text(_adt(context, 'After', 'بعد التعديل', 'Na'), style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              _jsonBox(pretty(row['new_data'])),
            ]),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(_adt(context, 'Close', 'إغلاق', 'Sluiten')))],
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(color: VetColors.muted, fontWeight: FontWeight.w700))),
          Expanded(child: SelectableText(value, style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
      );

  Widget _jsonBox(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: VetColors.surface3, borderRadius: BorderRadius.circular(12), border: Border.all(color: VetColors.border)),
        child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, height: 1.4)),
      );

  @override
  Widget build(BuildContext context) => FutureBuilder<_AuditData>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('${snapshot.error}', style: const TextStyle(color: VetColors.red)));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!;
          final profiles = {for (final p in data.profiles) p['id'].toString(): p};
          final tables = data.logs.map((e) => '${e['table_name']}').where((e) => e.isNotEmpty).toSet().toList()..sort();
          final needle = search.text.trim().toLowerCase();
          final rows = data.logs.where((row) {
            if (action != 'all' && '${row['action']}' != action) return false;
            if (table != 'all' && '${row['table_name']}' != table) return false;
            if (needle.isEmpty) return true;
            final actor = profiles[row['actor_user_id']?.toString()];
            final hay = '${row['action']} ${row['table_name']} ${row['record_id']} ${row['actor_user_id']} ${actor?['full_name']} ${row['old_data']} ${row['new_data']}'.toLowerCase();
            return hay.contains(needle);
          }).toList();

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(_adt(context, 'Administration audit trail', 'سجل عمليات الإدارة', 'Audittrail van beheer'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 5),
              Text(_adt(context, 'Every important change is recorded with the administrator, table, record, previous data and new data.', 'كل تغيير مهم يتم تسجيله مع اسم المسؤول والجدول والسجل والبيانات قبل وبعد التغيير.', 'Elke belangrijke wijziging wordt gelogd met beheerder, tabel, record en gegevens voor en na de wijziging.'), style: const TextStyle(color: VetColors.muted)),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Chip(avatar: const Icon(Icons.history_rounded, size: 17), label: Text('${data.logs.length} ${_adt(context, 'events', 'عملية', 'gebeurtenissen')}')),
                Chip(avatar: const Icon(Icons.edit_rounded, size: 17), label: Text('${data.logs.where((e) => e['action'] == 'UPDATE').length} UPDATE')),
                Chip(avatar: const Icon(Icons.add_circle_rounded, size: 17, color: VetColors.green), label: Text('${data.logs.where((e) => e['action'] == 'INSERT').length} INSERT')),
                Chip(avatar: const Icon(Icons.delete_rounded, size: 17, color: VetColors.red), label: Text('${data.logs.where((e) => e['action'] == 'DELETE').length} DELETE')),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 10, runSpacing: 10, children: [
                SizedBox(width: 420, child: TextField(controller: search, onChanged: (_) => setState(() {}), decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: _adt(context, 'Search actor, table, record or data', 'ابحث بالموظف أو الجدول أو السجل أو البيانات', 'Zoek actor, tabel, record of gegevens')))),
                SizedBox(width: 170, child: DropdownButtonFormField<String>(initialValue: action, decoration: InputDecoration(labelText: _adt(context, 'Action', 'العملية', 'Actie')), items: const [DropdownMenuItem(value: 'all', child: Text('All')), DropdownMenuItem(value: 'INSERT', child: Text('INSERT')), DropdownMenuItem(value: 'UPDATE', child: Text('UPDATE')), DropdownMenuItem(value: 'DELETE', child: Text('DELETE'))], onChanged: (v) => setState(() => action = v ?? 'all'))),
                SizedBox(width: 230, child: DropdownButtonFormField<String>(initialValue: table, decoration: InputDecoration(labelText: _adt(context, 'Table', 'الجدول', 'Tabel')), items: [DropdownMenuItem(value: 'all', child: Text(_adt(context, 'All tables', 'كل الجداول', 'Alle tabellen'))), for (final t in tables) DropdownMenuItem(value: t, child: Text(t))], onChanged: (v) => setState(() => table = v ?? 'all'))),
                IconButton.filledTonal(onPressed: reload, icon: const Icon(Icons.refresh_rounded)),
              ]),
              const SizedBox(height: 14),
              for (final row in rows)
                Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Icon(row['action'] == 'DELETE' ? Icons.delete_rounded : row['action'] == 'INSERT' ? Icons.add_rounded : Icons.edit_rounded, color: row['action'] == 'DELETE' ? VetColors.red : row['action'] == 'INSERT' ? VetColors.green : VetColors.blue)),
                    title: Text('${row['action']} • ${row['table_name']}', style: const TextStyle(fontWeight: FontWeight.w900)),
                    subtitle: Text('${profiles[row['actor_user_id']?.toString()]?['full_name'] ?? row['actor_user_id'] ?? '-'}\n${row['record_id'] ?? '-'} • ${row['created_at'] ?? '-'}'),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _open(row, profiles),
                  ),
                ),
              if (rows.isEmpty) Padding(padding: const EdgeInsets.all(38), child: Center(child: Text(_adt(context, 'No audit events match the filters.', 'لا توجد عمليات مطابقة للفلاتر.', 'Geen auditgebeurtenissen passen bij de filters.')))),
            ],
          );
        },
      );
}

class _AuditData {
  const _AuditData({required this.logs, required this.profiles});
  final List<Map<String, dynamic>> logs;
  final List<Map<String, dynamic>> profiles;
}

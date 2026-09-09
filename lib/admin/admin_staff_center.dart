import 'package:flutter/material.dart';

import '../i18n/vet_locale.dart';
import '../theme/app_theme.dart';
import 'admin_service.dart';

String _st(BuildContext context, String en, String ar, String nl) =>
    VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

class VetAdminStaffCenter extends StatefulWidget {
  const VetAdminStaffCenter({super.key});

  @override
  State<VetAdminStaffCenter> createState() => _VetAdminStaffCenterState();
}

class _VetAdminStaffCenterState extends State<VetAdminStaffCenter> {
  final admin = VetAdminService.instance;
  late Future<_StaffData> future = _load();

  static const permissions = <String>[
    'farms',
    'customers',
    'animals',
    'sensors',
    'alerts',
    'notifications',
    'support',
    'billing',
    'audit',
    'system',
    'manage_admins',
  ];

  Future<_StaffData> _load() async {
    final values = await Future.wait([admin.admins(), admin.profiles()]);
    return _StaffData(admins: values[0], profiles: values[1]);
  }

  void reload() => setState(() => future = _load());

  Future<void> _edit({Map<String, dynamic>? row, required _StaffData data}) async {
    String? userId = row?['user_id']?.toString();
    var role = '${row?['role'] ?? 'support'}';
    var active = row?['active'] == true || row == null;
    final current = row?['permissions'];
    final selected = <String, bool>{
      for (final p in permissions)
        p: current is Map && current[p] == true,
    };
    final existingIds = data.admins.map((e) => e['user_id'].toString()).toSet();
    final candidates = data.profiles.where((p) => row != null || !existingIds.contains(p['id'].toString())).toList();
    if (row != null && candidates.every((p) => p['id'].toString() != userId)) {
      final match = data.profiles.where((p) => p['id'].toString() == userId).toList();
      candidates.insertAll(0, match);
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(row == null
              ? _st(context, 'Add admin staff', 'إضافة موظف إدارة', 'Adminmedewerker toevoegen')
              : _st(context, 'Edit admin staff', 'تعديل موظف الإدارة', 'Adminmedewerker bewerken')),
          content: SizedBox(
            width: 690,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                DropdownButtonFormField<String>(
                  initialValue: userId,
                  decoration: InputDecoration(labelText: _st(context, 'User account', 'حساب المستخدم', 'Gebruikersaccount')),
                  items: [
                    for (final p in candidates)
                      DropdownMenuItem(value: p['id'].toString(), child: Text('${p['full_name'] ?? '-'} • ${p['phone'] ?? '-'}')),
                  ],
                  onChanged: row == null ? (v) => setLocal(() => userId = v) : null,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: InputDecoration(labelText: _st(context, 'Base role', 'الدور الأساسي', 'Basisrol')),
                  items: const [
                    DropdownMenuItem(value: 'super_admin', child: Text('Super Admin')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    DropdownMenuItem(value: 'operations', child: Text('Operations')),
                    DropdownMenuItem(value: 'support', child: Text('Support')),
                    DropdownMenuItem(value: 'billing', child: Text('Billing')),
                  ],
                  onChanged: (v) => setLocal(() => role = v ?? role),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: active,
                  onChanged: (v) => setLocal(() => active = v),
                  title: Text(_st(context, 'Admin access enabled', 'دخول الإدارة مفعّل', 'Admin-toegang ingeschakeld')),
                ),
                const Divider(height: 24),
                Text(_st(context, 'Extra permissions', 'صلاحيات إضافية', 'Extra rechten'), style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 5),
                Text(_st(context, 'The base role already grants its normal permissions. These switches can add explicit access.', 'الدور الأساسي يمنح صلاحياته المعتادة. هذه المفاتيح تضيف صلاحيات صريحة إضافية.', 'De basisrol geeft al normale rechten. Deze schakelaars voegen expliciete extra toegang toe.'), style: const TextStyle(color: VetColors.muted, fontSize: 12)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in permissions)
                      FilterChip(
                        selected: selected[p] == true,
                        label: Text(_permissionLabel(context, p)),
                        onSelected: (v) => setLocal(() => selected[p] = v),
                      ),
                  ],
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_st(context, 'Cancel', 'إلغاء', 'Annuleren'))),
            FilledButton(onPressed: userId == null ? null : () => Navigator.pop(dialogContext, true), child: Text(_st(context, 'Save access', 'حفظ الصلاحيات', 'Toegang opslaan'))),
          ],
        ),
      ),
    );
    if (ok != true || userId == null) return;
    await admin.client.rpc('admin_upsert_staff', params: {
      'p_user_id': userId,
      'p_role': role,
      'p_active': active,
      'p_permissions': {for (final e in selected.entries) if (e.value) e.key: true},
    });
    reload();
  }

  Future<void> _remove(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_st(context, 'Remove admin access?', 'إزالة صلاحية الإدارة؟', 'Admin-toegang verwijderen?')),
        content: Text(_st(context, 'This removes the account from the Vet AI administration team. It does not delete the customer/user account.', 'سيتم إزالة الحساب من فريق إدارة Vet AI فقط، ولن يتم حذف حساب المستخدم نفسه.', 'Dit verwijdert het account uit het Vet AI-beheerteam maar verwijdert het gebruikersaccount niet.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_st(context, 'Cancel', 'إلغاء', 'Annuleren'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_st(context, 'Remove', 'إزالة', 'Verwijderen'))),
        ],
      ),
    );
    if (ok != true) return;
    await admin.client.rpc('admin_remove_staff', params: {'p_user_id': row['user_id'].toString()});
    reload();
  }

  String _permissionLabel(BuildContext context, String p) => switch (p) {
        'farms' => _st(context, 'Companies & farms', 'الشركات والمزارع', 'Bedrijven & boerderijen'),
        'customers' => _st(context, 'Customers', 'العملاء', 'Klanten'),
        'animals' => _st(context, 'Animals', 'الحيوانات', 'Dieren'),
        'sensors' => _st(context, 'Sensors', 'الحساسات', 'Sensoren'),
        'alerts' => _st(context, 'Alerts', 'الإنذارات', 'Alarmen'),
        'notifications' => _st(context, 'Notifications', 'الإشعارات', 'Meldingen'),
        'support' => _st(context, 'Support', 'الدعم', 'Support'),
        'billing' => _st(context, 'Billing', 'الفوترة', 'Facturering'),
        'audit' => _st(context, 'Audit log', 'سجل العمليات', 'Auditlog'),
        'system' => _st(context, 'System controls', 'تحكم النظام', 'Systeembeheer'),
        'manage_admins' => _st(context, 'Manage admins', 'إدارة الموظفين', 'Admins beheren'),
        _ => p,
      };

  @override
  Widget build(BuildContext context) => FutureBuilder<_StaffData>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('${snapshot.error}', style: const TextStyle(color: VetColors.red)));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!;
          final profiles = {for (final p in data.profiles) p['id'].toString(): p};
          final activeCount = data.admins.where((e) => e['active'] == true).length;
          final superCount = data.admins.where((e) => e['role'] == 'super_admin' && e['active'] == true).length;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_st(context, 'Administration team & RBAC', 'فريق الإدارة والصلاحيات', 'Adminteam & RBAC'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(_st(context, 'Control exactly who can access companies, sensors, messages, billing and system settings.', 'تحكم بدقة في من يستطيع الوصول للشركات والحساسات والرسائل والفوترة وإعدادات النظام.', 'Bepaal exact wie toegang heeft tot bedrijven, sensoren, berichten, facturering en systeeminstellingen.'), style: const TextStyle(color: VetColors.muted)),
                ])),
                FilledButton.icon(onPressed: () => _edit(data: data), icon: const Icon(Icons.person_add_alt_1_rounded), label: Text(_st(context, 'Add staff', 'إضافة موظف', 'Medewerker toevoegen'))),
              ]),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Chip(avatar: const Icon(Icons.admin_panel_settings_rounded, size: 17), label: Text('${data.admins.length} ${_st(context, 'staff', 'موظف', 'medewerkers')}')),
                Chip(avatar: const Icon(Icons.check_circle_rounded, size: 17, color: VetColors.green), label: Text('$activeCount ${_st(context, 'active', 'نشط', 'actief')}')),
                Chip(avatar: const Icon(Icons.security_rounded, size: 17, color: VetColors.red), label: Text('$superCount Super Admin')),
              ]),
              const SizedBox(height: 14),
              for (final row in data.admins)
                Card(
                  child: ExpansionTile(
                    leading: CircleAvatar(child: Icon(row['active'] == true ? Icons.verified_user_rounded : Icons.person_off_rounded, color: row['active'] == true ? VetColors.green : VetColors.red)),
                    title: Text('${profiles[row['user_id'].toString()]?['full_name'] ?? row['user_id']}', style: const TextStyle(fontWeight: FontWeight.w900)),
                    subtitle: Text('${row['role']} • ${row['active'] == true ? _st(context, 'active', 'نشط', 'actief') : _st(context, 'disabled', 'موقوف', 'uitgeschakeld')}'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) => v == 'edit' ? _edit(row: row, data: data) : _remove(row),
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'edit', child: Text(_st(context, 'Edit permissions', 'تعديل الصلاحيات', 'Rechten bewerken'))),
                        PopupMenuItem(value: 'remove', child: Text(_st(context, 'Remove admin access', 'إزالة دخول الإدارة', 'Admin-toegang verwijderen'))),
                      ],
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                    children: [
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Wrap(spacing: 7, runSpacing: 7, children: [
                          for (final e in (row['permissions'] is Map ? Map<String, dynamic>.from(row['permissions'] as Map) : <String, dynamic>{}).entries)
                            if (e.value == true) Chip(label: Text(_permissionLabel(context, e.key))),
                          if (row['permissions'] is! Map || (row['permissions'] as Map).entries.where((e) => e.value == true).isEmpty)
                            Chip(label: Text(_st(context, 'Base-role permissions only', 'صلاحيات الدور الأساسي فقط', 'Alleen basisrolrechten'))),
                        ]),
                      ),
                      const SizedBox(height: 8),
                      Align(alignment: AlignmentDirectional.centerStart, child: Text('ID: ${row['user_id']}', style: const TextStyle(color: VetColors.muted, fontSize: 11))),
                    ],
                  ),
                ),
            ],
          );
        },
      );
}

class _StaffData {
  const _StaffData({required this.admins, required this.profiles});
  final List<Map<String, dynamic>> admins;
  final List<Map<String, dynamic>> profiles;
}

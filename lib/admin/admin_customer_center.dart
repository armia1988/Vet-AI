import 'package:flutter/material.dart';

import '../i18n/vet_locale.dart';
import '../theme/app_theme.dart';
import 'admin_service.dart';

String _ut(BuildContext context, String en, String ar, String nl) =>
    VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

class VetAdminCustomerCenter extends StatefulWidget {
  const VetAdminCustomerCenter({super.key});

  @override
  State<VetAdminCustomerCenter> createState() => _VetAdminCustomerCenterState();
}

class _VetAdminCustomerCenterState extends State<VetAdminCustomerCenter> {
  final admin = VetAdminService.instance;
  final search = TextEditingController();
  String status = 'all';
  late Future<_CustomerData> future = _load();

  Future<_CustomerData> _load() async {
    final values = await Future.wait([
      admin.profiles(),
      admin.farms(),
      admin.subscriptions(),
      admin.payments(),
      admin.pushDevices(),
      admin.supportThreads(),
    ]);
    return _CustomerData(
      profiles: values[0],
      farms: values[1],
      subscriptions: values[2],
      payments: values[3],
      devices: values[4],
      support: values[5],
    );
  }

  void reload() => setState(() => future = _load());

  Future<void> _edit(Map<String, dynamic> row) async {
    final name = TextEditingController(text: '${row['full_name'] ?? ''}');
    final phone = TextEditingController(text: '${row['phone'] ?? ''}');
    final job = TextEditingController(text: '${row['job_title'] ?? ''}');
    final language = TextEditingController(text: '${row['preferred_language'] ?? ''}');
    final notes = TextEditingController(text: '${row['admin_notes'] ?? ''}');
    final tags = TextEditingController(
      text: ((row['admin_tags'] as List?) ?? const []).join(', '),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_ut(context, 'Edit customer account', 'تعديل حساب العميل', 'Klantaccount bewerken')),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: InputDecoration(labelText: _ut(context, 'Full name', 'الاسم الكامل', 'Volledige naam'))),
              const SizedBox(height: 10),
              TextField(controller: phone, decoration: InputDecoration(labelText: _ut(context, 'Phone', 'الهاتف', 'Telefoon'))),
              const SizedBox(height: 10),
              TextField(controller: job, decoration: InputDecoration(labelText: _ut(context, 'Job title', 'الوظيفة', 'Functie'))),
              const SizedBox(height: 10),
              TextField(controller: language, decoration: InputDecoration(labelText: _ut(context, 'Preferred language code', 'كود اللغة المفضلة', 'Voorkeurstaalcode'))),
              const SizedBox(height: 10),
              TextField(controller: tags, decoration: InputDecoration(labelText: _ut(context, 'Admin tags', 'وسوم الإدارة', 'Adminlabels'), hintText: 'VIP, priority, reseller')),
              const SizedBox(height: 10),
              TextField(controller: notes, minLines: 3, maxLines: 7, decoration: InputDecoration(labelText: _ut(context, 'Private admin notes', 'ملاحظات إدارية خاصة', 'Privé-adminnotities'))),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_ut(context, 'Cancel', 'إلغاء', 'Annuleren'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_ut(context, 'Save', 'حفظ', 'Opslaan'))),
        ],
      ),
    );
    if (ok != true) return;
    await admin.updateProfile(row['id'].toString(), {
      'full_name': name.text.trim(),
      'phone': phone.text.trim(),
      'job_title': job.text.trim(),
      'preferred_language': language.text.trim(),
      'admin_notes': notes.text.trim(),
      'admin_tags': tags.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      'last_admin_review_at': DateTime.now().toUtc().toIso8601String(),
      'last_admin_reviewed_by': admin.client.auth.currentUser?.id,
    });
    reload();
  }

  Future<void> _setStatus(Map<String, dynamic> row, String next) async {
    final reason = TextEditingController(text: '${row['admin_notes'] ?? ''}');
    if (next != 'active') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(next == 'suspended'
              ? _ut(context, 'Suspend customer', 'إيقاف العميل', 'Klant opschorten')
              : _ut(context, 'Close customer account', 'إغلاق حساب العميل', 'Klantaccount sluiten')),
          content: SizedBox(
            width: 520,
            child: TextField(
              controller: reason,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(labelText: _ut(context, 'Reason / internal note', 'السبب / ملاحظة داخلية', 'Reden / interne notitie')),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_ut(context, 'Cancel', 'إلغاء', 'Annuleren'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_ut(context, 'Confirm', 'تأكيد', 'Bevestigen'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    await admin.client.rpc('admin_set_customer_status', params: {
      'p_user_id': row['id'].toString(),
      'p_status': next,
      'p_reason': reason.text.trim(),
    });
    reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_CustomerData>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('${snapshot.error}', style: const TextStyle(color: VetColors.red)));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!;
          final needle = search.text.trim().toLowerCase();
          final rows = data.profiles.where((row) {
            final rowStatus = '${row['account_status'] ?? 'active'}';
            if (status != 'all' && rowStatus != status) return false;
            if (needle.isEmpty) return true;
            final haystack = '${row['full_name']} ${row['phone']} ${row['job_title']} ${row['preferred_language']} ${row['id']}'.toLowerCase();
            return haystack.contains(needle);
          }).toList();
          final active = data.profiles.where((e) => '${e['account_status'] ?? 'active'}' == 'active').length;
          final suspended = data.profiles.where((e) => e['account_status'] == 'suspended').length;
          final closed = data.profiles.where((e) => e['account_status'] == 'closed').length;

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(_ut(context, 'Customer account operations', 'إدارة حسابات العملاء بالكامل', 'Klantaccountbeheer'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 5),
              Text(_ut(context, 'Search, edit, inspect company ownership, billing, support and push devices, or suspend access from the server.', 'بحث وتعديل ومراجعة الشركات والاشتراكات والمدفوعات والدعم والأجهزة أو إيقاف وصول العميل من السيرفر.', 'Zoek, bewerk en controleer bedrijven, facturering, support en pushapparaten of schort servertoegang op.'), style: const TextStyle(color: VetColors.muted)),
              const SizedBox(height: 15),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Chip(avatar: const Icon(Icons.people_alt_rounded, size: 17), label: Text('${data.profiles.length} ${_ut(context, 'customers', 'عميل', 'klanten')}')),
                Chip(avatar: const Icon(Icons.check_circle_rounded, size: 17, color: VetColors.green), label: Text('$active ${_ut(context, 'active', 'نشط', 'actief')}')),
                Chip(avatar: const Icon(Icons.pause_circle_rounded, size: 17, color: VetColors.history), label: Text('$suspended ${_ut(context, 'suspended', 'موقوف', 'opgeschort')}')),
                Chip(avatar: const Icon(Icons.block_rounded, size: 17, color: VetColors.red), label: Text('$closed ${_ut(context, 'closed', 'مغلق', 'gesloten')}')),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: _ut(context, 'Search customer, phone or ID', 'ابحث بالاسم أو الهاتف أو ID', 'Zoek klant, telefoon of ID')),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: InputDecoration(labelText: _ut(context, 'Status', 'الحالة', 'Status')),
                    items: [
                      DropdownMenuItem(value: 'all', child: Text(_ut(context, 'All', 'الكل', 'Alle'))),
                      DropdownMenuItem(value: 'active', child: Text(_ut(context, 'Active', 'نشط', 'Actief'))),
                      DropdownMenuItem(value: 'suspended', child: Text(_ut(context, 'Suspended', 'موقوف', 'Opgeschort'))),
                      DropdownMenuItem(value: 'closed', child: Text(_ut(context, 'Closed', 'مغلق', 'Gesloten'))),
                    ],
                    onChanged: (value) => setState(() => status = value ?? 'all'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(onPressed: reload, icon: const Icon(Icons.refresh_rounded)),
              ]),
              const SizedBox(height: 14),
              for (final row in rows)
                _CustomerCard(
                  row: row,
                  data: data,
                  onEdit: () => _edit(row),
                  onStatus: (value) => _setStatus(row, value),
                ),
              if (rows.isEmpty)
                Padding(padding: const EdgeInsets.all(40), child: Center(child: Text(_ut(context, 'No matching customers.', 'لا يوجد عملاء مطابقون.', 'Geen overeenkomende klanten.')))),
            ],
          );
        },
      );
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.row, required this.data, required this.onEdit, required this.onStatus});
  final Map<String, dynamic> row;
  final _CustomerData data;
  final VoidCallback onEdit;
  final ValueChanged<String> onStatus;

  @override
  Widget build(BuildContext context) {
    final id = row['id'].toString();
    final farms = data.farms.where((e) => e['owner_id'].toString() == id).toList();
    final farmIds = farms.map((e) => e['id'].toString()).toSet();
    final subscriptions = data.subscriptions.where((e) => farmIds.contains(e['farm_id'].toString())).toList();
    final payments = data.payments.where((e) => farmIds.contains(e['farm_id'].toString())).toList();
    final devices = data.devices.where((e) => e['user_id'].toString() == id).toList();
    final support = data.support.where((e) => farmIds.contains(e['farm_id'].toString())).toList();
    final paid = payments.where((e) => e['status'] == 'paid').fold<double>(0, (sum, e) => sum + (num.tryParse('${e['amount']}')?.toDouble() ?? 0));
    final accountStatus = '${row['account_status'] ?? 'active'}';
    final statusColor = accountStatus == 'active' ? VetColors.green : accountStatus == 'suspended' ? VetColors.history : VetColors.red;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: CircleAvatar(child: Icon(accountStatus == 'active' ? Icons.person_rounded : Icons.person_off_rounded, color: statusColor)),
        title: Text('${row['full_name'] ?? _ut(context, 'Unnamed customer', 'عميل بدون اسم', 'Naamloze klant')}', style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text('${row['phone'] ?? '-'} • ${row['job_title'] ?? '-'} • ${row['preferred_language'] ?? '-'}'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Chip(label: Text(accountStatus), avatar: Icon(Icons.circle, size: 10, color: statusColor)),
          PopupMenuButton<String>(
            onSelected: onStatus,
            itemBuilder: (_) => [
              PopupMenuItem(value: 'active', child: Text(_ut(context, 'Activate account', 'تفعيل الحساب', 'Account activeren'))),
              PopupMenuItem(value: 'suspended', child: Text(_ut(context, 'Suspend account', 'إيقاف الحساب', 'Account opschorten'))),
              PopupMenuItem(value: 'closed', child: Text(_ut(context, 'Close account', 'إغلاق الحساب', 'Account sluiten'))),
            ],
          ),
        ]),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              Chip(avatar: const Icon(Icons.domain_rounded, size: 17), label: Text('${farms.length} ${_ut(context, 'farms', 'مزرعة', 'boerderijen')}')),
              Chip(avatar: const Icon(Icons.workspace_premium_rounded, size: 17), label: Text('${subscriptions.length} ${_ut(context, 'subscriptions', 'اشتراك', 'abonnementen')}')),
              Chip(avatar: const Icon(Icons.payments_rounded, size: 17), label: Text('€${paid.toStringAsFixed(2)}')),
              Chip(avatar: const Icon(Icons.notifications_rounded, size: 17), label: Text('${devices.where((e) => e['enabled'] == true).length}/${devices.length} ${_ut(context, 'push devices', 'أجهزة إشعار', 'pushapparaten')}')),
              Chip(avatar: const Icon(Icons.support_agent_rounded, size: 17), label: Text('${support.where((e) => e['status'] != 'closed').length} ${_ut(context, 'open support', 'دعم مفتوح', 'open support')}')),
            ]),
          ),
          const SizedBox(height: 12),
          if (farms.isNotEmpty)
            Align(alignment: AlignmentDirectional.centerStart, child: Text('${_ut(context, 'Companies / farms', 'الشركات / المزارع', 'Bedrijven / boerderijen')}: ${farms.map((e) => '${e['company_name'] ?? ''} / ${e['farm_name'] ?? ''}').join(' • ')}')),
          if ('${row['admin_notes'] ?? ''}'.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(alignment: AlignmentDirectional.centerStart, child: Text('${_ut(context, 'Admin notes', 'ملاحظات الإدارة', 'Adminnotities')}: ${row['admin_notes']}', style: const TextStyle(color: VetColors.muted))),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: OutlinedButton.icon(onPressed: onEdit, icon: const Icon(Icons.edit_rounded), label: Text(_ut(context, 'Edit customer', 'تعديل العميل', 'Klant bewerken'))),
          ),
        ],
      ),
    );
  }
}

class _CustomerData {
  const _CustomerData({required this.profiles, required this.farms, required this.subscriptions, required this.payments, required this.devices, required this.support});
  final List<Map<String, dynamic>> profiles;
  final List<Map<String, dynamic>> farms;
  final List<Map<String, dynamic>> subscriptions;
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> devices;
  final List<Map<String, dynamic>> support;
}

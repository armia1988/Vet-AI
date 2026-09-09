import 'package:flutter/material.dart';

import '../i18n/vet_locale.dart';
import '../theme/app_theme.dart';
import 'admin_service.dart';

String _bt(BuildContext context, String en, String ar, String nl) =>
    VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

class VetAdminBillingCenter extends StatefulWidget {
  const VetAdminBillingCenter({super.key});

  @override
  State<VetAdminBillingCenter> createState() => _VetAdminBillingCenterState();
}

class _VetAdminBillingCenterState extends State<VetAdminBillingCenter> {
  final admin = VetAdminService.instance;
  late Future<_BillingData> future = _load();

  Future<_BillingData> _load() async {
    final values = await Future.wait([
      admin.plans(),
      admin.subscriptions(),
      admin.payments(),
      admin.farms(),
      admin.client.rpc('admin_billing_summary'),
    ]);
    return _BillingData(
      plans: values[0] as List<Map<String, dynamic>>,
      subscriptions: values[1] as List<Map<String, dynamic>>,
      payments: values[2] as List<Map<String, dynamic>>,
      farms: values[3] as List<Map<String, dynamic>>,
      summary: values[4] is Map ? Map<String, dynamic>.from(values[4] as Map) : <String, dynamic>{},
    );
  }

  void reload() => setState(() => future = _load());

  Future<void> _editPlan(Map<String, dynamic> row) async {
    final name = TextEditingController(text: '${row['name'] ?? ''}');
    final description = TextEditingController(text: '${row['description'] ?? ''}');
    final monthly = TextEditingController(text: '${row['monthly_price'] ?? 0}');
    final yearly = TextEditingController(text: '${row['yearly_price'] ?? 0}');
    final maxFarms = TextEditingController(text: '${row['max_farms'] ?? ''}');
    final maxSensors = TextEditingController(text: '${row['max_sensors'] ?? ''}');
    var active = row['active'] == true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(_bt(context, 'Edit subscription plan', 'تعديل خطة الاشتراك', 'Abonnementsplan bewerken')),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: name, decoration: InputDecoration(labelText: _bt(context, 'Plan name', 'اسم الخطة', 'Plannaam'))),
                const SizedBox(height: 10),
                TextField(controller: description, minLines: 2, maxLines: 5, decoration: InputDecoration(labelText: _bt(context, 'Description', 'الوصف', 'Beschrijving'))),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: monthly, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: _bt(context, 'Monthly price', 'السعر الشهري', 'Maandprijs')))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: yearly, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: _bt(context, 'Yearly price', 'السعر السنوي', 'Jaarprijs')))),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: maxFarms, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _bt(context, 'Max farms (blank = unlimited)', 'أقصى عدد مزارع (فارغ = غير محدود)', 'Max boerderijen (leeg = onbeperkt)')))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: maxSensors, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _bt(context, 'Max sensors (blank = unlimited)', 'أقصى عدد حساسات (فارغ = غير محدود)', 'Max sensoren (leeg = onbeperkt)')))),
                ]),
                SwitchListTile(value: active, onChanged: (v) => setLocal(() => active = v), title: Text(_bt(context, 'Plan available', 'الخطة متاحة', 'Plan beschikbaar'))),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_bt(context, 'Cancel', 'إلغاء', 'Annuleren'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_bt(context, 'Save', 'حفظ', 'Opslaan'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await admin.updatePlan(row['id'].toString(), {
      'name': name.text.trim(),
      'description': description.text.trim(),
      'monthly_price': double.tryParse(monthly.text.trim()) ?? 0,
      'yearly_price': double.tryParse(yearly.text.trim()) ?? 0,
      'max_farms': maxFarms.text.trim().isEmpty ? null : int.tryParse(maxFarms.text.trim()),
      'max_sensors': maxSensors.text.trim().isEmpty ? null : int.tryParse(maxSensors.text.trim()),
      'active': active,
    });
    reload();
  }

  Future<void> _createSubscription(_BillingData data) async {
    String? farmId;
    String? planId;
    var status = 'active';
    var cycle = 'monthly';
    var currency = 'EUR';
    final amount = TextEditingController(text: '0');
    final notes = TextEditingController();
    final periodDays = TextEditingController(text: '30');

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(_bt(context, 'Create subscription', 'إنشاء اشتراك', 'Abonnement aanmaken')),
          content: SizedBox(
            width: 660,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  initialValue: farmId,
                  decoration: InputDecoration(labelText: _bt(context, 'Company / farm', 'الشركة / المزرعة', 'Bedrijf / boerderij')),
                  items: [for (final f in data.farms) DropdownMenuItem(value: f['id'].toString(), child: Text('${f['company_name'] ?? ''} / ${f['farm_name'] ?? ''}'))],
                  onChanged: (v) => setLocal(() => farmId = v),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: planId,
                  decoration: InputDecoration(labelText: _bt(context, 'Plan', 'الخطة', 'Plan')),
                  items: [for (final p in data.plans) DropdownMenuItem(value: p['id'].toString(), child: Text('${p['name']} • €${p['monthly_price']}/m'))],
                  onChanged: (v) {
                    final matches = data.plans.where((e) => e['id'].toString() == v).toList();
                    setLocal(() => planId = v);
                    if (matches.isNotEmpty) amount.text = '${matches.first['monthly_price'] ?? 0}';
                  },
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: DropdownButtonFormField<String>(initialValue: status, decoration: InputDecoration(labelText: _bt(context, 'Status', 'الحالة', 'Status')), items: const [DropdownMenuItem(value: 'trial', child: Text('trial')), DropdownMenuItem(value: 'active', child: Text('active')), DropdownMenuItem(value: 'past_due', child: Text('past_due')), DropdownMenuItem(value: 'paused', child: Text('paused'))], onChanged: (v) => setLocal(() => status = v ?? 'active'))),
                  const SizedBox(width: 10),
                  Expanded(child: DropdownButtonFormField<String>(initialValue: cycle, decoration: InputDecoration(labelText: _bt(context, 'Billing cycle', 'دورة الدفع', 'Factureringscyclus')), items: const [DropdownMenuItem(value: 'monthly', child: Text('monthly')), DropdownMenuItem(value: 'yearly', child: Text('yearly')), DropdownMenuItem(value: 'manual', child: Text('manual'))], onChanged: (v) => setLocal(() => cycle = v ?? 'monthly'))),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: _bt(context, 'Amount', 'المبلغ', 'Bedrag')))),
                  const SizedBox(width: 10),
                  SizedBox(width: 120, child: TextField(onChanged: (v) => currency = v.trim().toUpperCase(), controller: TextEditingController(text: currency), decoration: InputDecoration(labelText: _bt(context, 'Currency', 'العملة', 'Valuta')))),
                  const SizedBox(width: 10),
                  SizedBox(width: 150, child: TextField(controller: periodDays, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _bt(context, 'Period days', 'مدة الفترة', 'Periodes dagen')))),
                ]),
                const SizedBox(height: 10),
                TextField(controller: notes, minLines: 2, maxLines: 4, decoration: InputDecoration(labelText: _bt(context, 'Admin notes', 'ملاحظات الإدارة', 'Adminnotities'))),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_bt(context, 'Cancel', 'إلغاء', 'Annuleren'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_bt(context, 'Create', 'إنشاء', 'Aanmaken'))),
          ],
        ),
      ),
    );
    if (ok != true || farmId == null) return;
    final periodEnd = DateTime.now().toUtc().add(Duration(days: int.tryParse(periodDays.text.trim()) ?? 30));
    final inserted = await admin.createSubscription(
      farmId: farmId!,
      planId: planId,
      status: status,
      billingCycle: cycle,
      currency: currency.isEmpty ? 'EUR' : currency,
      amount: double.tryParse(amount.text.trim()) ?? 0,
      periodEnd: periodEnd,
    );
    if (notes.text.trim().isNotEmpty) await admin.updateSubscription(inserted['id'].toString(), {'notes': notes.text.trim()});
    reload();
  }

  Future<void> _editSubscription(Map<String, dynamic> row, _BillingData data) async {
    var nextStatus = '${row['status'] ?? 'active'}';
    var cycle = '${row['billing_cycle'] ?? 'monthly'}';
    String? planId = row['plan_id']?.toString();
    final amount = TextEditingController(text: '${row['amount'] ?? 0}');
    final notes = TextEditingController(text: '${row['notes'] ?? ''}');
    final external = TextEditingController(text: '${row['external_subscription_id'] ?? ''}');

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(_bt(context, 'Edit subscription', 'تعديل الاشتراك', 'Abonnement bewerken')),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(initialValue: planId, decoration: InputDecoration(labelText: _bt(context, 'Plan', 'الخطة', 'Plan')), items: [for (final p in data.plans) DropdownMenuItem(value: p['id'].toString(), child: Text('${p['name']}'))], onChanged: (v) => setLocal(() => planId = v)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: DropdownButtonFormField<String>(initialValue: nextStatus, decoration: InputDecoration(labelText: _bt(context, 'Status', 'الحالة', 'Status')), items: const [DropdownMenuItem(value: 'trial', child: Text('trial')), DropdownMenuItem(value: 'active', child: Text('active')), DropdownMenuItem(value: 'past_due', child: Text('past_due')), DropdownMenuItem(value: 'paused', child: Text('paused')), DropdownMenuItem(value: 'cancelled', child: Text('cancelled')), DropdownMenuItem(value: 'expired', child: Text('expired'))], onChanged: (v) => setLocal(() => nextStatus = v ?? nextStatus))),
                const SizedBox(width: 10),
                Expanded(child: DropdownButtonFormField<String>(initialValue: cycle, decoration: InputDecoration(labelText: _bt(context, 'Cycle', 'الدورة', 'Cyclus')), items: const [DropdownMenuItem(value: 'monthly', child: Text('monthly')), DropdownMenuItem(value: 'yearly', child: Text('yearly')), DropdownMenuItem(value: 'manual', child: Text('manual'))], onChanged: (v) => setLocal(() => cycle = v ?? cycle))),
              ]),
              const SizedBox(height: 10),
              TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: _bt(context, 'Amount', 'المبلغ', 'Bedrag'))),
              const SizedBox(height: 10),
              TextField(controller: external, decoration: InputDecoration(labelText: _bt(context, 'External subscription ID', 'رقم الاشتراك الخارجي', 'Extern abonnements-ID'))),
              const SizedBox(height: 10),
              TextField(controller: notes, minLines: 3, maxLines: 6, decoration: InputDecoration(labelText: _bt(context, 'Notes', 'ملاحظات', 'Notities'))),
            ])),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_bt(context, 'Cancel', 'إلغاء', 'Annuleren'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_bt(context, 'Save', 'حفظ', 'Opslaan'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await admin.updateSubscription(row['id'].toString(), {
      'plan_id': planId,
      'status': nextStatus,
      'billing_cycle': cycle,
      'amount': double.tryParse(amount.text.trim()) ?? 0,
      'external_subscription_id': external.text.trim().isEmpty ? null : external.text.trim(),
      'notes': notes.text.trim(),
      if (nextStatus == 'cancelled') 'cancelled_at': DateTime.now().toUtc().toIso8601String(),
    });
    reload();
  }

  Future<void> _addPayment(_BillingData data) async {
    String? farmId;
    String? subscriptionId;
    var status = 'pending';
    var provider = 'manual';
    var currency = 'EUR';
    final amount = TextEditingController();
    final description = TextEditingController();
    final providerId = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(_bt(context, 'Create payment / invoice', 'إنشاء دفعة / فاتورة', 'Betaling / factuur maken')),
          content: SizedBox(width: 650, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(initialValue: farmId, decoration: InputDecoration(labelText: _bt(context, 'Company / farm', 'الشركة / المزرعة', 'Bedrijf / boerderij')), items: [for (final f in data.farms) DropdownMenuItem(value: f['id'].toString(), child: Text('${f['company_name'] ?? ''} / ${f['farm_name'] ?? ''}'))], onChanged: (v) => setLocal(() { farmId = v; subscriptionId = null; })),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(initialValue: subscriptionId, decoration: InputDecoration(labelText: _bt(context, 'Subscription (optional)', 'الاشتراك (اختياري)', 'Abonnement (optioneel)')), items: [for (final s in data.subscriptions.where((e) => farmId == null || e['farm_id'].toString() == farmId)) DropdownMenuItem(value: s['id'].toString(), child: Text('${s['status']} • ${s['amount']} ${s['currency']}'))], onChanged: (v) => setLocal(() => subscriptionId = v)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: _bt(context, 'Amount', 'المبلغ', 'Bedrag')))),
              const SizedBox(width: 10),
              SizedBox(width: 120, child: TextField(onChanged: (v) => currency = v.trim().toUpperCase(), controller: TextEditingController(text: currency), decoration: InputDecoration(labelText: _bt(context, 'Currency', 'العملة', 'Valuta')))),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: DropdownButtonFormField<String>(initialValue: status, decoration: InputDecoration(labelText: _bt(context, 'Status', 'الحالة', 'Status')), items: const [DropdownMenuItem(value: 'pending', child: Text('pending')), DropdownMenuItem(value: 'paid', child: Text('paid')), DropdownMenuItem(value: 'failed', child: Text('failed')), DropdownMenuItem(value: 'cancelled', child: Text('cancelled'))], onChanged: (v) => setLocal(() => status = v ?? 'pending'))),
              const SizedBox(width: 10),
              Expanded(child: TextField(onChanged: (v) => provider = v.trim().isEmpty ? 'manual' : v.trim(), controller: TextEditingController(text: provider), decoration: InputDecoration(labelText: _bt(context, 'Provider', 'مزود الدفع', 'Provider')))),
            ]),
            const SizedBox(height: 10),
            TextField(controller: providerId, decoration: InputDecoration(labelText: _bt(context, 'Provider payment ID', 'رقم العملية لدى مزود الدفع', 'Provider-betalings-ID'))),
            const SizedBox(height: 10),
            TextField(controller: description, minLines: 2, maxLines: 4, decoration: InputDecoration(labelText: _bt(context, 'Description', 'الوصف', 'Beschrijving'))),
          ]))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_bt(context, 'Cancel', 'إلغاء', 'Annuleren'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_bt(context, 'Create', 'إنشاء', 'Aanmaken'))),
          ],
        ),
      ),
    );
    if (ok != true || farmId == null) return;
    final row = await admin.createPayment(
      farmId: farmId!,
      subscriptionId: subscriptionId,
      amount: double.tryParse(amount.text.trim()) ?? 0,
      currency: currency.isEmpty ? 'EUR' : currency,
      status: status,
      provider: provider,
      description: description.text.trim(),
    );
    if (providerId.text.trim().isNotEmpty) await admin.updatePayment(row['id'].toString(), {'provider_payment_id': providerId.text.trim()});
    reload();
  }

  Future<void> _changePayment(Map<String, dynamic> row, String next) async {
    final update = <String, dynamic>{'status': next};
    if (next == 'paid') update['paid_at'] = DateTime.now().toUtc().toIso8601String();
    if (next == 'refunded') {
      update['refunded_at'] = DateTime.now().toUtc().toIso8601String();
      update['refund_amount'] = num.tryParse('${row['amount']}')?.toDouble() ?? 0;
    }
    await admin.updatePayment(row['id'].toString(), update);
    reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_BillingData>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('${snapshot.error}', style: const TextStyle(color: VetColors.red)));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!;
          final farmNames = {for (final f in data.farms) f['id'].toString(): '${f['company_name'] ?? ''} / ${f['farm_name'] ?? ''}'};
          final planNames = {for (final p in data.plans) p['id'].toString(): '${p['name'] ?? ''}'};

          return DefaultTabController(
            length: 4,
            child: Column(children: [
              Material(
                color: VetColors.surface2,
                child: TabBar(isScrollable: true, tabs: [
                  Tab(icon: const Icon(Icons.dashboard_rounded), text: _bt(context, 'Billing overview', 'نظرة مالية', 'Factureringsoverzicht')),
                  Tab(icon: const Icon(Icons.workspace_premium_rounded), text: _bt(context, 'Subscriptions', 'الاشتراكات', 'Abonnementen')),
                  Tab(icon: const Icon(Icons.sell_rounded), text: _bt(context, 'Plans', 'الخطط', 'Plannen')),
                  Tab(icon: const Icon(Icons.receipt_long_rounded), text: _bt(context, 'Payments & invoices', 'المدفوعات والفواتير', 'Betalingen & facturen')),
                ]),
              ),
              Expanded(child: TabBarView(children: [
                _overview(context, data),
                _subscriptions(context, data, farmNames, planNames),
                _plans(context, data),
                _payments(context, data, farmNames),
              ])),
            ]),
          );
        },
      );

  Widget _overview(BuildContext context, _BillingData data) {
    final s = data.summary;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text(_bt(context, 'Commercial control center', 'مركز التحكم التجاري', 'Commercieel controlecentrum'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      const SizedBox(height: 5),
      Text(_bt(context, 'Subscriptions, invoices, payment status, pricing and revenue in one place.', 'الاشتراكات والفواتير وحالات الدفع والأسعار والإيرادات في مكان واحد.', 'Abonnementen, facturen, betaalstatus, prijzen en omzet op één plek.'), style: const TextStyle(color: VetColors.muted)),
      const SizedBox(height: 16),
      Wrap(spacing: 12, runSpacing: 12, children: [
        _billingMetric(context, Icons.workspace_premium_rounded, _bt(context, 'Active', 'اشتراكات نشطة', 'Actief'), '${s['active_subscriptions'] ?? 0}', VetColors.green),
        _billingMetric(context, Icons.hourglass_top_rounded, _bt(context, 'Trials', 'تجارب', 'Proefperioden'), '${s['trial_subscriptions'] ?? 0}', VetColors.blue),
        _billingMetric(context, Icons.warning_amber_rounded, _bt(context, 'Past due', 'متأخر', 'Achterstallig'), '${s['past_due_subscriptions'] ?? 0}', VetColors.history),
        _billingMetric(context, Icons.account_balance_wallet_rounded, _bt(context, 'Paid total', 'إجمالي المدفوع', 'Totaal betaald'), '€${s['paid_total'] ?? 0}', VetColors.green),
        _billingMetric(context, Icons.pending_actions_rounded, _bt(context, 'Pending', 'معلق', 'Openstaand'), '€${s['pending_total'] ?? 0}', VetColors.history),
        _billingMetric(context, Icons.undo_rounded, _bt(context, 'Refunded', 'مسترد', 'Terugbetaald'), '€${s['refunded_total'] ?? 0}', VetColors.red),
      ]),
      const SizedBox(height: 18),
      Align(alignment: AlignmentDirectional.centerEnd, child: Wrap(spacing: 8, children: [
        FilledButton.icon(onPressed: () => _createSubscription(data), icon: const Icon(Icons.add_rounded), label: Text(_bt(context, 'New subscription', 'اشتراك جديد', 'Nieuw abonnement'))),
        OutlinedButton.icon(onPressed: () => _addPayment(data), icon: const Icon(Icons.add_card_rounded), label: Text(_bt(context, 'New payment', 'دفعة جديدة', 'Nieuwe betaling'))),
      ])),
    ]);
  }

  Widget _subscriptions(BuildContext context, _BillingData data, Map<String, String> farms, Map<String, String> plans) => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Align(alignment: AlignmentDirectional.centerEnd, child: FilledButton.icon(onPressed: () => _createSubscription(data), icon: const Icon(Icons.add_rounded), label: Text(_bt(context, 'Create subscription', 'إنشاء اشتراك', 'Abonnement aanmaken')))),
          const SizedBox(height: 12),
          for (final row in data.subscriptions)
            Card(child: ListTile(
              leading: CircleAvatar(child: Icon(row['status'] == 'active' ? Icons.check_circle_rounded : Icons.workspace_premium_rounded)),
              title: Text(farms[row['farm_id'].toString()] ?? row['farm_id'].toString(), style: const TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text('${plans[row['plan_id']?.toString()] ?? '-'} • ${row['status']} • ${row['billing_cycle']}\n${row['currency']} ${row['amount']} • ${row['current_period_end'] ?? '-'}'),
              isThreeLine: true,
              trailing: IconButton(onPressed: () => _editSubscription(row, data), icon: const Icon(Icons.edit_rounded)),
              onTap: () => _editSubscription(row, data),
            )),
        ],
      );

  Widget _plans(BuildContext context, _BillingData data) => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          for (final row in data.plans)
            Card(child: ListTile(
              leading: CircleAvatar(child: Icon(row['active'] == true ? Icons.sell_rounded : Icons.visibility_off_rounded)),
              title: Text('${row['name']} • ${row['currency']} ${row['monthly_price']}/m', style: const TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text('${row['description'] ?? ''}\n${_bt(context, 'Max farms', 'أقصى مزارع', 'Max boerderijen')}: ${row['max_farms'] ?? '∞'} • ${_bt(context, 'Max sensors', 'أقصى حساسات', 'Max sensoren')}: ${row['max_sensors'] ?? '∞'} • ${row['active'] == true ? 'active' : 'inactive'}'),
              isThreeLine: true,
              trailing: IconButton(onPressed: () => _editPlan(row), icon: const Icon(Icons.edit_rounded)),
              onTap: () => _editPlan(row),
            )),
        ],
      );

  Widget _payments(BuildContext context, _BillingData data, Map<String, String> farms) => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Align(alignment: AlignmentDirectional.centerEnd, child: FilledButton.icon(onPressed: () => _addPayment(data), icon: const Icon(Icons.add_card_rounded), label: Text(_bt(context, 'Create payment', 'إنشاء دفعة', 'Betaling maken')))),
          const SizedBox(height: 12),
          for (final row in data.payments)
            Card(child: ListTile(
              leading: CircleAvatar(child: Icon(row['status'] == 'paid' ? Icons.check_rounded : row['status'] == 'refunded' ? Icons.undo_rounded : Icons.receipt_long_rounded)),
              title: Text('${row['invoice_number'] ?? '-'} • ${row['currency']} ${row['amount']}', style: const TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text('${farms[row['farm_id'].toString()] ?? row['farm_id']}\n${row['status']} • ${row['provider']} • ${row['provider_payment_id'] ?? '-'}\n${row['description'] ?? ''}'),
              isThreeLine: true,
              trailing: PopupMenuButton<String>(
                onSelected: (v) => _changePayment(row, v),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'paid', child: Text(_bt(context, 'Mark paid', 'تعيين كمدفوع', 'Markeer betaald'))),
                  PopupMenuItem(value: 'pending', child: Text(_bt(context, 'Mark pending', 'تعيين كمعلق', 'Markeer openstaand'))),
                  PopupMenuItem(value: 'failed', child: Text(_bt(context, 'Mark failed', 'تعيين كفاشل', 'Markeer mislukt'))),
                  PopupMenuItem(value: 'refunded', child: Text(_bt(context, 'Mark refunded', 'تعيين كمسترد', 'Markeer terugbetaald'))),
                  PopupMenuItem(value: 'cancelled', child: Text(_bt(context, 'Cancel', 'إلغاء', 'Annuleren'))),
                ],
              ),
            )),
        ],
      );

  Widget _billingMetric(BuildContext context, IconData icon, String title, String value, Color color) => SizedBox(
        width: MediaQuery.sizeOf(context).width > 700 ? 220 : double.infinity,
        child: Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
          CircleAvatar(backgroundColor: color.withValues(alpha: .12), child: Icon(icon, color: color)),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)), Text(title, style: const TextStyle(color: VetColors.muted, fontSize: 12))])),
        ]))),
      );
}

class _BillingData {
  const _BillingData({required this.plans, required this.subscriptions, required this.payments, required this.farms, required this.summary});
  final List<Map<String, dynamic>> plans;
  final List<Map<String, dynamic>> subscriptions;
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> farms;
  final Map<String, dynamic> summary;
}

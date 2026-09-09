import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/vet_locale.dart';
import '../theme/app_theme.dart';
import 'admin_service.dart';

String _gst(BuildContext context, String en, String ar, String nl) =>
    VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

class VetAdminGlobalSearchCenter extends StatefulWidget {
  const VetAdminGlobalSearchCenter({super.key});

  @override
  State<VetAdminGlobalSearchCenter> createState() =>
      _VetAdminGlobalSearchCenterState();
}

class _VetAdminGlobalSearchCenterState
    extends State<VetAdminGlobalSearchCenter> {
  final admin = VetAdminService.instance;
  final query = TextEditingController();
  List<Map<String, dynamic>> results = const [];
  bool loading = false;
  Object? error;
  String filter = 'all';

  static const entityTypes = <String>[
    'all',
    'customer',
    'farm',
    'sensor',
    'animal',
    'alert',
    'support',
    'payment',
  ];

  Future<void> search() async {
    final value = query.text.trim();
    if (value.length < 2) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final raw = await admin.client.rpc(
        'admin_global_search',
        params: {'p_query': value, 'p_limit': 120},
      );
      final rows = (raw as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() => results = rows);
    } catch (e) {
      if (!mounted) return;
      setState(() => error = e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String label(BuildContext context, String type) => switch (type) {
        'customer' => _gst(context, 'Customer', 'عميل', 'Klant'),
        'farm' => _gst(context, 'Company / farm', 'شركة / مزرعة', 'Bedrijf / boerderij'),
        'sensor' => _gst(context, 'Sensor', 'حساس', 'Sensor'),
        'animal' => _gst(context, 'Animal', 'حيوان', 'Dier'),
        'alert' => _gst(context, 'Alert', 'إنذار', 'Alarm'),
        'support' => _gst(context, 'Support', 'دعم', 'Support'),
        'payment' => _gst(context, 'Payment', 'دفعة', 'Betaling'),
        _ => _gst(context, 'All', 'الكل', 'Alles'),
      };

  IconData icon(String type) => switch (type) {
        'customer' => Icons.person_rounded,
        'farm' => Icons.domain_rounded,
        'sensor' => Icons.sensors_rounded,
        'animal' => Icons.pets_rounded,
        'alert' => Icons.warning_amber_rounded,
        'support' => Icons.support_agent_rounded,
        'payment' => Icons.payments_rounded,
        _ => Icons.search_rounded,
      };

  Color color(String type) => switch (type) {
        'alert' => VetColors.red,
        'sensor' => VetColors.green,
        'payment' => VetColors.history,
        'support' => VetColors.blue,
        _ => VetColors.green,
      };

  Future<void> copyValue(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_gst(context, 'Copied', 'تم النسخ', 'Gekopieerd')),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = filter == 'all'
        ? results
        : results.where((e) => e['entity_type'] == filter).toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          _gst(context, 'Global search & command finder', 'البحث الشامل في Vet AI', 'Globaal zoeken in Vet AI'),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 5),
        Text(
          _gst(
            context,
            'Find a customer, company, farm, sensor, animal, alert, support case or invoice from one place.',
            'ابحث عن عميل أو شركة أو مزرعة أو حساس أو حيوان أو إنذار أو محادثة دعم أو فاتورة من مكان واحد.',
            'Vind klanten, bedrijven, boerderijen, sensoren, dieren, alarmen, supportcases en facturen op één plek.',
          ),
          style: const TextStyle(color: VetColors.muted),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: query,
                  autofocus: false,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => search(),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: _gst(
                      context,
                      'Name, phone, company, sensor UID, animal tag, invoice…',
                      'اسم، هاتف، شركة، رقم حساس، تاج حيوان، فاتورة…',
                      'Naam, telefoon, bedrijf, sensor-UID, diernummer, factuur…',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: loading ? null : search,
                icon: loading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.search_rounded),
                label: Text(_gst(context, 'Search', 'بحث', 'Zoeken')),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final type in entityTypes)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(
                    selected: filter == type,
                    onSelected: (_) => setState(() => filter = type),
                    avatar: Icon(icon(type), size: 16),
                    label: Text(label(context, type)),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (error != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.error_outline_rounded, color: VetColors.red),
              title: Text(_gst(context, 'Search failed', 'تعذر البحث', 'Zoeken mislukt')),
              subtitle: Text('$error'),
              trailing: IconButton(onPressed: search, icon: const Icon(Icons.refresh_rounded)),
            ),
          )
        else if (!loading && results.isEmpty && query.text.trim().isNotEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.search_off_rounded),
              title: Text(_gst(context, 'No matching records', 'لا توجد نتائج مطابقة', 'Geen overeenkomende records')),
            ),
          )
        else ...[
          if (results.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${shown.length} ${_gst(context, 'results', 'نتيجة', 'resultaten')}',
                style: const TextStyle(fontWeight: FontWeight.w800, color: VetColors.muted),
              ),
            ),
          for (final row in shown)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: color('${row['entity_type']}').withValues(alpha: .12),
                  child: Icon(icon('${row['entity_type']}'), color: color('${row['entity_type']}')),
                ),
                title: Text('${row['title'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w900)),
                subtitle: Text(
                  '${label(context, '${row['entity_type']}')} • ${row['status'] ?? '-'}\n${row['subtitle'] ?? ''}',
                ),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'entity') copyValue('${row['entity_id']}');
                    if (value == 'farm' && row['farm_id'] != null) copyValue('${row['farm_id']}');
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(value: 'entity', child: Text(_gst(context, 'Copy record ID', 'نسخ رقم السجل', 'Record-ID kopiëren'))),
                    if (row['farm_id'] != null)
                      PopupMenuItem(value: 'farm', child: Text(_gst(context, 'Copy farm ID', 'نسخ رقم المزرعة', 'Boerderij-ID kopiëren'))),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: 50),
      ],
    );
  }
}

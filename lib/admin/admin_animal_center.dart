import 'package:flutter/material.dart';

import '../i18n/vet_locale.dart';
import '../theme/app_theme.dart';
import 'admin_service.dart';

String _ant(BuildContext context, String en, String ar, String nl) =>
    VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

class VetAdminAnimalCenter extends StatefulWidget {
  const VetAdminAnimalCenter({super.key});

  @override
  State<VetAdminAnimalCenter> createState() => _VetAdminAnimalCenterState();
}

class _VetAdminAnimalCenterState extends State<VetAdminAnimalCenter> {
  final admin = VetAdminService.instance;
  final search = TextEditingController();
  String group = 'all';
  String activity = 'all';
  late Future<_AnimalData> future = _load();

  Future<_AnimalData> _load() async {
    final values = await Future.wait([admin.animals(), admin.farms(), admin.sensors()]);
    return _AnimalData(animals: values[0], farms: values[1], sensors: values[2]);
  }

  void reload() => setState(() => future = _load());

  Future<void> _edit({Map<String, dynamic>? row, required _AnimalData data}) async {
    String? farmId = row?['farm_id']?.toString();
    var animalGroup = '${row?['animal_group'] ?? 'livestock'}';
    final externalId = TextEditingController(text: '${row?['external_id'] ?? ''}');
    final name = TextEditingController(text: '${row?['name'] ?? ''}');
    final species = TextEditingController(text: '${row?['species'] ?? ''}');
    final breed = TextEditingController(text: '${row?['breed'] ?? ''}');
    final sex = TextEditingController(text: '${row?['sex'] ?? ''}');
    final ageDays = TextEditingController(text: '${row?['approximate_age_days'] ?? ''}');
    final weight = TextEditingController(text: '${row?['weight_kg'] ?? ''}');
    final notes = TextEditingController(text: '${row?['admin_notes'] ?? ''}');
    var active = row?['active'] == true || row == null;
    var pregnant = row?['pregnant'] == true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(row == null
              ? _ant(context, 'Add animal', 'إضافة حيوان', 'Dier toevoegen')
              : _ant(context, 'Edit animal record', 'تعديل سجل الحيوان', 'Dierrecord bewerken')),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  initialValue: farmId,
                  decoration: InputDecoration(labelText: _ant(context, 'Company / farm', 'الشركة / المزرعة', 'Bedrijf / boerderij')),
                  items: [for (final f in data.farms) DropdownMenuItem(value: f['id'].toString(), child: Text('${f['company_name'] ?? ''} / ${f['farm_name'] ?? ''}'))],
                  onChanged: row == null ? (v) => setLocal(() => farmId = v) : null,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: animalGroup,
                  decoration: InputDecoration(labelText: _ant(context, 'Animal group', 'مجموعة الحيوان', 'Diergroep')),
                  items: [
                    DropdownMenuItem(value: 'livestock', child: Text(_ant(context, 'Livestock', 'ماشية', 'Vee'))),
                    DropdownMenuItem(value: 'poultry', child: Text(_ant(context, 'Poultry / birds', 'دواجن / طيور', 'Pluimvee / vogels'))),
                    DropdownMenuItem(value: 'dogs', child: Text(_ant(context, 'Dogs', 'كلاب', 'Honden'))),
                  ],
                  onChanged: (v) => setLocal(() => animalGroup = v ?? animalGroup),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: name, decoration: InputDecoration(labelText: _ant(context, 'Name', 'الاسم', 'Naam')))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: externalId, decoration: InputDecoration(labelText: _ant(context, 'External / tag ID', 'رقم الحيوان / التاج', 'Extern / tag-ID')))),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: species, decoration: InputDecoration(labelText: _ant(context, 'Species', 'النوع', 'Soort')))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: breed, decoration: InputDecoration(labelText: _ant(context, 'Breed', 'السلالة', 'Ras')))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: sex, decoration: InputDecoration(labelText: _ant(context, 'Sex', 'الجنس', 'Geslacht')))),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: ageDays, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _ant(context, 'Approx. age (days)', 'العمر التقريبي بالأيام', 'Geschatte leeftijd (dagen)')))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: weight, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: _ant(context, 'Weight kg', 'الوزن كجم', 'Gewicht kg')))),
                ]),
                const SizedBox(height: 6),
                SwitchListTile(contentPadding: EdgeInsets.zero, value: pregnant, onChanged: (v) => setLocal(() => pregnant = v), title: Text(_ant(context, 'Pregnant', 'حامل', 'Drachtig'))),
                SwitchListTile(contentPadding: EdgeInsets.zero, value: active, onChanged: (v) => setLocal(() => active = v), title: Text(_ant(context, 'Animal active', 'الحيوان نشط', 'Dier actief'))),
                const SizedBox(height: 6),
                TextField(controller: notes, minLines: 3, maxLines: 6, decoration: InputDecoration(labelText: _ant(context, 'Private admin notes', 'ملاحظات إدارية خاصة', 'Privé-adminnotities'))),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_ant(context, 'Cancel', 'إلغاء', 'Annuleren'))),
            FilledButton(onPressed: farmId == null ? null : () => Navigator.pop(dialogContext, true), child: Text(_ant(context, 'Save', 'حفظ', 'Opslaan'))),
          ],
        ),
      ),
    );
    if (ok != true || farmId == null) return;

    final values = <String, dynamic>{
      'animal_group': animalGroup,
      'external_id': externalId.text.trim().isEmpty ? null : externalId.text.trim(),
      'name': name.text.trim().isEmpty ? null : name.text.trim(),
      'species': species.text.trim().isEmpty ? null : species.text.trim(),
      'breed': breed.text.trim().isEmpty ? null : breed.text.trim(),
      'sex': sex.text.trim().isEmpty ? null : sex.text.trim(),
      'approximate_age_days': ageDays.text.trim().isEmpty ? null : int.tryParse(ageDays.text.trim()),
      'weight_kg': weight.text.trim().isEmpty ? null : double.tryParse(weight.text.trim()),
      'pregnant': pregnant,
      'active': active,
      'admin_notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
    };
    if (row == null) {
      await admin.client.from('animals').insert({'farm_id': farmId, ...values});
    } else {
      await admin.client.from('animals').update(values).eq('id', row['id']);
    }
    reload();
  }

  Future<void> _setActive(Map<String, dynamic> row, bool active) async {
    await admin.client.from('animals').update({'active': active}).eq('id', row['id']);
    reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_AnimalData>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('${snapshot.error}', style: const TextStyle(color: VetColors.red)));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!;
          final farms = {for (final f in data.farms) f['id'].toString(): f};
          final needle = search.text.trim().toLowerCase();
          final rows = data.animals.where((row) {
            if (group != 'all' && '${row['animal_group']}' != group) return false;
            if (activity == 'active' && row['active'] != true) return false;
            if (activity == 'inactive' && row['active'] == true) return false;
            if (needle.isEmpty) return true;
            final farm = farms[row['farm_id'].toString()];
            final hay = '${row['name']} ${row['external_id']} ${row['species']} ${row['breed']} ${farm?['company_name']} ${farm?['farm_name']}'.toLowerCase();
            return hay.contains(needle);
          }).toList();
          final activeCount = data.animals.where((e) => e['active'] == true).length;
          final linkedSensors = data.sensors.where((e) => e['animal_id'] != null).length;

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_ant(context, 'Animal registry operations', 'إدارة سجل الحيوانات', 'Dierregisterbeheer'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 5),
                  Text(_ant(context, 'Create and edit animal records across every customer farm and see sensor assignments.', 'أضف وعدّل سجلات الحيوانات في كل مزارع العملاء وشاهد الحساسات المرتبطة بها.', 'Maak en bewerk dierrecords voor alle klantboerderijen en bekijk sensorkoppelingen.'), style: const TextStyle(color: VetColors.muted)),
                ])),
                FilledButton.icon(onPressed: () => _edit(data: data), icon: const Icon(Icons.add_rounded), label: Text(_ant(context, 'Add animal', 'إضافة حيوان', 'Dier toevoegen'))),
              ]),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Chip(avatar: const Icon(Icons.pets_rounded, size: 17), label: Text('${data.animals.length} ${_ant(context, 'animals', 'حيوان', 'dieren')}')),
                Chip(avatar: const Icon(Icons.check_circle_rounded, size: 17, color: VetColors.green), label: Text('$activeCount ${_ant(context, 'active', 'نشط', 'actief')}')),
                Chip(avatar: const Icon(Icons.sensors_rounded, size: 17, color: VetColors.blue), label: Text('$linkedSensors ${_ant(context, 'sensor assignments', 'حساس مرتبط', 'sensorkoppelingen')}')),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 10, runSpacing: 10, children: [
                SizedBox(width: 410, child: TextField(controller: search, onChanged: (_) => setState(() {}), decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: _ant(context, 'Search animal, tag, breed or company', 'ابحث بالحيوان أو التاج أو السلالة أو الشركة', 'Zoek dier, tag, ras of bedrijf')))),
                SizedBox(width: 190, child: DropdownButtonFormField<String>(initialValue: group, decoration: InputDecoration(labelText: _ant(context, 'Group', 'المجموعة', 'Groep')), items: [DropdownMenuItem(value: 'all', child: Text(_ant(context, 'All groups', 'كل المجموعات', 'Alle groepen'))), const DropdownMenuItem(value: 'livestock', child: Text('Livestock')), const DropdownMenuItem(value: 'poultry', child: Text('Poultry')), const DropdownMenuItem(value: 'dogs', child: Text('Dogs'))], onChanged: (v) => setState(() => group = v ?? 'all'))),
                SizedBox(width: 170, child: DropdownButtonFormField<String>(initialValue: activity, decoration: InputDecoration(labelText: _ant(context, 'Status', 'الحالة', 'Status')), items: [DropdownMenuItem(value: 'all', child: Text(_ant(context, 'All', 'الكل', 'Alle'))), DropdownMenuItem(value: 'active', child: Text(_ant(context, 'Active', 'نشط', 'Actief'))), DropdownMenuItem(value: 'inactive', child: Text(_ant(context, 'Inactive', 'غير نشط', 'Inactief')))], onChanged: (v) => setState(() => activity = v ?? 'all'))),
                IconButton.filledTonal(onPressed: reload, icon: const Icon(Icons.refresh_rounded)),
              ]),
              const SizedBox(height: 14),
              for (final row in rows)
                _AnimalCard(
                  row: row,
                  farm: farms[row['farm_id'].toString()],
                  linkedSensors: data.sensors.where((e) => e['animal_id']?.toString() == row['id'].toString()).toList(),
                  onEdit: () => _edit(row: row, data: data),
                  onActive: (v) => _setActive(row, v),
                ),
              if (rows.isEmpty) Padding(padding: const EdgeInsets.all(38), child: Center(child: Text(_ant(context, 'No animals match the filters.', 'لا توجد حيوانات مطابقة للفلاتر.', 'Geen dieren passen bij de filters.')))),
            ],
          );
        },
      );
}

class _AnimalCard extends StatelessWidget {
  const _AnimalCard({required this.row, required this.farm, required this.linkedSensors, required this.onEdit, required this.onActive});
  final Map<String, dynamic> row;
  final Map<String, dynamic>? farm;
  final List<Map<String, dynamic>> linkedSensors;
  final VoidCallback onEdit;
  final ValueChanged<bool> onActive;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 11),
        child: ExpansionTile(
          leading: CircleAvatar(child: Icon(row['active'] == true ? Icons.pets_rounded : Icons.block_rounded, color: row['active'] == true ? VetColors.green : VetColors.red)),
          title: Text('${row['name'] ?? row['external_id'] ?? _ant(context, 'Unnamed animal', 'حيوان بدون اسم', 'Naamloos dier')} • ${row['species'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w900)),
          subtitle: Text('${farm?['company_name'] ?? ''} / ${farm?['farm_name'] ?? row['farm_id']}\n${row['breed'] ?? '-'} • ${row['sex'] ?? '-'} • ${row['weight_kg'] ?? '-'} kg • ${linkedSensors.length} ${_ant(context, 'sensors', 'حساس', 'sensoren')}'),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          trailing: PopupMenuButton<String>(
            onSelected: (v) => v == 'edit' ? onEdit() : onActive(v == 'activate'),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'edit', child: Text(_ant(context, 'Edit record', 'تعديل السجل', 'Record bewerken'))),
              PopupMenuItem(value: row['active'] == true ? 'deactivate' : 'activate', child: Text(row['active'] == true ? _ant(context, 'Deactivate', 'إيقاف', 'Deactiveren') : _ant(context, 'Activate', 'تفعيل', 'Activeren'))),
            ],
          ),
          children: [
            Align(alignment: AlignmentDirectional.centerStart, child: Wrap(spacing: 8, runSpacing: 8, children: [
              Chip(label: Text('${_ant(context, 'Group', 'المجموعة', 'Groep')}: ${row['animal_group']}')),
              Chip(label: Text('${_ant(context, 'Tag', 'التاج', 'Tag')}: ${row['external_id'] ?? '-'}')),
              Chip(label: Text('${_ant(context, 'Age days', 'العمر بالأيام', 'Leeftijd dagen')}: ${row['approximate_age_days'] ?? '-'}')),
              if (row['pregnant'] == true) Chip(label: Text(_ant(context, 'Pregnant', 'حامل', 'Drachtig'))),
            ])),
            if (linkedSensors.isNotEmpty) ...[
              const SizedBox(height: 10),
              Align(alignment: AlignmentDirectional.centerStart, child: Text('${_ant(context, 'Linked sensors', 'الحساسات المرتبطة', 'Gekoppelde sensoren')}: ${linkedSensors.map((e) => e['display_name'] ?? e['device_uid']).join(' • ')}')),
            ],
            if ('${row['admin_notes'] ?? ''}'.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Align(alignment: AlignmentDirectional.centerStart, child: Text('${_ant(context, 'Admin notes', 'ملاحظات الإدارة', 'Adminnotities')}: ${row['admin_notes']}', style: const TextStyle(color: VetColors.muted))),
            ],
            const SizedBox(height: 12),
            Align(alignment: AlignmentDirectional.centerEnd, child: OutlinedButton.icon(onPressed: onEdit, icon: const Icon(Icons.edit_rounded), label: Text(_ant(context, 'Edit animal', 'تعديل الحيوان', 'Dier bewerken')))),
          ],
        ),
      );
}

class _AnimalData {
  const _AnimalData({required this.animals, required this.farms, required this.sensors});
  final List<Map<String, dynamic>> animals;
  final List<Map<String, dynamic>> farms;
  final List<Map<String, dynamic>> sensors;
}

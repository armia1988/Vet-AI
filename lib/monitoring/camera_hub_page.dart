import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/vet_backend.dart';
import 'camera_alert_center_page.dart';
import 'camera_center_page.dart';
import 'camera_device_page.dart';
import 'dahua_thermal_camera_onboarding_page.dart';

class CameraHubPage extends StatefulWidget {
  const CameraHubPage({super.key, required this.farmId});

  final String farmId;

  @override
  State<CameraHubPage> createState() => _CameraHubPageState();
}

class _CameraHubPageState extends State<CameraHubPage> {
  static const _secureStorage = FlutterSecureStorage();

  int tab = 0;
  late Future<List<Map<String, dynamic>>> devicesFuture;

  @override
  void initState() {
    super.initState();
    devicesFuture = _loadDevices();
  }

  String _t(String en, String ar, String nl) {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    if (code == 'ar') return ar;
    if (code == 'nl') return nl;
    return en;
  }

  Future<List<Map<String, dynamic>>> _loadDevices() async {
    final rows = await VetBackend.instance.client
        .from('sensor_devices')
        .select('device_uid,device_type,controller_model,capabilities,active,last_seen_at')
        .eq('farm_id', widget.farmId)
        .eq('active', true);
    return List<Map<String, dynamic>>.from(rows).where((row) {
      final type = (row['device_type'] ?? '').toString();
      return type == 'ip_camera' || type == 'thermal_camera';
    }).toList();
  }

  void _refreshDevices() {
    if (!mounted) return;
    setState(() => devicesFuture = _loadDevices());
  }

  Future<String> _passwordFor(
    Map<String, dynamic> row,
    Map<String, dynamic> caps,
  ) async {
    final uid = (row['device_uid'] ?? '').toString();
    final configuredKey = (caps['credential_key'] ?? '').toString().trim();
    final key = configuredKey.isEmpty ? 'vetai.camera.$uid.password' : configuredKey;
    return await _secureStorage.read(key: key) ?? '';
  }

  int _channelFrom(Map<String, dynamic> caps) {
    final raw = caps['channel'];
    if (raw is int) return raw.clamp(1, 64);
    return int.tryParse((raw ?? '1').toString())?.clamp(1, 64) ?? 1;
  }

  String _streamForChannel(String source, int channel) {
    final value = source.trim();
    if (value.isEmpty) return value;
    final expression = RegExp(r'([?&])channel=\d+', caseSensitive: false);
    if (expression.hasMatch(value)) {
      return value.replaceFirstMapped(
        expression,
        (match) => '${match.group(1)}channel=$channel',
      );
    }
    return value;
  }

  Future<void> _addCamera() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DahuaThermalCameraOnboardingPage(
          farmId: widget.farmId,
          onSaved: _refreshDevices,
        ),
      ),
    );
    if (saved == true) _refreshDevices();
  }

  Future<void> _openCamera(Map<String, dynamic> row) async {
    final caps = Map<String, dynamic>.from(row['capabilities'] as Map? ?? const {});
    final stream = (caps['stream_uri'] ?? '').toString().trim();
    if (stream.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'No verified live stream is stored for this camera yet.',
              'لا يوجد بث مباشر تم التحقق منه لهذه الكاميرا حتى الآن.',
              'Voor deze camera is nog geen geverifieerde livestream opgeslagen.',
            ),
          ),
        ),
      );
      return;
    }

    final password = await _passwordFor(row, caps);
    if (!mounted) return;
    final channel = _channelFrom(caps);
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CameraDevicePage(
          cameraName: (caps['camera_name'] ?? row['controller_model'] ?? 'IP Camera').toString(),
          vendor: (caps['vendor'] ?? 'IP Camera').toString(),
          host: (caps['host'] ?? '').toString(),
          httpPort: int.tryParse((caps['http_port'] ?? '80').toString()) ?? 80,
          rtspPort: int.tryParse((caps['rtsp_port'] ?? '554').toString()) ?? 554,
          username: (caps['username'] ?? '').toString(),
          password: password,
          streamUri: stream,
          subStreamUri: (caps['substream_uri'] ?? '').toString().trim(),
          onvif: caps['onvif'] == true,
          channel: channel,
          onChannelChanged: (nextChannel) => _saveChannel(row, caps, nextChannel),
        ),
      ),
    );
  }

  Future<void> _saveChannel(
    Map<String, dynamic> row,
    Map<String, dynamic> originalCaps,
    int channel,
  ) async {
    final caps = <String, dynamic>{...originalCaps};
    caps['channel'] = channel;
    final stream = (caps['stream_uri'] ?? '').toString();
    final sub = (caps['substream_uri'] ?? '').toString();
    if (stream.isNotEmpty) caps['stream_uri'] = _streamForChannel(stream, channel);
    if (sub.isNotEmpty) caps['substream_uri'] = _streamForChannel(sub, channel);
    await VetBackend.instance.client
        .from('sensor_devices')
        .update({'capabilities': caps})
        .eq('farm_id', widget.farmId)
        .eq('device_uid', (row['device_uid'] ?? '').toString());
    _refreshDevices();
  }

  Future<void> _editCamera(Map<String, dynamic> row) async {
    final caps = Map<String, dynamic>.from(row['capabilities'] as Map? ?? const {});
    final name = TextEditingController(
      text: (caps['camera_name'] ?? row['controller_model'] ?? 'IP Camera').toString(),
    );
    final host = TextEditingController(text: (caps['host'] ?? '').toString());
    final httpPort = TextEditingController(text: (caps['http_port'] ?? 80).toString());
    final rtspPort = TextEditingController(text: (caps['rtsp_port'] ?? 554).toString());
    final username = TextEditingController(text: (caps['username'] ?? '').toString());
    final newPassword = TextEditingController();
    var channel = _channelFrom(caps);

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(_t('Edit camera', 'تعديل الكاميرا', 'Camera bewerken')),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: InputDecoration(labelText: _t('Name', 'الاسم', 'Naam')),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: host,
                    decoration: const InputDecoration(labelText: 'IP / host'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: httpPort,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'HTTP'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: rtspPort,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'RTSP'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: username,
                    decoration: InputDecoration(labelText: _t('Username', 'اسم المستخدم', 'Gebruikersnaam')),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: newPassword,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: _t(
                        'New password (leave empty to keep current)',
                        'كلمة مرور جديدة (اتركها فارغة للإبقاء على الحالية)',
                        'Nieuw wachtwoord (leeg laten om te behouden)',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: Text(_t('Channel', 'القناة', 'Kanaal'))),
                      DropdownButton<int>(
                        value: channel,
                        items: List.generate(
                          16,
                          (index) => DropdownMenuItem(
                            value: index + 1,
                            child: Text('${index + 1}'),
                          ),
                        ),
                        onChanged: (value) {
                          if (value != null) setDialogState(() => channel = value);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_t('Cancel', 'إلغاء', 'Annuleren')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(_t('Save', 'حفظ', 'Opslaan')),
            ),
          ],
        ),
      ),
    );

    if (save == true) {
      final parsedHttp = int.tryParse(httpPort.text.trim());
      final parsedRtsp = int.tryParse(rtspPort.text.trim());
      if (host.text.trim().isEmpty ||
          parsedHttp == null ||
          parsedHttp < 1 ||
          parsedHttp > 65535 ||
          parsedRtsp == null ||
          parsedRtsp < 1 ||
          parsedRtsp > 65535 ||
          username.text.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_t('Check the camera address, ports and username.', 'راجع عنوان الكاميرا والمنافذ واسم المستخدم.', 'Controleer camera-adres, poorten en gebruikersnaam.'))),
          );
        }
      } else {
        final previousHost = (caps['host'] ?? '').toString();
        final previousUser = (caps['username'] ?? '').toString();
        final changedConnection = previousHost != host.text.trim() ||
            previousUser != username.text.trim() ||
            int.tryParse((caps['http_port'] ?? '80').toString()) != parsedHttp ||
            int.tryParse((caps['rtsp_port'] ?? '554').toString()) != parsedRtsp;

        final updatedCaps = <String, dynamic>{
          ...caps,
          'camera_name': name.text.trim().isEmpty ? 'IP Camera' : name.text.trim(),
          'host': host.text.trim(),
          'http_port': parsedHttp,
          'rtsp_port': parsedRtsp,
          'username': username.text.trim(),
          'channel': channel,
          if (changedConnection) 'connection_verified': false,
        };
        final currentStream = (updatedCaps['stream_uri'] ?? '').toString();
        final currentSub = (updatedCaps['substream_uri'] ?? '').toString();
        if (currentStream.isNotEmpty) {
          updatedCaps['stream_uri'] = _streamForChannel(currentStream, channel);
        }
        if (currentSub.isNotEmpty) {
          updatedCaps['substream_uri'] = _streamForChannel(currentSub, channel);
        }

        await VetBackend.instance.client
            .from('sensor_devices')
            .update({'capabilities': updatedCaps})
            .eq('farm_id', widget.farmId)
            .eq('device_uid', (row['device_uid'] ?? '').toString());

        if (newPassword.text.isNotEmpty) {
          final uid = (row['device_uid'] ?? '').toString();
          final configuredKey = (caps['credential_key'] ?? '').toString().trim();
          final key = configuredKey.isEmpty ? 'vetai.camera.$uid.password' : configuredKey;
          await _secureStorage.write(key: key, value: newPassword.text);
        }
        _refreshDevices();
      }
    }

    name.dispose();
    host.dispose();
    httpPort.dispose();
    rtspPort.dispose();
    username.dispose();
    newPassword.dispose();
  }

  Future<void> _deleteCamera(Map<String, dynamic> row) async {
    final caps = Map<String, dynamic>.from(row['capabilities'] as Map? ?? const {});
    final displayName = (caps['camera_name'] ?? row['controller_model'] ?? 'IP Camera').toString();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('Remove camera?', 'حذف الكاميرا؟', 'Camera verwijderen?')),
        content: Text(
          _t(
            'Remove "$displayName" from Vet AI? The camera itself will not be reset.',
            'حذف "$displayName" من Vet AI؟ لن يتم عمل إعادة ضبط للكاميرا نفسها.',
            '"$displayName" uit Vet AI verwijderen? De camera zelf wordt niet gereset.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_t('Cancel', 'إلغاء', 'Annuleren')),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_t('Remove', 'حذف', 'Verwijderen')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final uid = (row['device_uid'] ?? '').toString();
    final configuredKey = (caps['credential_key'] ?? '').toString().trim();
    final key = configuredKey.isEmpty ? 'vetai.camera.$uid.password' : configuredKey;
    await VetBackend.instance.client
        .from('sensor_devices')
        .delete()
        .eq('farm_id', widget.farmId)
        .eq('device_uid', uid);
    await _secureStorage.delete(key: key);
    _refreshDevices();
  }

  Widget _devicesTab() {
    return RefreshIndicator(
      onRefresh: () async => _refreshDevices(),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: devicesFuture,
        builder: (context, snapshot) {
          final devices = snapshot.data ?? const <Map<String, dynamic>>[];
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _t('My cameras', 'الكاميرات', 'Mijn camera\'s'),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _addCamera,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(_t('Add', 'إضافة', 'Toevoegen')),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _t(
                  'Add or discover a camera once. Live view, PTZ, snapshots, recording, events and health are managed here.',
                  'أضف أو اكتشف الكاميرا مرة واحدة. العرض المباشر وPTZ والصور والتسجيل والأحداث وفحص الحالة كلها من هنا.',
                  'Voeg of ontdek een camera één keer. Livebeeld, PTZ, foto\'s, opname, gebeurtenissen en statusbeheer staan hier.',
                ),
              ),
              const SizedBox(height: 18),
              if (snapshot.connectionState != ConnectionState.done)
                const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
              if (snapshot.hasError)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        const Icon(Icons.cloud_off_rounded, size: 34),
                        const SizedBox(height: 10),
                        Text(_t('Could not load cameras.', 'تعذر تحميل الكاميرات.', 'Camera\'s konden niet worden geladen.')),
                        const SizedBox(height: 8),
                        OutlinedButton(onPressed: _refreshDevices, child: Text(_t('Retry', 'إعادة المحاولة', 'Opnieuw'))),
                      ],
                    ),
                  ),
                ),
              if (!snapshot.hasError && snapshot.connectionState == ConnectionState.done && devices.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const Icon(Icons.videocam_off_outlined, size: 42),
                        const SizedBox(height: 12),
                        Text(
                          _t('No cameras added yet.', 'لم تتم إضافة كاميرات بعد.', 'Nog geen camera\'s toegevoegd.'),
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _addCamera,
                          icon: const Icon(Icons.add_a_photo_outlined),
                          label: Text(_t('Add / discover camera', 'إضافة / اكتشاف كاميرا', 'Camera toevoegen / ontdekken')),
                        ),
                      ],
                    ),
                  ),
                ),
              for (final row in devices) _cameraCard(row),
            ],
          );
        },
      ),
    );
  }

  Widget _cameraCard(Map<String, dynamic> row) {
    final caps = Map<String, dynamic>.from(row['capabilities'] as Map? ?? const {});
    final name = (caps['camera_name'] ?? row['controller_model'] ?? 'IP Camera').toString();
    final vendor = (caps['vendor'] ?? 'IP Camera').toString();
    final model = (row['controller_model'] ?? '').toString();
    final host = (caps['host'] ?? '').toString();
    final stream = (caps['stream_uri'] ?? '').toString().trim();
    final connected = caps['connection_verified'] == true && stream.isNotEmpty;
    final channel = _channelFrom(caps);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 24,
                  child: Icon(connected ? Icons.videocam_rounded : Icons.videocam_off_rounded),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                      const SizedBox(height: 4),
                      Text([vendor, model, host].where((value) => value.trim().isNotEmpty).join(' • ')),
                      const SizedBox(height: 5),
                      Text('${_t('Channel', 'القناة', 'Kanaal')} $channel'),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          Icon(
                            connected ? Icons.circle : Icons.error_outline_rounded,
                            size: 14,
                            color: connected ? Colors.green : Colors.orange,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              connected
                                  ? _t('Ready for live view', 'جاهزة للعرض المباشر', 'Klaar voor livebeeld')
                                  : _t('Connection needs verification', 'الاتصال يحتاج تحقق', 'Verbinding moet worden gecontroleerd'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') _editCamera(row);
                    if (value == 'delete') _deleteCamera(row);
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        leading: const Icon(Icons.edit_outlined),
                        title: Text(_t('Edit', 'تعديل', 'Bewerken')),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: const Icon(Icons.delete_outline_rounded),
                        title: Text(_t('Remove', 'حذف', 'Verwijderen')),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: stream.isEmpty ? null : () => _openCamera(row),
                    icon: const Icon(Icons.play_circle_fill_rounded),
                    label: Text(_t('Open', 'فتح', 'Openen')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => tab = 1),
                    icon: const Icon(Icons.grid_view_rounded),
                    label: Text(_t('Wall', 'الشاشات', 'Wall')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingsTab() {
    Widget item(IconData icon, String title, String body) => Card(
          child: ListTile(
            leading: Icon(icon),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(body),
          ),
        );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          _t('Camera settings', 'إعدادات الكاميرات', 'Camera-instellingen'),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        item(
          Icons.lock_outline_rounded,
          _t('Secure credentials', 'بيانات دخول آمنة', 'Veilige inloggegevens'),
          _t(
            'Camera passwords stay in secure device storage and are not written to Supabase.',
            'كلمات مرور الكاميرات تبقى في التخزين الآمن على الجهاز ولا تُكتب في Supabase.',
            'Camerawachtwoorden blijven in beveiligde apparaatopslag en worden niet naar Supabase geschreven.',
          ),
        ),
        item(
          Icons.lan_outlined,
          _t('Direct Dahua connection', 'اتصال Dahua مباشر', 'Directe Dahua-verbinding'),
          _t(
            'Standard Dahua cameras use native authenticated HTTP/CGI plus RTSP. ONVIF is not required.',
            'كاميرات Dahua العادية تستخدم HTTP/CGI الأصلي مع RTSP ولا تحتاج ONVIF.',
            'Standaard Dahua-camera\'s gebruiken native HTTP/CGI plus RTSP. ONVIF is niet vereist.',
          ),
        ),
        item(
          Icons.photo_camera_back_outlined,
          _t('Snapshots and recordings', 'الصور والتسجيلات', 'Foto\'s en opnamen'),
          _t(
            'Snapshots and manual recordings are saved locally on the device running Vet AI.',
            'الصور والتسجيلات اليدوية تُحفظ محليًا على الجهاز الذي يشغل Vet AI.',
            'Momentopnamen en handmatige opnamen worden lokaal opgeslagen op het apparaat met Vet AI.',
          ),
        ),
        item(
          Icons.view_stream_outlined,
          _t('Multi-channel', 'قنوات متعددة', 'Meerdere kanalen'),
          _t(
            'Dahua channels can be selected per camera and the selected channel is saved for the live wall.',
            'يمكن اختيار قناة Dahua لكل كاميرا ويتم حفظ القناة المختارة للعرض المباشر.',
            'Dahua-kanalen kunnen per camera worden gekozen en worden opgeslagen voor de livewall.',
          ),
        ),
        item(
          Icons.cloud_off_outlined,
          _t('Remote access', 'الوصول من خارج الشبكة', 'Externe toegang'),
          _t(
            'Vendor P2P/cloud and recorder playback are separate transports and are not shown as connected until a real remote transport is configured.',
            'P2P/Cloud وتشغيل تسجيلات المسجل وسائل اتصال منفصلة ولن تظهر كمتصلة قبل إعداد اتصال خارجي حقيقي.',
            'Vendor-P2P/cloud en recorderweergave zijn aparte verbindingen en worden pas als verbonden getoond wanneer een echte externe transportlaag is ingesteld.',
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _devicesTab(),
      CameraCenterPage(farmId: widget.farmId),
      CameraAlertCenterPage(farmId: widget.farmId),
      _settingsTab(),
    ];
    return Scaffold(
      appBar: tab == 1 || tab == 2
          ? null
          : AppBar(
              title: Text(_t('Camera Center', 'مركز الكاميرات', 'Cameracentrum')),
              actions: [
                if (tab == 0)
                  IconButton(
                    onPressed: _refreshDevices,
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: _t('Refresh', 'تحديث', 'Vernieuwen'),
                  ),
              ],
            ),
      body: IndexedStack(index: tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) {
          setState(() => tab = value);
          if (value == 0) _refreshDevices();
        },
        destinations: [
          NavigationDestination(icon: const Icon(Icons.videocam_outlined), selectedIcon: const Icon(Icons.videocam_rounded), label: _t('Devices', 'الأجهزة', 'Apparaten')),
          NavigationDestination(icon: const Icon(Icons.grid_view_outlined), selectedIcon: const Icon(Icons.grid_view_rounded), label: _t('Live', 'مباشر', 'Live')),
          NavigationDestination(icon: const Icon(Icons.notifications_none_rounded), selectedIcon: const Icon(Icons.notifications_active_rounded), label: _t('Events', 'الأحداث', 'Gebeurtenissen')),
          NavigationDestination(icon: const Icon(Icons.settings_outlined), selectedIcon: const Icon(Icons.settings_rounded), label: _t('Settings', 'الإعدادات', 'Instellingen')),
        ],
      ),
      floatingActionButton: tab == 0
          ? FloatingActionButton(
              onPressed: _addCamera,
              tooltip: _t('Add camera', 'إضافة كاميرا', 'Camera toevoegen'),
              child: const Icon(Icons.add_rounded),
            )
          : null,
    );
  }
}

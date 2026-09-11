import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/vet_backend.dart';
import 'camera_alert_center_page.dart';
import 'camera_center_page.dart';
import 'camera_live_view_page.dart';
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
        .select('device_uid,device_type,controller_model,capabilities,active')
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

  Future<void> _openLive(Map<String, dynamic> row) async {
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
    final uid = (row['device_uid'] ?? '').toString();
    final configuredKey = (caps['credential_key'] ?? '').toString().trim();
    final key = configuredKey.isEmpty ? 'vetai.camera.$uid.password' : configuredKey;
    final password = await _secureStorage.read(key: key) ?? '';
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CameraLiveViewPage(
          streamUri: stream,
          username: (caps['username'] ?? '').toString(),
          password: password,
          cameraName: (caps['camera_name'] ?? row['controller_model'] ?? 'IP Camera').toString(),
        ),
      ),
    );
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
                  'Add a camera once, then use Live, Events and camera controls from this center.',
                  'أضف الكاميرا مرة واحدة، وبعدها استخدم العرض المباشر والأحداث والتحكم من هذا المركز.',
                  'Voeg een camera één keer toe en gebruik daarna Live, Gebeurtenissen en camerabediening vanuit dit centrum.',
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
                          label: Text(_t('Add camera', 'إضافة كاميرا', 'Camera toevoegen')),
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
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          Icon(connected ? Icons.circle : Icons.error_outline_rounded, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            connected
                                ? _t('Ready for live view', 'جاهزة للعرض المباشر', 'Klaar voor livebeeld')
                                : _t('Connection needs verification', 'الاتصال يحتاج تحقق', 'Verbinding moet worden gecontroleerd'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: stream.isEmpty ? null : () => _openLive(row),
                    icon: const Icon(Icons.play_circle_fill_rounded),
                    label: Text(_t('Live', 'مباشر', 'Live')),
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
            'Camera passwords stay in the secure storage on this device and are not written to Supabase.',
            'كلمات مرور الكاميرات تبقى في التخزين الآمن على هذا الجهاز ولا تُكتب في Supabase.',
            'Camerawachtwoorden blijven in de beveiligde opslag op dit apparaat en worden niet naar Supabase geschreven.',
          ),
        ),
        item(
          Icons.lan_outlined,
          _t('Direct local connection', 'اتصال محلي مباشر', 'Directe lokale verbinding'),
          _t(
            'Dahua can use its native authenticated device API and direct RTSP stream without requiring ONVIF.',
            'كاميرات Dahua يمكنها استخدام واجهة الجهاز الأصلية والبث RTSP مباشرة بدون اشتراط ONVIF.',
            'Dahua kan de eigen geauthenticeerde apparaat-API en directe RTSP-stream gebruiken zonder ONVIF te vereisen.',
          ),
        ),
        item(
          Icons.cloud_off_outlined,
          _t('Remote access', 'الوصول من خارج الشبكة', 'Externe toegang'),
          _t(
            'Vendor P2P/cloud and recorder playback are separate transports. They are not presented as connected until a real transport is configured.',
            'P2P/Cloud الخاص بالشركة وتشغيل تسجيلات المسجل هما وسائل اتصال منفصلة، ولن نعرضهما كأنهما يعملان قبل إعداد اتصال حقيقي.',
            'Vendor-P2P/cloud en recorderweergave zijn aparte verbindingen en worden pas als verbonden getoond wanneer een echte transportlaag is ingesteld.',
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

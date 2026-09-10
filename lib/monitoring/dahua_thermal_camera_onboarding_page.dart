import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../i18n/vet_locale.dart';
import '../services/vet_backend.dart';
import '../theme/app_theme.dart';
import 'camera_connection_service.dart';
import 'camera_stream_profile_service.dart';
import 'onvif_discovery_page.dart';
import 'camera_live_view_page.dart';

String _dt(BuildContext context, String en, String ar, String nl) =>
    VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

class DahuaThermalCameraOnboardingPage extends StatefulWidget {
  const DahuaThermalCameraOnboardingPage({
    super.key,
    required this.farmId,
    this.onSaved,
  });

  final String farmId;
  final VoidCallback? onSaved;

  @override
  State<DahuaThermalCameraOnboardingPage> createState() =>
      _DahuaThermalCameraOnboardingPageState();
}

class _DahuaThermalCameraOnboardingPageState
    extends State<DahuaThermalCameraOnboardingPage> {
  static const _secureStorage = FlutterSecureStorage();
  static const _connector = CameraConnectionService();

  final name = TextEditingController(text: 'IP Camera');
  final manufacturer = TextEditingController();
  final host = TextEditingController();
  final port = TextEditingController(text: '80');
  final rtspPort = TextEditingController(text: '554');
  final username = TextEditingController(text: 'admin');
  final password = TextEditingController();
  final model = TextEditingController();
  final serial = TextEditingController();

  bool passwordVisible = false;
  bool busy = false;
  bool testedSuccessfully = false;
  String protocol = 'ONVIF + RTSP';
  String cameraType = 'standard';
  String purpose = 'general_monitoring';
  String? discoveredStreamUri;
  String? discoveredSubStreamUri;
  int discoveredProfileCount = 0;
  String? testDetails;

  @override
  void initState() {
    super.initState();
    for (final controller in [host, port, rtspPort, username, password]) {
      controller.addListener(_invalidateTest);
    }
  }

  void _invalidateTest() {
    if (!testedSuccessfully && discoveredStreamUri == null && testDetails == null) return;
    if (!mounted) return;
    setState(() {
      testedSuccessfully = false;
      discoveredStreamUri = null;
      discoveredSubStreamUri = null;
      discoveredProfileCount = 0;
      testDetails = null;
    });
  }

  @override
  void dispose() {
    name.dispose();
    manufacturer.dispose();
    host.dispose();
    port.dispose();
    rtspPort.dispose();
    username.dispose();
    password.dispose();
    model.dispose();
    serial.dispose();
    super.dispose();
  }

  bool _validHost(String value) {
    final v = value.trim();
    if (v.isEmpty || v.contains(' ')) return false;
    final ipv4 = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
    if (ipv4.hasMatch(v)) {
      return v.split('.').every((part) {
        final n = int.tryParse(part);
        return n != null && n >= 0 && n <= 255;
      });
    }
    return RegExp(r'^[a-zA-Z0-9.-]+$').hasMatch(v);
  }

  int? _validPort(String value) {
    final p = int.tryParse(value.trim());
    return p != null && p > 0 && p <= 65535 ? p : null;
  }

  ({String host, int httpPort, int rtspPort})? _validatedEndpoint() {
    final cameraHost = host.text.trim();
    final httpPort = _validPort(port.text);
    final streamPort = _validPort(rtspPort.text);
    if (!_validHost(cameraHost) || httpPort == null || streamPort == null) {
      _snack(
        _dt(
          context,
          'Enter a valid camera IP/hostname and ports.',
          'اكتب IP أو اسم شبكة صحيح للكاميرا وأرقام المنافذ.',
          'Vul een geldig camera-IP/hostnaam en geldige poorten in.',
        ),
        true,
      );
      return null;
    }
    if (username.text.trim().isEmpty) {
      _snack(
        _dt(
          context,
          'Enter the camera username.',
          'اكتب اسم مستخدم الكاميرا.',
          'Vul de gebruikersnaam van de camera in.',
        ),
        true,
      );
      return null;
    }
    return (host: cameraHost, httpPort: httpPort, rtspPort: streamPort);
  }

  Future<void> _discoverCamera() async {
    FocusScope.of(context).unfocus();
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const OnvifDiscoveryPage()),
    );
    if (!mounted || result == null) return;
    final discoveredHost = (result['host'] ?? '').toString().trim();
    final discoveredPort = result['httpPort'];
    final discoveredName = (result['name'] ?? '').toString().trim();
    final discoveredHardware = (result['hardware'] ?? '').toString().trim();
    setState(() {
      if (discoveredHost.isNotEmpty) host.text = discoveredHost;
      if (discoveredPort is int && discoveredPort > 0) port.text = '$discoveredPort';
      if (discoveredName.isNotEmpty && name.text.trim() == 'IP Camera') name.text = discoveredName;
      if (discoveredHardware.isNotEmpty && model.text.trim().isEmpty) model.text = discoveredHardware;
      testedSuccessfully = false;
      discoveredStreamUri = null;
      discoveredSubStreamUri = null;
      discoveredProfileCount = 0;
      testDetails = null;
    });
  }

  Future<void> _testConnection() async {
    FocusScope.of(context).unfocus();
    final endpoint = _validatedEndpoint();
    if (endpoint == null) return;

    setState(() {
      busy = true;
      testedSuccessfully = false;
      discoveredStreamUri = null;
      discoveredSubStreamUri = null;
      discoveredProfileCount = 0;
      testDetails = null;
    });

    try {
      final result = await _connector.test(
        host: endpoint.host,
        httpPort: endpoint.httpPort,
        rtspPort: endpoint.rtspPort,
        username: username.text.trim(),
        password: password.text,
        useOnvif: protocol.contains('ONVIF'),
        useRtsp: protocol.contains('RTSP'),
      );
      if (!mounted) return;

      CameraStreamProfiles? discoveredProfiles;
      if (result.success && protocol.contains('ONVIF')) {
        try {
          discoveredProfiles = await CameraStreamProfileService(
            host: endpoint.host,
            httpPort: endpoint.httpPort,
            username: username.text.trim(),
            password: password.text,
          ).discover();
        } catch (_) {
          // A verified camera remains usable even when it exposes only one
          // stream or refuses optional profile enumeration.
        }
      }

      final info = result.deviceInformation ?? const <String, String>{};
      if (manufacturer.text.trim().isEmpty && (info['Manufacturer'] ?? '').isNotEmpty) {
        manufacturer.text = info['Manufacturer']!;
      }
      if (model.text.trim().isEmpty && (info['Model'] ?? '').isNotEmpty) {
        model.text = info['Model']!;
      }
      if (serial.text.trim().isEmpty && (info['SerialNumber'] ?? '').isNotEmpty) {
        serial.text = info['SerialNumber']!;
      }

      setState(() {
        testedSuccessfully = result.success;
        discoveredStreamUri = discoveredProfiles?.mainStreamUri ?? result.streamUri;
        discoveredSubStreamUri = discoveredProfiles?.subStreamUri;
        discoveredProfileCount = discoveredProfiles?.profiles.length ?? 0;
        testDetails = result.message;
      });

      if (result.success) {
        _snack(
          _dt(
            context,
            'Camera connection verified successfully.',
            'تم التحقق من الاتصال بالكاميرا بنجاح.',
            'De cameraverbinding is succesvol gecontroleerd.',
          ),
          false,
        );
      } else {
        _snack(
          _dt(
            context,
            'The camera did not pass the selected connection tests.',
            'الكاميرا لم تنجح في اختبارات الاتصال المحددة.',
            'De camera heeft de gekozen verbindingstests niet doorstaan.',
          ),
          true,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => testDetails = e.toString());
      _snack(
        _dt(
          context,
          'Could not connect to the camera. Check network, ports and credentials.',
          'تعذر الاتصال بالكاميرا. تأكد من الشبكة والمنافذ وبيانات الدخول.',
          'Kan geen verbinding maken met de camera. Controleer netwerk, poorten en inloggegevens.',
        ),
        true,
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final endpoint = _validatedEndpoint();
    if (endpoint == null) return;
    if (!testedSuccessfully) {
      _snack(
        _dt(
          context,
          'Test the real camera connection successfully before adding it.',
          'اختبر الاتصال الحقيقي بالكاميرا بنجاح قبل إضافتها.',
          'Test eerst de echte cameraverbinding voordat je de camera toevoegt.',
        ),
        true,
      );
      return;
    }

    setState(() => busy = true);
    try {
      final idPart = serial.text.trim().isNotEmpty
          ? serial.text.trim()
          : '${endpoint.host}:${endpoint.httpPort}';
      final safeFarmId = widget.farmId.toLowerCase();
      final vendor = manufacturer.text.trim().isEmpty
          ? 'Generic'
          : manufacturer.text.trim();
      final deviceUid = 'camera-$safeFarmId-${idPart.toLowerCase()}';
      final isThermal = cameraType == 'thermal';
      final secureKey = 'vetai.camera.$deviceUid.password';

      await _secureStorage.write(key: secureKey, value: password.text);

      await VetBackend.instance.client.from('sensor_devices').upsert(
        {
          'farm_id': widget.farmId,
          'device_uid': deviceUid,
          'device_type': isThermal ? 'thermal_camera' : 'ip_camera',
          'controller_model': model.text.trim().isEmpty
              ? '$vendor ${isThermal ? 'Thermal Camera' : 'IP Camera'}'
              : model.text.trim(),
          'active': true,
          'capabilities': {
            'vendor': vendor,
            'camera_name': name.text.trim(),
            'camera_type': cameraType,
            'host': endpoint.host,
            'http_port': endpoint.httpPort,
            'rtsp_port': endpoint.rtspPort,
            'username': username.text.trim(),
            'protocol': protocol,
            'purpose': purpose,
            'thermal': isThermal,
            'onvif': protocol.contains('ONVIF'),
            'rtsp': protocol.contains('RTSP'),
            'connection_verified': true,
            'stream_uri': discoveredStreamUri,
            'substream_uri': discoveredSubStreamUri,
            'stream_profile_count': discoveredProfileCount,
            'adaptive_wall_streams': discoveredSubStreamUri != null,
            'credentials_storage': 'platform_secure_storage',
            'credential_key': secureKey,
          },
        },
        onConflict: 'device_uid',
      );
      if (!mounted) return;
      widget.onSaved?.call();
      _snack(
        _dt(
          context,
          'Camera connected and added to Vet AI.',
          'تم توصيل الكاميرا وإضافتها إلى Vet AI.',
          'Camera is verbonden en toegevoegd aan Vet AI.',
        ),
        false,
      );
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      _snack(
        _dt(
          context,
          'Could not save the camera. Check your farm permissions and try again.',
          'تعذر حفظ الكاميرا. تأكد من صلاحيات المزرعة وحاول مرة أخرى.',
          'De camera kon niet worden opgeslagen. Controleer de boerderijrechten en probeer opnieuw.',
        ),
        true,
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _snack(String text, bool error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor:
            error ? Theme.of(context).colorScheme.error : VetColors.surface2,
      ),
    );
  }

  Widget _field(TextEditingController controller, String label, IconData icon,
      {TextInputType? keyboardType, String? hintText}) {
    return TextField(
      controller: controller,
      enabled: !busy,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: Icon(icon),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_dt(context, 'Add camera', 'إضافة كاميرا', 'Camera toevoegen')),
      ),
      floatingActionButton: testedSuccessfully && discoveredStreamUri != null
          ? FloatingActionButton.extended(
              onPressed: busy
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CameraLiveViewPage(
                            streamUri: discoveredStreamUri!,
                            username: username.text.trim(),
                            password: password.text,
                            cameraName: name.text.trim().isEmpty ? 'IP Camera' : name.text.trim(),
                          ),
                        ),
                      ),
              icon: const Icon(Icons.play_circle_fill_rounded),
              label: Text(_dt(context, 'Live view', 'عرض مباشر', 'Livebeeld')),
            )
          : null,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CircleAvatar(
                      backgroundColor: VetColors.softGreen,
                      child: Icon(Icons.videocam_rounded, color: VetColors.green),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _dt(context, 'Real IP camera connection', 'اتصال حقيقي بكاميرا IP', 'Echte IP-cameraverbinding'),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _dt(
                              context,
                              'Vet AI tests ONVIF and/or RTSP against the camera before it can be added.',
                              'يقوم Vet AI باختبار ONVIF و/أو RTSP مع الكاميرا فعليًا قبل السماح بإضافتها.',
                              'Vet AI test ONVIF en/of RTSP echt met de camera voordat deze kan worden toegevoegd.',
                            ),
                            style: const TextStyle(color: VetColors.muted, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            _field(name, _dt(context, 'Camera name', 'اسم الكاميرا', 'Cameranaam'), Icons.videocam_outlined),
            const SizedBox(height: 12),
            _field(
              manufacturer,
              _dt(context, 'Manufacturer (optional)', 'الشركة المصنعة (اختياري)', 'Fabrikant (optioneel)'),
              Icons.factory_outlined,
              hintText: 'Dahua, Hikvision, Uniview, Axis…',
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: cameraType,
              decoration: InputDecoration(
                labelText: _dt(context, 'Camera type', 'نوع الكاميرا', 'Cameratype'),
                prefixIcon: const Icon(Icons.category_outlined),
              ),
              items: [
                DropdownMenuItem(value: 'standard', child: Text(_dt(context, 'Standard IP camera', 'كاميرا IP عادية', 'Standaard IP-camera'))),
                DropdownMenuItem(value: 'thermal', child: Text(_dt(context, 'Thermal camera', 'كاميرا حرارية', 'Thermische camera'))),
              ],
              onChanged: busy ? null : (v) => setState(() => cameraType = v ?? cameraType),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: busy ? null : _discoverCamera,
                icon: const Icon(Icons.radar_rounded),
                label: Text(_dt(context, 'Find cameras', 'البحث عن الكاميرات', 'Camera\'s zoeken')),
              ),
            ),
            const SizedBox(height: 12),
            _field(host, _dt(context, 'IP address / hostname', 'IP / اسم الشبكة', 'IP-adres / hostnaam'), Icons.lan_outlined, keyboardType: TextInputType.url, hintText: '192.168.1.120'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _field(port, _dt(context, 'HTTP port', 'منفذ HTTP', 'HTTP-poort'), Icons.http_rounded, keyboardType: TextInputType.number)),
                const SizedBox(width: 12),
                Expanded(child: _field(rtspPort, _dt(context, 'RTSP port', 'منفذ RTSP', 'RTSP-poort'), Icons.settings_ethernet_rounded, keyboardType: TextInputType.number)),
              ],
            ),
            const SizedBox(height: 12),
            _field(username, _dt(context, 'Username', 'اسم المستخدم', 'Gebruikersnaam'), Icons.person_outline_rounded),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              enabled: !busy,
              obscureText: !passwordVisible,
              decoration: InputDecoration(
                labelText: _dt(context, 'Password', 'كلمة المرور', 'Wachtwoord'),
                helperText: _dt(context, 'Saved only in secure device storage', 'تُحفظ فقط في التخزين الآمن على الجهاز', 'Alleen opgeslagen in beveiligde apparaatopslag'),
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  onPressed: busy ? null : () => setState(() => passwordVisible = !passwordVisible),
                  icon: Icon(passwordVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _field(model, _dt(context, 'Model (optional)', 'الموديل (اختياري)', 'Model (optioneel)'), Icons.memory_rounded),
            const SizedBox(height: 12),
            _field(serial, _dt(context, 'Serial number (optional)', 'السيريال (اختياري)', 'Serienummer (optioneel)'), Icons.qr_code_2_rounded),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: protocol,
              decoration: InputDecoration(
                labelText: _dt(context, 'Connection', 'طريقة الاتصال', 'Verbinding'),
                prefixIcon: const Icon(Icons.settings_input_antenna_rounded),
              ),
              items: const [
                DropdownMenuItem(value: 'ONVIF + RTSP', child: Text('ONVIF + RTSP')),
                DropdownMenuItem(value: 'ONVIF', child: Text('ONVIF')),
                DropdownMenuItem(value: 'RTSP', child: Text('RTSP')),
              ],
              onChanged: busy
                  ? null
                  : (v) => setState(() {
                        protocol = v ?? protocol;
                        testedSuccessfully = false;
                        discoveredStreamUri = null;
                        testDetails = null;
                      }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: purpose,
              decoration: InputDecoration(
                labelText: _dt(context, 'Monitoring purpose', 'استخدام الكاميرا', 'Doel van monitoring'),
                prefixIcon: const Icon(Icons.monitor_heart_outlined),
              ),
              items: [
                DropdownMenuItem(value: 'general_monitoring', child: Text(_dt(context, 'General monitoring', 'مراقبة عامة', 'Algemene monitoring'))),
                DropdownMenuItem(value: 'animal_monitoring', child: Text(_dt(context, 'Animal monitoring', 'مراقبة الحيوانات', 'Diermonitoring'))),
                DropdownMenuItem(value: 'barn_monitoring', child: Text(_dt(context, 'Barn / area monitoring', 'مراقبة الحظيرة / المكان', 'Stal / ruimtemonitoring'))),
                DropdownMenuItem(value: 'temperature_monitoring', child: Text(_dt(context, 'Temperature monitoring', 'مراقبة الحرارة', 'Temperatuurmonitoring'))),
              ],
              onChanged: busy ? null : (v) => setState(() => purpose = v ?? purpose),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: busy ? null : _testConnection,
              icon: busy
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(testedSuccessfully ? Icons.verified_rounded : Icons.network_check_rounded),
              label: Text(_dt(
                context,
                testedSuccessfully ? 'Connection verified' : 'Test camera connection',
                testedSuccessfully ? 'تم التحقق من الاتصال' : 'اختبار اتصال الكاميرا',
                testedSuccessfully ? 'Verbinding gecontroleerd' : 'Cameraverbinding testen',
              )),
            ),
            if (testedSuccessfully || testDetails != null || discoveredStreamUri != null) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        testedSuccessfully ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                        color: testedSuccessfully ? VetColors.green : Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          testedSuccessfully
                              ? _dt(context, 'Real camera connection succeeded.${discoveredStreamUri == null ? '' : '\nRTSP stream discovered automatically.'}', 'نجح الاتصال الحقيقي بالكاميرا.${discoveredStreamUri == null ? '' : '\nتم اكتشاف رابط RTSP تلقائيًا.'}', 'Echte cameraverbinding gelukt.${discoveredStreamUri == null ? '' : '\nRTSP-stream automatisch gevonden.'}')
                              : (testDetails ?? _dt(context, 'Connection failed.', 'فشل الاتصال.', 'Verbinding mislukt.')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: busy || !testedSuccessfully ? null : _save,
              icon: const Icon(Icons.add_link_rounded),
              label: Text(_dt(context, 'Add connected camera', 'إضافة الكاميرا المتصلة', 'Verbonden camera toevoegen')),
            ),
            const SizedBox(height: 10),
            Text(
              _dt(
                context,
                'The password is never written to Supabase. It is kept in platform secure storage for future camera sessions.',
                'لن تتم كتابة كلمة المرور في Supabase. تُحفظ في التخزين الآمن للجهاز لاستخدام الكاميرا لاحقًا.',
                'Het wachtwoord wordt nooit naar Supabase geschreven en blijft in beveiligde apparaatopslag.',
              ),
              style: const TextStyle(fontSize: 12, color: VetColors.muted, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}

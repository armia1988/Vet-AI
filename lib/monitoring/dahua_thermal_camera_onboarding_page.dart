import 'package:flutter/material.dart';

import '../i18n/vet_locale.dart';
import '../services/vet_backend.dart';
import '../theme/app_theme.dart';

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
  String protocol = 'ONVIF + RTSP';
  String cameraType = 'standard';
  String purpose = 'general_monitoring';

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

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
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
      return;
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
      return;
    }

    setState(() => busy = true);
    try {
      final idPart = serial.text.trim().isNotEmpty
          ? serial.text.trim()
          : '$cameraHost:$httpPort';
      final safeFarmId = widget.farmId.toLowerCase();
      final vendor = manufacturer.text.trim().isEmpty
          ? 'Generic'
          : manufacturer.text.trim();
      final deviceUid = 'camera-$safeFarmId-${idPart.toLowerCase()}';
      final isThermal = cameraType == 'thermal';

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
            'host': cameraHost,
            'http_port': httpPort,
            'rtsp_port': streamPort,
            'username': username.text.trim(),
            'protocol': protocol,
            'purpose': purpose,
            'thermal': isThermal,
            'onvif': protocol.contains('ONVIF'),
            'rtsp': protocol.contains('RTSP'),
            'credentials_storage': 'password_not_stored',
          },
        },
        onConflict: 'device_uid',
      );
      if (!mounted) return;
      widget.onSaved?.call();
      _snack(
        _dt(
          context,
          'Camera added to Vet AI.',
          'تمت إضافة الكاميرا إلى Vet AI.',
          'Camera is toegevoegd aan Vet AI.',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_dt(context, 'Add camera', 'إضافة كاميرا', 'Camera toevoegen')),
      ),
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
                            _dt(context, 'IP Camera', 'كاميرا IP', 'IP-camera'),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _dt(
                              context,
                              'Works with compatible cameras using ONVIF and/or RTSP, including Dahua, Hikvision and other IP camera brands.',
                              'تعمل مع الكاميرات المتوافقة عبر ONVIF و/أو RTSP، بما فيها Dahua وHikvision وغيرها من كاميرات IP.',
                              'Werkt met compatibele camera’s via ONVIF en/of RTSP, waaronder Dahua, Hikvision en andere IP-cameramerken.',
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
            TextField(
              controller: name,
              enabled: !busy,
              decoration: InputDecoration(
                labelText: _dt(context, 'Camera name', 'اسم الكاميرا', 'Cameranaam'),
                prefixIcon: const Icon(Icons.videocam_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: manufacturer,
              enabled: !busy,
              decoration: InputDecoration(
                labelText: _dt(context, 'Manufacturer (optional)', 'الشركة المصنعة (اختياري)', 'Fabrikant (optioneel)'),
                hintText: 'Dahua, Hikvision, Uniview, Axis…',
                prefixIcon: const Icon(Icons.factory_outlined),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: cameraType,
              decoration: InputDecoration(
                labelText: _dt(context, 'Camera type', 'نوع الكاميرا', 'Cameratype'),
                prefixIcon: const Icon(Icons.category_outlined),
              ),
              items: [
                DropdownMenuItem(
                  value: 'standard',
                  child: Text(_dt(context, 'Standard IP camera', 'كاميرا IP عادية', 'Standaard IP-camera')),
                ),
                DropdownMenuItem(
                  value: 'thermal',
                  child: Text(_dt(context, 'Thermal camera', 'كاميرا حرارية', 'Thermische camera')),
                ),
              ],
              onChanged: busy ? null : (v) => setState(() => cameraType = v ?? cameraType),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: host,
              enabled: !busy,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: _dt(context, 'IP address / hostname', 'IP / اسم الشبكة', 'IP-adres / hostnaam'),
                hintText: '192.168.1.120',
                prefixIcon: const Icon(Icons.lan_outlined),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: port,
                    enabled: !busy,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: _dt(context, 'HTTP port', 'منفذ HTTP', 'HTTP-poort'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: rtspPort,
                    enabled: !busy,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: _dt(context, 'RTSP port', 'منفذ RTSP', 'RTSP-poort'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: username,
              enabled: !busy,
              decoration: InputDecoration(
                labelText: _dt(context, 'Username', 'اسم المستخدم', 'Gebruikersnaam'),
                prefixIcon: const Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              enabled: !busy,
              obscureText: !passwordVisible,
              decoration: InputDecoration(
                labelText: _dt(context, 'Password (not stored)', 'كلمة المرور (لن يتم تخزينها)', 'Wachtwoord (niet opgeslagen)'),
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => passwordVisible = !passwordVisible),
                  icon: Icon(passwordVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: model,
              enabled: !busy,
              decoration: InputDecoration(
                labelText: _dt(context, 'Model (optional)', 'الموديل (اختياري)', 'Model (optioneel)'),
                prefixIcon: const Icon(Icons.memory_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: serial,
              enabled: !busy,
              decoration: InputDecoration(
                labelText: _dt(context, 'Serial number (optional)', 'السيريال (اختياري)', 'Serienummer (optioneel)'),
                prefixIcon: const Icon(Icons.qr_code_2_rounded),
              ),
            ),
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
              onChanged: busy ? null : (v) => setState(() => protocol = v ?? protocol),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: purpose,
              decoration: InputDecoration(
                labelText: _dt(context, 'Monitoring purpose', 'استخدام الكاميرا', 'Doel van monitoring'),
                prefixIcon: const Icon(Icons.monitor_heart_outlined),
              ),
              items: [
                DropdownMenuItem(
                  value: 'general_monitoring',
                  child: Text(_dt(context, 'General monitoring', 'مراقبة عامة', 'Algemene monitoring')),
                ),
                DropdownMenuItem(
                  value: 'animal_monitoring',
                  child: Text(_dt(context, 'Animal monitoring', 'مراقبة الحيوانات', 'Diermonitoring')),
                ),
                DropdownMenuItem(
                  value: 'barn_monitoring',
                  child: Text(_dt(context, 'Barn / area monitoring', 'مراقبة الحظيرة / المكان', 'Stal / ruimtemonitoring')),
                ),
                DropdownMenuItem(
                  value: 'temperature_monitoring',
                  child: Text(_dt(context, 'Temperature monitoring', 'مراقبة الحرارة', 'Temperatuurmonitoring')),
                ),
              ],
              onChanged: busy ? null : (v) => setState(() => purpose = v ?? purpose),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: busy ? null : _save,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 19,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.add_link_rounded),
              label: Text(_dt(
                context,
                busy ? 'Adding camera…' : 'Add camera',
                busy ? 'جاري إضافة الكاميرا…' : 'إضافة كاميرا',
                busy ? 'Camera toevoegen…' : 'Camera toevoegen',
              )),
            ),
            const SizedBox(height: 10),
            Text(
              _dt(
                context,
                'Compatibility depends on the camera exposing ONVIF and/or RTSP. The camera password is not written to the Vet AI database.',
                'التوافق يعتمد على دعم الكاميرا لـ ONVIF و/أو RTSP. كلمة مرور الكاميرا لا يتم حفظها في قاعدة بيانات Vet AI.',
                'Compatibiliteit hangt af van ONVIF- en/of RTSP-ondersteuning. Het camerawachtwoord wordt niet in de Vet AI-database opgeslagen.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: VetColors.muted, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}

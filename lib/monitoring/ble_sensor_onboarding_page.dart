import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n/vet_locale.dart';
import '../services/ble_sensor_models.dart';
import '../services/ble_sensor_provisioning.dart';
import '../services/vet_backend.dart';
import '../theme/app_theme.dart';

String _bt(BuildContext context, String en, String ar, String nl) =>
    VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

class VetBleSensorOnboardingPage extends StatefulWidget {
  const VetBleSensorOnboardingPage({
    super.key,
    required this.farmId,
    this.onProvisioned,
  });

  final String farmId;
  final VoidCallback? onProvisioned;

  @override
  State<VetBleSensorOnboardingPage> createState() =>
      _VetBleSensorOnboardingPageState();
}

class _VetBleSensorOnboardingPageState
    extends State<VetBleSensorOnboardingPage> {
  final ble = VetBleSensorProvisioner.instance;
  final ssid = TextEditingController();
  final password = TextEditingController();
  final devices = <String, VetBleDevice>{};
  StreamSubscription<VetBleDevice>? scanSub;
  StreamSubscription<VetBleAdapterState>? adapterSub;

  VetBleAdapterState adapter = VetBleAdapterState.unknown;
  VetBleDevice? selected;
  VetBleDeviceInfo? info;
  String stage = 'idle';
  String? detail;
  bool passwordVisible = false;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    adapterSub = ble.adapterState.listen((value) {
      if (!mounted) return;
      setState(() => adapter = value);
      if (value == VetBleAdapterState.ready && devices.isEmpty && !busy) {
        _startScan();
      }
    });
    if (ble.supported) _startScan();
  }

  @override
  void dispose() {
    scanSub?.cancel();
    adapterSub?.cancel();
    unawaited(ble.stopScan());
    ssid.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    if (!ble.supported || busy) return;
    await scanSub?.cancel();
    await ble.stopScan();
    if (!mounted) return;
    setState(() {
      devices.clear();
      selected = null;
      info = null;
      stage = 'scanning';
      detail = null;
    });
    scanSub = ble.scan().listen(
      (device) {
        if (!mounted) return;
        setState(() => devices[device.id] = device);
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          stage = 'error';
          detail = '$error';
        });
      },
    );
  }

  Future<void> _select(VetBleDevice device) async {
    if (busy) return;
    setState(() {
      selected = device;
      info = null;
      busy = true;
      stage = 'connecting';
      detail = null;
    });
    try {
      final value = await ble.readDeviceInfo(device.id);
      if (!mounted) return;
      setState(() {
        info = value;
        stage = 'network';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        selected = null;
        stage = 'error';
        detail = '$error';
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _provision() async {
    final device = selected;
    final deviceInfo = info;
    if (device == null || deviceInfo == null || busy) return;
    if (ssid.text.trim().isEmpty) {
      _snack(_bt(
        context,
        'Enter the Wi-Fi name used by this sensor or gateway.',
        'اكتب اسم شبكة Wi‑Fi التي سيستخدمها الحساس أو الـGateway.',
        'Vul de wifi-naam in die deze sensor of gateway gebruikt.',
      ));
      return;
    }

    setState(() {
      busy = true;
      stage = 'registering';
      detail = null;
    });

    try {
      final response = await VetBackend.instance.client.functions.invoke(
        'provision-sensor-device',
        body: {
          'farm_id': widget.farmId,
          'device_uid': deviceInfo.deviceUid,
          'device_type': deviceInfo.deviceType,
          'firmware_version': deviceInfo.firmwareVersion,
          'sensor_models': deviceInfo.capabilities,
        },
      );
      if (response.status < 200 || response.status >= 300) {
        throw StateError('Server registration failed (${response.status}).');
      }
      final raw = response.data;
      if (raw is! Map) throw StateError('Invalid provisioning response.');
      final data = Map<String, dynamic>.from(raw);
      final token = '${data['device_token'] ?? ''}'.trim();
      if (token.isEmpty) throw StateError('Device token was not returned.');

      if (!mounted) return;
      setState(() => stage = 'sending_network');

      final config = VetBleCloudConfig(
        farmId: widget.farmId,
        deviceToken: token,
        supabaseUrl: VetBackend.instance.client.rest.url,
        wifiSsid: ssid.text.trim(),
        wifiPassword: password.text,
      );
      final result = await ble.provision(
        deviceId: device.id,
        config: config,
        onStatus: (status) {
          if (!mounted) return;
          setState(() {
            stage = status.code;
            if (status.message.isNotEmpty) detail = status.message;
          });
        },
      );
      if (!result.success) throw StateError('Sensor did not confirm setup.');

      if (!mounted) return;
      setState(() {
        stage = 'done';
        detail = null;
      });
      widget.onProvisioned?.call();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        stage = 'error';
        detail = '$error';
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _adapterText() => switch (adapter) {
        VetBleAdapterState.ready => _bt(context, 'Bluetooth ready', 'البلوتوث جاهز', 'Bluetooth gereed'),
        VetBleAdapterState.off => _bt(context, 'Turn Bluetooth on', 'شغّل البلوتوث', 'Zet Bluetooth aan'),
        VetBleAdapterState.unauthorized => _bt(context, 'Allow Bluetooth access', 'اسمح للتطبيق باستخدام البلوتوث', 'Geef Bluetooth-toegang'),
        VetBleAdapterState.unavailable => _bt(context, 'Bluetooth is unavailable', 'البلوتوث غير متاح', 'Bluetooth is niet beschikbaar'),
        _ => _bt(context, 'Checking Bluetooth…', 'جاري فحص البلوتوث…', 'Bluetooth controleren…'),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_bt(context, 'Connect a sensor', 'ربط حساس', 'Sensor koppelen')),
      ),
      body: SafeArea(
        child: !ble.supported
            ? _mobileOnly(context)
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                children: [
                  _HeroCard(adapterText: _adapterText()),
                  const SizedBox(height: 18),
                  if (stage == 'done') _success(context) else ...[
                    if (info == null) _devicePicker(context),
                    if (info != null) _networkSetup(context),
                    if (stage == 'error') ...[
                      const SizedBox(height: 14),
                      _ErrorCard(
                        text: detail ?? _bt(context, 'Setup failed.', 'حدث خطأ أثناء الربط.', 'Koppelen mislukt.'),
                        onRetry: busy ? null : _startScan,
                      ),
                    ],
                  ],
                ],
              ),
      ),
    );
  }

  Widget _mobileOnly(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bluetooth_disabled_rounded, size: 58, color: VetColors.muted),
              const SizedBox(height: 14),
              Text(
                _bt(
                  context,
                  'Bluetooth setup is available in the Vet AI iPhone/Android app.',
                  'ربط الحساس بالبلوتوث متاح من تطبيق Vet AI على iPhone أو Android.',
                  'Bluetooth-koppeling is beschikbaar in de Vet AI iPhone/Android-app.',
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );

  Widget _devicePicker(BuildContext context) {
    final rows = devices.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _bt(context, 'Nearby Vet AI sensors', 'حساسات Vet AI القريبة', 'Vet AI-sensoren in de buurt'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          _bt(
            context,
            'Keep the phone close to the sensor. The strongest device appears first.',
            'قرّب الهاتف من الحساس. أقرب جهاز سيظهر في الأعلى.',
            'Houd de telefoon dicht bij de sensor. Het sterkste apparaat staat bovenaan.',
          ),
          style: const TextStyle(color: VetColors.muted),
        ),
        const SizedBox(height: 14),
        if (rows.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  if (stage == 'scanning' || adapter == VetBleAdapterState.ready)
                    const CircularProgressIndicator(),
                  const SizedBox(height: 14),
                  Text(_bt(
                    context,
                    'Searching automatically…',
                    'جاري البحث تلقائيًا…',
                    'Automatisch zoeken…',
                  )),
                ],
              ),
            ),
          ),
        for (final device in rows)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              enabled: !busy,
              leading: const CircleAvatar(
                backgroundColor: VetColors.softGreen,
                child: Icon(Icons.bluetooth_rounded, color: VetColors.green),
              ),
              title: Text(device.name, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('${_bt(context, 'Signal', 'قوة الإشارة', 'Signaal')}: ${device.rssi} dBm'),
              trailing: busy && selected?.id == device.id
                  ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.chevron_right_rounded),
              onTap: () => _select(device),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: busy ? null : _startScan,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(_bt(context, 'Scan again', 'بحث من جديد', 'Opnieuw zoeken')),
        ),
      ],
    );
  }

  Widget _networkSetup(BuildContext context) {
    final deviceInfo = info!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: VetColors.softGreen,
              child: Icon(Icons.check_rounded, color: VetColors.green),
            ),
            title: Text(selected?.name ?? deviceInfo.deviceUid, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('${deviceInfo.deviceType} • ${deviceInfo.deviceUid}${deviceInfo.firmwareVersion.isEmpty ? '' : '\nFirmware ${deviceInfo.firmwareVersion}'}'),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          _bt(context, 'Connect it to the internet', 'وصّل الحساس بالإنترنت', 'Verbind met internet'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          _bt(
            context,
            'Enter the farm Wi-Fi once. Vet AI sends it securely to the sensor over Bluetooth.',
            'اكتب Wi‑Fi المزرعة مرة واحدة. Vet AI سيرسل الإعدادات للحساس مباشرة عبر البلوتوث.',
            'Vul de wifi van de boerderij één keer in. Vet AI stuurt de instellingen via Bluetooth naar de sensor.',
          ),
          style: const TextStyle(color: VetColors.muted),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: ssid,
          enabled: !busy,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: _bt(context, 'Wi-Fi name', 'اسم شبكة Wi‑Fi', 'Wifi-naam'),
            prefixIcon: const Icon(Icons.wifi_rounded),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: password,
          enabled: !busy,
          obscureText: !passwordVisible,
          onSubmitted: (_) => _provision(),
          decoration: InputDecoration(
            labelText: _bt(context, 'Wi-Fi password', 'كلمة مرور Wi‑Fi', 'Wifi-wachtwoord'),
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              onPressed: () => setState(() => passwordVisible = !passwordVisible),
              icon: Icon(passwordVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded),
            ),
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: busy ? null : _provision,
          icon: busy
              ? const SizedBox.square(dimension: 19, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.link_rounded),
          label: Text(_bt(
            context,
            busy ? 'Connecting…' : 'Connect sensor',
            busy ? 'جاري الربط…' : 'ربط الحساس',
            busy ? 'Verbinden…' : 'Sensor koppelen',
          )),
        ),
        if (busy || ['registering', 'sending_network', 'config_sent', 'wifi_connecting', 'cloud_connecting'].contains(stage)) ...[
          const SizedBox(height: 12),
          Text(
            _bt(
              context,
              'Vet AI is registering the device, sending Wi-Fi settings and waiting for its cloud confirmation.',
              'Vet AI يسجل الجهاز ويرسل إعدادات Wi‑Fi وينتظر تأكيد اتصال الحساس بالسحابة.',
              'Vet AI registreert het apparaat, stuurt wifi-instellingen en wacht op cloudbevestiging.',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(color: VetColors.muted, fontSize: 12.5),
          ),
        ],
      ],
    );
  }

  Widget _success(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const CircleAvatar(
                radius: 32,
                backgroundColor: VetColors.softGreen,
                child: Icon(Icons.check_rounded, color: VetColors.green, size: 38),
              ),
              const SizedBox(height: 14),
              Text(
                _bt(context, 'Sensor connected', 'تم ربط الحساس', 'Sensor gekoppeld'),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 7),
              Text(
                _bt(
                  context,
                  'Bluetooth setup is finished. The sensor can now send real readings through the internet without keeping the phone nearby.',
                  'انتهى الربط بالبلوتوث. الحساس الآن يرسل القراءات الحقيقية عبر الإنترنت بدون الحاجة لوجود الهاتف بجانبه.',
                  'Bluetooth-instelling is klaar. De sensor kan nu via internet echte metingen sturen zonder dat de telefoon in de buurt blijft.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(color: VetColors.muted),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(_bt(context, 'Done', 'تم', 'Klaar')),
              ),
            ],
          ),
        ),
      );
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.adapterText});
  final String adapterText;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: VetColors.surface2,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: VetColors.border),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 27,
              backgroundColor: VetColors.softGreen,
              child: Icon(Icons.bluetooth_searching_rounded, color: VetColors.green, size: 31),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _bt(context, 'Easy Bluetooth setup', 'ربط سهل بالبلوتوث', 'Eenvoudig koppelen via Bluetooth'),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                  ),
                  const SizedBox(height: 3),
                  Text(adapterText, style: const TextStyle(color: VetColors.muted)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.text, required this.onRetry});
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(Icons.error_outline_rounded, color: VetColors.red),
              const SizedBox(height: 8),
              Text(text, textAlign: TextAlign.center),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(_bt(context, 'Try again', 'حاول مرة أخرى', 'Opnieuw proberen')),
              ),
            ],
          ),
        ),
      );
}

import 'package:flutter/material.dart';

import 'camera_intelligence_service.dart';

class CameraIntelligencePage extends StatefulWidget {
  const CameraIntelligencePage({
    super.key,
    required this.cameraName,
    required this.host,
    required this.httpPort,
    required this.username,
    required this.password,
    required this.vendor,
  });

  final String cameraName;
  final String host;
  final int httpPort;
  final String username;
  final String password;
  final String vendor;

  @override
  State<CameraIntelligencePage> createState() => _CameraIntelligencePageState();
}

class _CameraIntelligencePageState extends State<CameraIntelligencePage> {
  late final CameraIntelligenceService service;
  CameraIntelligenceCapabilities? caps;
  ThermalRuleTemperature? thermal;
  bool loading = true;
  bool thermalLoading = false;
  String? error;
  String? thermalError;

  @override
  void initState() {
    super.initState();
    service = CameraIntelligenceService(
      host: widget.host,
      httpPort: widget.httpPort,
      username: widget.username,
      password: widget.password,
      vendorHint: widget.vendor,
    );
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
      thermal = null;
      thermalError = null;
    });
    try {
      final result = await service.readCapabilities();
      if (!mounted) return;
      setState(() {
        caps = result;
        loading = false;
      });
      if (result.thermalSupported) await _readThermal();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = e.toString();
      });
    }
  }

  Future<void> _readThermal() async {
    if (thermalLoading) return;
    setState(() {
      thermalLoading = true;
      thermalError = null;
    });
    try {
      final value = await service.readThermalRuleTemperature();
      if (!mounted) return;
      setState(() => thermal = value);
    } catch (e) {
      if (!mounted) return;
      setState(() => thermalError = e.toString());
    } finally {
      if (mounted) setState(() => thermalLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111419),
        foregroundColor: Colors.white,
        title: Text('${widget.cameraName} Intelligence'),
        actions: [
          IconButton(onPressed: loading ? null : _load, icon: const Icon(Icons.refresh_rounded), tooltip: 'Refresh capabilities'),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? _errorState()
              : _content(),
    );
  }

  Widget _content() {
    final c = caps!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(
            'Device capabilities',
            Column(
              children: [
                _row('Manufacturer', c.manufacturer.isEmpty ? 'Not reported' : c.manufacturer),
                _row('Model', c.model.isEmpty ? 'Not reported' : c.model),
                _row('Firmware', c.firmwareVersion.isEmpty ? 'Not reported' : c.firmwareVersion),
                _row('Serial', c.serialNumber.isEmpty ? 'Not reported' : c.serialNumber),
                _flag('ONVIF Analytics', c.onvifAnalytics),
                _flag('ONVIF Events', c.onvifEvents),
                _flag('Video analytics profile', c.videoAnalyticsConfigurationToken != null),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _section(
            'Thermal / thermometry',
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _flag('Thermometry', c.thermalSupported),
                _flag('Realtime thermometry', c.realtimeThermometry),
                _flag('Face thermometry', c.faceThermometry),
                _flag('Fire detection', c.fireDetection),
                _flag('Click-to-thermometry', c.clickToThermometry),
                if (c.thermalMode != null) _row('Mode', c.thermalMode!),
                const SizedBox(height: 10),
                if (!c.thermalSupported)
                  const Text(
                    'No supported vendor thermometry API was reported by this camera.',
                    style: TextStyle(color: Colors.white60),
                  )
                else if (thermalLoading)
                  const Center(child: Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator()))
                else if (thermal != null)
                  _thermalCard(thermal!)
                else ...[
                  Text(
                    thermalError ?? 'Thermometry is supported, but no rule temperature was returned for channel 1 / scene 1 / rule 1.',
                    style: const TextStyle(color: Colors.orangeAccent),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(onPressed: _readThermal, icon: const Icon(Icons.thermostat_rounded), label: const Text('Read temperature again')),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          _section(
            'AI Analytics',
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _flag('Camera-reported analytics service', c.onvifAnalytics),
                _flag('Camera event service', c.onvifEvents),
                if (c.videoAnalyticsConfigurationToken != null)
                  _row('Analytics config token', c.videoAnalyticsConfigurationToken!),
                const SizedBox(height: 10),
                Text(
                  c.onvifAnalytics
                      ? 'The camera reports real ONVIF analytics capability. Vet AI will use only events/metadata actually emitted by the device; no fake detections are shown.'
                      : 'This camera did not report an ONVIF analytics capability. Vet AI will not invent AI detections for it.',
                  style: const TextStyle(color: Colors.white60),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Thermal temperature values require a radiometric camera and a supported vendor API. Standard ONVIF video alone does not guarantee temperature data.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _thermalCard(ThermalRuleTemperature t) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF20252C),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _temp('MAX', t.maxCelsius),
                _temp('AVG', t.averageCelsius),
                _temp('MIN', t.minCelsius),
              ],
            ),
            if (t.maxPointX != null && t.maxPointY != null) ...[
              const SizedBox(height: 10),
              Text('Hottest point: x=${t.maxPointX!.toStringAsFixed(3)}, y=${t.maxPointY!.toStringAsFixed(3)}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ],
          ],
        ),
      );

  Widget _temp(String label, double value) => Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text('${value.toStringAsFixed(1)} °C', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
        ],
      );

  Widget _section(String title, Widget child) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF15191F),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 128, child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
            Expanded(child: Text(value, style: const TextStyle(color: Colors.white70))),
          ],
        ),
      );

  Widget _flag(String label, bool value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(value ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded, color: value ? Colors.greenAccent : Colors.white30, size: 20),
            const SizedBox(width: 9),
            Expanded(child: Text(label, style: const TextStyle(color: Colors.white70))),
          ],
        ),
      );

  Widget _errorState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 52),
              const SizedBox(height: 12),
              Text(error ?? 'Could not read camera capabilities', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 14),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
}

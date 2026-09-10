import 'dart:async';

import 'package:flutter/material.dart';

import 'camera_intelligence_service.dart';
import 'onvif_analytics_events_service.dart';

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
  late final OnvifAnalyticsEventsService analyticsService;
  CameraIntelligenceCapabilities? caps;
  ThermalRuleTemperature? thermal;
  List<OnvifAnalyticsModule> modules = const [];
  List<String> eventTopics = const [];
  final List<OnvifCameraEvent> events = [];
  OnvifEventSession? eventSession;
  bool loading = true;
  bool thermalLoading = false;
  bool analyticsLoading = false;
  bool eventsRunning = false;
  String? error;
  String? thermalError;
  String? analyticsError;
  String? eventsError;

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
    analyticsService = OnvifAnalyticsEventsService(
      host: widget.host,
      httpPort: widget.httpPort,
      username: widget.username,
      password: widget.password,
    );
    _load();
  }

  @override
  void dispose() {
    final session = eventSession;
    eventsRunning = false;
    if (session != null) unawaited(analyticsService.unsubscribe(session));
    super.dispose();
  }

  Future<void> _load() async {
    await _stopEvents();
    setState(() {
      loading = true;
      error = null;
      thermal = null;
      thermalError = null;
      modules = const [];
      eventTopics = const [];
      events.clear();
      analyticsError = null;
      eventsError = null;
    });
    try {
      final result = await service.readCapabilities();
      if (!mounted) return;
      setState(() {
        caps = result;
        loading = false;
      });
      if (result.thermalSupported) await _readThermal();
      await _loadAnalyticsMetadata(result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = e.toString();
      });
    }
  }

  Future<void> _loadAnalyticsMetadata(CameraIntelligenceCapabilities c) async {
    if (!c.onvifAnalytics && !c.onvifEvents) return;
    setState(() {
      analyticsLoading = true;
      analyticsError = null;
    });
    try {
      var newModules = <OnvifAnalyticsModule>[];
      var newTopics = <String>[];
      final token = c.videoAnalyticsConfigurationToken;
      if (c.onvifAnalytics && token != null && token.isNotEmpty) {
        try {
          newModules = await analyticsService.getAnalyticsModules(token);
        } catch (e) {
          analyticsError = 'Analytics modules: $e';
        }
      }
      if (c.onvifEvents) {
        try {
          newTopics = await analyticsService.getEventTopics();
        } catch (e) {
          analyticsError = '${analyticsError == null ? '' : '${analyticsError!}\n'}Event topics: $e';
        }
      }
      if (!mounted) return;
      setState(() {
        modules = newModules;
        eventTopics = newTopics;
        analyticsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        analyticsLoading = false;
        analyticsError = e.toString();
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

  Future<void> _startEvents() async {
    if (eventsRunning) return;
    setState(() {
      eventsRunning = true;
      eventsError = null;
    });
    try {
      final session = await analyticsService.createPullPointSubscription();
      eventSession = session;
      while (mounted && eventsRunning && identical(eventSession, session)) {
        try {
          final pulled = await analyticsService.pullMessages(session);
          if (!mounted || !eventsRunning) break;
          if (pulled.isNotEmpty) {
            setState(() {
              events.insertAll(0, pulled.reversed);
              if (events.length > 100) events.removeRange(100, events.length);
            });
          }
        } catch (e) {
          if (!mounted) break;
          setState(() => eventsError = e.toString());
          break;
        }
      }
    } catch (e) {
      if (mounted) setState(() => eventsError = e.toString());
    } finally {
      if (mounted) setState(() => eventsRunning = false);
    }
  }

  Future<void> _stopEvents() async {
    final session = eventSession;
    eventsRunning = false;
    eventSession = null;
    if (session != null) await analyticsService.unsubscribe(session);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111419),
        foregroundColor: Colors.white,
        title: Text('${widget.cameraName} Intelligence'),
        actions: [IconButton(onPressed: loading ? null : _load, icon: const Icon(Icons.refresh_rounded))],
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
          _section('Device capabilities', Column(children: [
            _row('Manufacturer', c.manufacturer.isEmpty ? 'Not reported' : c.manufacturer),
            _row('Model', c.model.isEmpty ? 'Not reported' : c.model),
            _row('Firmware', c.firmwareVersion.isEmpty ? 'Not reported' : c.firmwareVersion),
            _row('Serial', c.serialNumber.isEmpty ? 'Not reported' : c.serialNumber),
            _flag('ONVIF Analytics', c.onvifAnalytics),
            _flag('ONVIF Events', c.onvifEvents),
            _flag('Video analytics profile', c.videoAnalyticsConfigurationToken != null),
          ])),
          const SizedBox(height: 14),
          _section('Thermal / thermometry', Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _flag('Thermometry', c.thermalSupported),
            _flag('Realtime thermometry', c.realtimeThermometry),
            _flag('Face thermometry', c.faceThermometry),
            _flag('Fire detection', c.fireDetection),
            _flag('Click-to-thermometry', c.clickToThermometry),
            if (c.thermalMode != null) _row('Mode', c.thermalMode!),
            const SizedBox(height: 10),
            if (!c.thermalSupported)
              const Text('No supported vendor thermometry API was reported by this camera.', style: TextStyle(color: Colors.white60))
            else if (thermalLoading)
              const Center(child: Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator()))
            else if (thermal != null)
              _thermalCard(thermal!)
            else ...[
              Text(thermalError ?? 'No temperature was returned for channel 1 / scene 1 / rule 1.', style: const TextStyle(color: Colors.orangeAccent)),
              const SizedBox(height: 10),
              OutlinedButton.icon(onPressed: _readThermal, icon: const Icon(Icons.thermostat_rounded), label: const Text('Read temperature again')),
            ],
          ])),
          const SizedBox(height: 14),
          _section('AI Analytics modules', Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _flag('Camera-reported analytics service', c.onvifAnalytics),
            if (c.videoAnalyticsConfigurationToken != null) _row('Analytics token', c.videoAnalyticsConfigurationToken!),
            if (analyticsLoading) const LinearProgressIndicator(),
            if (modules.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...modules.map((m) => _row(m.name.isEmpty ? 'Module' : m.name, m.type.isEmpty ? 'Type not reported' : m.type)),
            ] else if (c.onvifAnalytics && !analyticsLoading)
              const Text('No analytics modules were returned for this configuration token.', style: TextStyle(color: Colors.white60)),
            if (analyticsError != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(analyticsError!, style: const TextStyle(color: Colors.orangeAccent))),
          ])),
          const SizedBox(height: 14),
          _section('Live camera events', Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _flag('ONVIF Event service', c.onvifEvents),
            if (eventTopics.isNotEmpty) _row('Reported topics', eventTopics.take(8).join(', ')),
            const SizedBox(height: 8),
            if (c.onvifEvents)
              Row(children: [
                Expanded(child: FilledButton.icon(onPressed: eventsRunning ? null : _startEvents, icon: const Icon(Icons.play_arrow_rounded), label: const Text('Start live events'))),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton.icon(onPressed: eventsRunning ? _stopEvents : null, icon: const Icon(Icons.stop_rounded), label: const Text('Stop'))),
              ]),
            if (eventsRunning) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator()),
            if (eventsError != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(eventsError!, style: const TextStyle(color: Colors.orangeAccent))),
            if (events.isEmpty) const Padding(padding: EdgeInsets.only(top: 10), child: Text('No camera-emitted events received yet.', style: TextStyle(color: Colors.white60))),
            ...events.take(30).map(_eventTile),
          ])),
          const SizedBox(height: 18),
          const Text('Events and analytics shown here come from the connected camera through ONVIF. Thermal values require a radiometric camera and supported vendor thermometry API.', style: TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _eventTile(OnvifCameraEvent e) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFF20252C), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(e.topic, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(e.summary, style: const TextStyle(color: Colors.white70)),
          if (e.utcTime != null) Text(e.utcTime!.toLocal().toString(), style: const TextStyle(color: Colors.white38, fontSize: 11)),
          if (e.values.length > 1) Text(e.values.entries.map((x) => '${x.key}=${x.value}').join(' • '), style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ]),
      );

  Widget _thermalCard(ThermalRuleTemperature t) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFF20252C), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_temp('MAX', t.maxCelsius), _temp('AVG', t.averageCelsius), _temp('MIN', t.minCelsius)]),
          if (t.maxPointX != null && t.maxPointY != null) ...[
            const SizedBox(height: 10),
            Text('Hottest point: x=${t.maxPointX!.toStringAsFixed(3)}, y=${t.maxPointY!.toStringAsFixed(3)}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
          ],
        ]),
      );

  Widget _temp(String label, double value) => Column(children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text('${value.toStringAsFixed(1)} °C', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
      ]);

  Widget _section(String title, Widget child) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFF15191F), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          child,
        ]),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 128, child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.white70))),
        ]),
      );

  Widget _flag(String label, bool value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Icon(value ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded, color: value ? Colors.greenAccent : Colors.white30, size: 20),
          const SizedBox(width: 9),
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white70))),
        ]),
      );

  Widget _errorState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 52),
            const SizedBox(height: 12),
            Text(error ?? 'Could not read camera capabilities', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 14),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ]),
        ),
      );
}

import 'dart:async';

import 'package:flutter/material.dart';

import 'camera_event_classifier.dart';
import 'camera_alert_repository.dart';
import 'camera_intelligence_service.dart';
import 'onvif_analytics_events_service.dart';

class CameraIntelligencePage extends StatefulWidget {
  const CameraIntelligencePage({
    super.key,
    required this.farmId,
    required this.deviceUid,
    required this.cameraName,
    required this.host,
    required this.httpPort,
    required this.username,
    required this.password,
    required this.vendor,
  });

  final String farmId;
  final String deviceUid;
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
  final CameraAlertRepository alertRepository = const CameraAlertRepository();
  final Set<String> _savedFingerprints = <String>{};
  double _thermalCriticalThresholdC = 41.0;
  CameraIntelligenceCapabilities? caps;
  ThermalRuleTemperature? thermal;
  List<OnvifAnalyticsModule> modules = const [];
  List<OnvifSupportedAnalyticsModule> supportedModules = const [];
  List<String> eventTopics = const [];
  final List<OnvifCameraEvent> events = [];
  final Set<String> _liveEventFingerprints = <String>{};
  OnvifEventSession? eventSession;
  bool loading = true;
  bool thermalLoading = false;
  bool analyticsLoading = false;
  bool eventsRunning = false;
  bool eventsReconnecting = false;
  int eventReconnects = 0;
  int eventRenewals = 0;
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
    unawaited(_loadAlertSettings());
    _load();
  }

  @override
  void dispose() {
    final session = eventSession;
    eventsRunning = false;
    if (session != null) unawaited(analyticsService.unsubscribe(session));
    super.dispose();
  }

  Future<void> _loadAlertSettings() async {
    try {
      final value = await alertRepository.thermalCriticalThreshold(
        farmId: widget.farmId,
        cameraUid: widget.deviceUid,
      );
      if (mounted) setState(() => _thermalCriticalThresholdC = value);
    } catch (_) {
      // Keep safe default when this camera has no saved threshold yet.
    }
  }

  Future<void> _editThermalThreshold() async {
    final controller = TextEditingController(text: _thermalCriticalThresholdC.toStringAsFixed(1));
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Critical thermal alert'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Temperature °C', helperText: 'Allowed range: 30–60 °C'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final parsed = double.tryParse(controller.text.trim().replaceAll(',', '.'));
              if (parsed == null || parsed < 30 || parsed > 60) return;
              Navigator.pop(context, parsed);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    try {
      await alertRepository.setThermalCriticalThreshold(
        farmId: widget.farmId,
        cameraUid: widget.deviceUid,
        valueC: value,
      );
      if (!mounted) return;
      setState(() => _thermalCriticalThresholdC = value);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Critical thermal alert set to ${value.toStringAsFixed(1)} °C')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save thermal threshold: $e')));
    }
  }

  Future<void> _load() async {
    await _stopEvents();
    setState(() {
      loading = true;
      error = null;
      thermal = null;
      thermalError = null;
      modules = const [];
      supportedModules = const [];
      eventTopics = const [];
      events.clear();
      _liveEventFingerprints.clear();
      eventReconnects = 0;
      eventRenewals = 0;
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
      var newSupportedModules = <OnvifSupportedAnalyticsModule>[];
      var newTopics = <String>[];
      final errors = <String>[];
      final token = c.videoAnalyticsConfigurationToken;
      if (c.onvifAnalytics && token != null && token.isNotEmpty) {
        try {
          newModules = await analyticsService.getAnalyticsModules(token);
        } catch (e) {
          errors.add('Analytics modules: $e');
        }
        try {
          newSupportedModules =
              await analyticsService.getSupportedAnalyticsModules(token);
        } catch (e) {
          errors.add('Supported analytics modules: $e');
        }
      }
      if (c.onvifEvents) {
        try {
          newTopics = await analyticsService.getEventTopics();
        } catch (e) {
          errors.add('Event topics: $e');
        }
      }
      if (!mounted) return;
      setState(() {
        modules = newModules;
        supportedModules = newSupportedModules;
        eventTopics = newTopics;
        analyticsLoading = false;
        analyticsError = errors.isEmpty ? null : errors.join('\n');
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

  List<OnvifCameraEvent> _dedupeLiveEvents(List<OnvifCameraEvent> pulled) {
    final unique = <OnvifCameraEvent>[];
    for (final event in pulled) {
      if (event.utcTime == null) {
        unique.add(event);
        continue;
      }
      final fingerprint = event.stableFingerprint;
      if (_liveEventFingerprints.add(fingerprint)) unique.add(event);
    }
    while (_liveEventFingerprints.length > 500) {
      _liveEventFingerprints.remove(_liveEventFingerprints.first);
    }
    return unique;
  }

  Future<void> _startEvents() async {
    if (eventsRunning) return;
    setState(() {
      eventsRunning = true;
      eventsReconnecting = false;
      eventsError = null;
    });

    var reconnectAttempt = 0;
    while (mounted && eventsRunning) {
      OnvifEventSession? session;
      try {
        session = await analyticsService.createPullPointSubscription();
        if (!mounted || !eventsRunning) break;
        eventSession = session;
        reconnectAttempt = 0;
        setState(() {
          eventsReconnecting = false;
          eventsError = null;
        });

        while (mounted && eventsRunning && eventSession != null) {
          final activeSession = session;
          if (activeSession == null) break;
          if (activeSession.shouldRenew()) {
            session = await analyticsService.renewPullPointSubscription(activeSession);
            eventSession = session;
            eventRenewals += 1;
            if (mounted) setState(() {});
          }

          final pullSession = session;
          if (pullSession == null) break;
          final rawPulled = await analyticsService.pullMessages(pullSession);
          final pulled = _dedupeLiveEvents(rawPulled);
          if (!mounted || !eventsRunning) break;
          if (pulled.isNotEmpty) {
            setState(() {
              events.insertAll(0, pulled.reversed);
              if (events.length > 100) events.removeRange(100, events.length);
            });
            _surfaceHighestPriorityAlert(pulled);
            unawaited(_persistCameraAlerts(pulled));
          }
        }
      } catch (e) {
        if (!mounted || !eventsRunning) break;
        eventReconnects += 1;
        final shift = reconnectAttempt > 5 ? 5 : reconnectAttempt;
        final delay = Duration(seconds: 1 << shift);
        reconnectAttempt += 1;
        setState(() {
          eventsReconnecting = true;
          eventsError = 'Camera event connection lost. Reconnecting in ${delay.inSeconds}s…\n$e';
        });
        await Future<void>.delayed(delay);
      } finally {
        final activeSession = session;
        if (activeSession != null) {
          unawaited(analyticsService.unsubscribe(activeSession));
        }
        if (identical(eventSession, session)) eventSession = null;
      }
    }

    if (mounted) {
      setState(() {
        eventsRunning = false;
        eventsReconnecting = false;
      });
    }
  }

  void _surfaceHighestPriorityAlert(List<OnvifCameraEvent> pulled) {
    CameraAlertDecision? best;
    for (final event in pulled) {
      final decision = CameraEventClassifier.classify(
        topic: event.topic,
        values: event.values,
      );
      if (!decision.shouldSurface) continue;
      if (best == null || decision.severity.index > best.severity.index) {
        best = decision;
      }
    }
    if (best == null || !mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${widget.cameraName}: ${best.title}'),
        duration: Duration(
          seconds: best.severity == CameraAlertSeverity.critical ? 6 : 3,
        ),
      ),
    );
  }

  Future<void> _persistCameraAlerts(List<OnvifCameraEvent> pulled) async {
    for (final event in pulled) {
      final decision = CameraEventClassifier.classify(topic: event.topic, values: event.values, criticalTemperatureC: _thermalCriticalThresholdC);
      if (!decision.shouldSurface) continue;
      final fingerprint = '${event.utcTime?.toUtc().toIso8601String() ?? ''}|${event.topic}|${event.operation ?? ''}|${event.values.entries.map((e) => '${e.key}=${e.value}').join(';')}';
      if (_savedFingerprints.contains(fingerprint)) continue;
      _savedFingerprints.add(fingerprint);
      if (_savedFingerprints.length > 300) _savedFingerprints.remove(_savedFingerprints.first);
      try {
        final row = await alertRepository.save(
          farmId: widget.farmId,
          cameraUid: widget.deviceUid,
          cameraName: widget.cameraName,
          event: event,
          decision: decision,
        );
        final id = (row['id'] ?? '').toString();
        final inserted = row['_inserted'] != false;
        if (inserted && id.isNotEmpty) {
          try {
            await alertRepository.dispatchPush(id);
          } catch (_) {
            // Alert persistence must not fail just because APNs is unavailable.
          }
        }
      } catch (e) {
        if (mounted) setState(() => eventsError = 'Alert save: $e');
      }
    }
  }

  Future<void> _showSavedAlerts() async {
    List<Map<String, dynamic>> rows = const [];
    String? loadError;
    try {
      rows = await alertRepository.recentForCamera(
        farmId: widget.farmId,
        cameraUid: widget.deviceUid,
      );
    } catch (e) {
      loadError = e.toString();
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF15191F),
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * .72,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 2, 18, 12),
                child: Row(children: [
                  Icon(Icons.notifications_active_rounded, color: Colors.white),
                  SizedBox(width: 10),
                  Text('Saved camera alerts', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                ]),
              ),
              if (loadError != null)
                Padding(padding: const EdgeInsets.all(18), child: Text(loadError!, style: const TextStyle(color: Colors.orangeAccent)))
              else if (rows.isEmpty)
                const Expanded(child: Center(child: Text('No saved alerts for this camera yet.', style: TextStyle(color: Colors.white60))))
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final risk = (row['risk'] ?? '').toString();
                      final created = DateTime.tryParse((row['created_at'] ?? '').toString())?.toLocal();
                      final color = risk == 'red' ? Colors.redAccent : risk == 'orange' ? Colors.orangeAccent : Colors.amberAccent;
                      final acknowledged = row['acknowledged_at'] != null;
                      return ListTile(
                        leading: Icon(acknowledged ? Icons.check_circle_rounded : Icons.warning_amber_rounded, color: acknowledged ? Colors.greenAccent : color),
                        title: Text((row['title'] ?? 'Camera alert').toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        subtitle: Text('${created ?? ''}\n${(row['details'] ?? '').toString()}', maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60)),
                        trailing: acknowledged
                            ? const Tooltip(message: 'Acknowledged', child: Icon(Icons.done_all_rounded, color: Colors.greenAccent))
                            : IconButton(
                                tooltip: 'Acknowledge alert',
                                icon: const Icon(Icons.check_rounded, color: Colors.white70),
                                onPressed: () async {
                                  final id = (row['id'] ?? '').toString();
                                  if (id.isEmpty) return;
                                  try {
                                    await alertRepository.acknowledge(id);
                                    if (!context.mounted) return;
                                    Navigator.pop(context);
                                    await _showSavedAlerts();
                                  } catch (e) {
                                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not acknowledge alert: $e')));
                                  }
                                },
                              ),
                        isThreeLine: true,
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _stopEvents() async {
    final session = eventSession;
    eventsRunning = false;
    eventsReconnecting = false;
    eventSession = null;
    if (session != null) await analyticsService.unsubscribe(session);
    if (mounted) setState(() {});
  }

  int get _activeAlertCount => events
      .where(
        (e) => CameraEventClassifier.classify(
          topic: e.topic,
          values: e.values,
        ).shouldSurface,
      )
      .length;

  int get _criticalAlertCount => events.where((e) {
        final d = CameraEventClassifier.classify(
          topic: e.topic,
          values: e.values,
        );
        return d.shouldSurface && d.severity == CameraAlertSeverity.critical;
      }).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111419),
        foregroundColor: Colors.white,
        title: Text('${widget.cameraName} Intelligence'),
        actions: [
          IconButton(
            onPressed: _showSavedAlerts,
            icon: const Icon(Icons.notifications_active_outlined),
            tooltip: 'Saved alerts',
          ),
          IconButton(
            onPressed: loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
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
            Column(children: [
              _row('Manufacturer', c.manufacturer.isEmpty ? 'Not reported' : c.manufacturer),
              _row('Model', c.model.isEmpty ? 'Not reported' : c.model),
              _row('Firmware', c.firmwareVersion.isEmpty ? 'Not reported' : c.firmwareVersion),
              _row('Serial', c.serialNumber.isEmpty ? 'Not reported' : c.serialNumber),
              _flag('ONVIF Analytics', c.onvifAnalytics),
              _flag('ONVIF Events', c.onvifEvents),
              _flag('Video analytics profile', c.videoAnalyticsConfigurationToken != null),
            ]),
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
            _row('Critical alert threshold', '${_thermalCriticalThresholdC.toStringAsFixed(1)} °C'),
            Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _editThermalThreshold, icon: const Icon(Icons.tune_rounded), label: const Text('Change thermal alert threshold'))),
                const SizedBox(height: 10),
                if (!c.thermalSupported)
                  const Text(
                    'No supported vendor thermometry API was reported by this camera.',
                    style: TextStyle(color: Colors.white60),
                  )
                else if (thermalLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (thermal != null)
                  _thermalCard(thermal!)
                else ...[
                  Text(
                    thermalError ?? 'No temperature was returned for channel 1 / scene 1 / rule 1.',
                    style: const TextStyle(color: Colors.orangeAccent),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _readThermal,
                    icon: const Icon(Icons.thermostat_rounded),
                    label: const Text('Read temperature again'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          _section(
            'AI Analytics modules',
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _flag('Camera-reported analytics service', c.onvifAnalytics),
                if (c.videoAnalyticsConfigurationToken != null)
                  _row('Analytics token', c.videoAnalyticsConfigurationToken!),
                if (analyticsLoading) const LinearProgressIndicator(),
                if (modules.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Configured modules',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                  ...modules.map(
                    (m) => _row(
                      m.name.isEmpty ? 'Module' : m.name,
                      m.type.isEmpty ? 'Type not reported' : m.type,
                    ),
                  ),
                ] else if (c.onvifAnalytics && !analyticsLoading)
                  const Text(
                    'No configured analytics modules were returned for this configuration token.',
                    style: TextStyle(color: Colors.white60),
                  ),
                if (supportedModules.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Camera-supported modules',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                  ...supportedModules.map((m) {
                    final details = <String>[
                      if (m.type.isNotEmpty) m.type,
                      if (m.maxInstances != null) 'max ${m.maxInstances}',
                      if (m.parameters.isNotEmpty)
                        'params: ${m.parameters.take(5).join(', ')}',
                    ].join(' • ');
                    return _row(
                      m.name.isEmpty ? 'Supported module' : m.name,
                      details.isEmpty ? 'Supported' : details,
                    );
                  }),
                ],
                if (analyticsError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      analyticsError!,
                      style: const TextStyle(color: Colors.orangeAccent),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _section(
            'Smart alerts from camera events',
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _flag('ONVIF Event service', c.onvifEvents),
                if (eventTopics.isNotEmpty)
                  _row('Reported topics', eventTopics.take(8).join(', ')),
                if (eventsRunning) ...[
                  _row('Subscription renewals', '$eventRenewals'),
                  _row('Reconnects', '$eventReconnects'),
                ],
                if (events.isNotEmpty) ...[
                  _row('Surfaced alerts', '$_activeAlertCount'),
                  _row('Critical alerts', '$_criticalAlertCount'),
                ],
                const SizedBox(height: 8),
                if (c.onvifEvents)
                  Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: eventsRunning ? null : _startEvents,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Start live alerts'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: eventsRunning ? _stopEvents : null,
                        icon: const Icon(Icons.stop_rounded),
                        label: const Text('Stop'),
                      ),
                    ),
                  ]),
                if (eventsRunning)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          eventsReconnecting
                              ? 'Reconnecting to camera events…'
                              : 'Live PullPoint subscription active',
                          style: TextStyle(
                            color: eventsReconnecting
                                ? Colors.orangeAccent
                                : Colors.greenAccent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ]),
                  ),
                if (eventsError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      eventsError!,
                      style: const TextStyle(color: Colors.orangeAccent),
                    ),
                  ),
                if (events.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      'No camera-emitted events received yet.',
                      style: TextStyle(color: Colors.white60),
                    ),
                  ),
                ...events.take(30).map(_eventTile),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Smart alert labels are derived only from real ONVIF event topics and values emitted by the connected camera. Vet AI does not fabricate detections.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _eventTile(OnvifCameraEvent e) {
    final decision = CameraEventClassifier.classify(
      topic: e.topic,
      values: e.values,
    );
    final icon = decision.severity == CameraAlertSeverity.critical
        ? Icons.error_rounded
        : decision.severity == CameraAlertSeverity.warning
            ? Icons.warning_amber_rounded
            : Icons.info_outline_rounded;
    final color = decision.severity == CameraAlertSeverity.critical
        ? Colors.redAccent
        : decision.severity == CameraAlertSeverity.warning
            ? Colors.orangeAccent
            : Colors.lightBlueAccent;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF20252C),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: decision.shouldSurface
              ? color.withValues(alpha: 0.45)
              : Colors.white10,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                decision.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text(e.topic, style: const TextStyle(color: Colors.white60, fontSize: 12)),
          Text(e.summary, style: const TextStyle(color: Colors.white70)),
          if (e.utcTime != null)
            Text(
              e.utcTime!.toLocal().toString(),
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          if (e.values.length > 1)
            Text(
              e.values.entries.map((x) => '${x.key}=${x.value}').join(' • '),
              style: const TextStyle(color: Colors.white54, fontSize: 11),
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
        child: Column(children: [
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
            Text(
              'Hottest point: x=${t.maxPointX!.toStringAsFixed(3)}, y=${t.maxPointY!.toStringAsFixed(3)}',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
        ]),
      );

  Widget _temp(String label, double value) => Column(children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '${value.toStringAsFixed(1)} °C',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
      ]);

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
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
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
            SizedBox(
              width: 128,
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: Text(value, style: const TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      );

  Widget _flag(String label, bool value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Icon(
            value ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded,
            color: value ? Colors.greenAccent : Colors.white30,
            size: 20,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.white70)),
          ),
        ]),
      );

  Widget _errorState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 52),
              const SizedBox(height: 12),
              Text(
                error ?? 'Could not read camera capabilities',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 14),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
}

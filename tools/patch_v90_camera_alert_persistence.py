from pathlib import Path

page = Path('lib/monitoring/camera_intelligence_page.dart')
s = page.read_text()

if "import 'camera_alert_repository.dart';" not in s:
    s = s.replace("import 'camera_event_classifier.dart';\n", "import 'camera_event_classifier.dart';\nimport 'camera_alert_repository.dart';\n", 1)

if 'required this.farmId,' not in s:
    s = s.replace('    required this.cameraName,\n', '    required this.farmId,\n    required this.deviceUid,\n    required this.cameraName,\n', 1)
    s = s.replace('  final String cameraName;\n', '  final String farmId;\n  final String deviceUid;\n  final String cameraName;\n', 1)

if 'final CameraAlertRepository alertRepository = const CameraAlertRepository();' not in s:
    anchor = '  late final OnvifAnalyticsEventsService analyticsService;\n'
    s = s.replace(anchor, anchor + '  final CameraAlertRepository alertRepository = const CameraAlertRepository();\n  final Set<String> _savedFingerprints = <String>{};\n', 1)

if 'Future<void> _persistCameraAlerts(' not in s:
    anchor = '  Future<void> _stopEvents() async {\n'
    method = '''  Future<void> _persistCameraAlerts(List<OnvifCameraEvent> pulled) async {
    for (final event in pulled) {
      final decision = CameraEventClassifier.classify(topic: event.topic, values: event.values);
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
        if (id.isNotEmpty) {
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
                      return ListTile(
                        leading: Icon(Icons.warning_amber_rounded, color: color),
                        title: Text((row['title'] ?? 'Camera alert').toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        subtitle: Text('${created ?? ''}\\n${(row['details'] ?? '').toString()}', maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60)),
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

'''
    assert anchor in s, 'V90 stop-events anchor missing'
    s = s.replace(anchor, method + anchor, 1)

old = '''            _surfaceHighestPriorityAlert(pulled);
'''
new = '''            _surfaceHighestPriorityAlert(pulled);
            unawaited(_persistCameraAlerts(pulled));
'''
if new not in s:
    assert old in s, 'V90 event persistence anchor missing'
    s = s.replace(old, new, 1)

old_actions = "        actions: [IconButton(onPressed: loading ? null : _load, icon: const Icon(Icons.refresh_rounded))],\n"
new_actions = "        actions: [\n          IconButton(onPressed: _showSavedAlerts, icon: const Icon(Icons.notifications_active_outlined), tooltip: 'Saved alerts'),\n          IconButton(onPressed: loading ? null : _load, icon: const Icon(Icons.refresh_rounded)),\n        ],\n"
if new_actions not in s:
    assert old_actions in s, 'V90 appbar anchor missing'
    s = s.replace(old_actions, new_actions, 1)

assert "import 'camera_alert_repository.dart';" in s
assert 'required this.farmId,' in s
assert 'required this.deviceUid,' in s
assert '_persistCameraAlerts(pulled)' in s
assert '_showSavedAlerts' in s
page.write_text(s)

center = Path('lib/monitoring/camera_center_page.dart')
c = center.read_text()
old_builder = '''        builder: (_) => CameraIntelligencePage(
          cameraName: camera.name,
'''
new_builder = '''        builder: (_) => CameraIntelligencePage(
          farmId: widget.farmId,
          deviceUid: camera.uid,
          cameraName: camera.name,
'''
if new_builder not in c:
    assert old_builder in c, 'V90 CameraIntelligencePage builder anchor missing'
    c = c.replace(old_builder, new_builder, 1)
assert 'farmId: widget.farmId' in c
assert 'deviceUid: camera.uid' in c
center.write_text(c)

print('V90 camera alerts persisted to Supabase, APNs dispatched, saved alert history wired')

from pathlib import Path

page = Path('lib/monitoring/camera_intelligence_page.dart')
s = page.read_text()

if 'double _thermalCriticalThresholdC = 41.0;' not in s:
    anchor = '  final Set<String> _savedFingerprints = <String>{};\n'
    assert anchor in s, 'V91 V90 state anchor missing'
    s = s.replace(anchor, anchor + '  double _thermalCriticalThresholdC = 41.0;\n', 1)

if 'unawaited(_loadAlertSettings());' not in s:
    anchor = '    _load();\n'
    assert anchor in s, 'V91 init anchor missing'
    s = s.replace(anchor, '    unawaited(_loadAlertSettings());\n' + anchor, 1)

if 'Future<void> _loadAlertSettings()' not in s:
    anchor = '  Future<void> _load() async {\n'
    method = '''  Future<void> _loadAlertSettings() async {
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

'''
    assert anchor in s, 'V91 load method anchor missing'
    s = s.replace(anchor, method + anchor, 1)

# Make all camera alert classifications use the persisted per-camera threshold.
s = s.replace(
    'CameraEventClassifier.classify(topic: event.topic, values: event.values);',
    'CameraEventClassifier.classify(topic: event.topic, values: event.values, criticalTemperatureC: _thermalCriticalThresholdC);',
)
s = s.replace(
    'CameraEventClassifier.classify(topic: e.topic, values: e.values).shouldSurface',
    'CameraEventClassifier.classify(topic: e.topic, values: e.values, criticalTemperatureC: _thermalCriticalThresholdC).shouldSurface',
)
s = s.replace(
    'CameraEventClassifier.classify(topic: e.topic, values: e.values);',
    'CameraEventClassifier.classify(topic: e.topic, values: e.values, criticalTemperatureC: _thermalCriticalThresholdC);',
)

# Only dispatch APNs when a row was really inserted; duplicates return _inserted=false.
old = '''        final id = (row['id'] ?? '').toString();
        if (id.isNotEmpty) {
          try {
            await alertRepository.dispatchPush(id);
          } catch (_) {
            // Alert persistence must not fail just because APNs is unavailable.
          }
        }
'''
new = '''        final id = (row['id'] ?? '').toString();
        final inserted = row['_inserted'] != false;
        if (inserted && id.isNotEmpty) {
          try {
            await alertRepository.dispatchPush(id);
          } catch (_) {
            // Alert persistence must not fail just because APNs is unavailable.
          }
        }
'''
if new not in s:
    assert old in s, 'V91 APNs dedupe anchor missing'
    s = s.replace(old, new, 1)

# Show/edit the real per-camera thermal threshold.
old = "            if (c.thermalMode != null) _row('Mode', c.thermalMode!),\n"
new = "            if (c.thermalMode != null) _row('Mode', c.thermalMode!),\n            _row('Critical alert threshold', '${_thermalCriticalThresholdC.toStringAsFixed(1)} °C'),\n            Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _editThermalThreshold, icon: const Icon(Icons.tune_rounded), label: const Text('Change thermal alert threshold'))),\n"
if new not in s:
    assert old in s, 'V91 thermal UI anchor missing'
    s = s.replace(old, new, 1)

# Add acknowledgement state/action to saved alert history.
old = '''                      return ListTile(
                        leading: Icon(Icons.warning_amber_rounded, color: color),
                        title: Text((row['title'] ?? 'Camera alert').toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        subtitle: Text('${created ?? ''}\\n${(row['details'] ?? '').toString()}', maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60)),
                        isThreeLine: true,
                      );
'''
new = '''                      final acknowledged = row['acknowledged_at'] != null;
                      return ListTile(
                        leading: Icon(acknowledged ? Icons.check_circle_rounded : Icons.warning_amber_rounded, color: acknowledged ? Colors.greenAccent : color),
                        title: Text((row['title'] ?? 'Camera alert').toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        subtitle: Text('${created ?? ''}\\n${(row['details'] ?? '').toString()}', maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60)),
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
'''
if new not in s:
    assert old in s, 'V91 saved alert tile anchor missing'
    s = s.replace(old, new, 1)

assert 'double _thermalCriticalThresholdC = 41.0;' in s
assert 'thermalCriticalThreshold(' in s
assert 'setThermalCriticalThreshold(' in s
assert "row['_inserted'] != false" in s
assert 'alertRepository.acknowledge(id)' in s
assert 'Change thermal alert threshold' in s
page.write_text(s)

print('V91 camera alert hardening applied: persistent threshold, dedupe-aware push, acknowledgement UI')

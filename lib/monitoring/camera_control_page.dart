import 'package:flutter/material.dart';

import 'onvif_camera_control_service.dart';

class CameraControlPage extends StatefulWidget {
  const CameraControlPage({
    super.key,
    required this.cameraName,
    required this.host,
    required this.httpPort,
    required this.username,
    required this.password,
  });

  final String cameraName;
  final String host;
  final int httpPort;
  final String username;
  final String password;

  @override
  State<CameraControlPage> createState() => _CameraControlPageState();
}

class _CameraControlPageState extends State<CameraControlPage> {
  late final OnvifCameraControlService service;
  OnvifCameraCapabilities? capabilities;
  OnvifImagingSettings? imaging;
  List<OnvifPreset> presets = const [];
  bool loading = true;
  bool moving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    service = OnvifCameraControlService(
      host: widget.host,
      httpPort: widget.httpPort,
      username: widget.username,
      password: widget.password,
    );
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final caps = await service.readCapabilities();
      OnvifImagingSettings? imagingSettings;
      List<OnvifPreset> presetItems = const [];
      if (caps.imagingSupported) {
        try {
          imagingSettings = await service.getImagingSettings(caps);
        } catch (_) {}
      }
      if (caps.supportsPtz) {
        try {
          presetItems = await service.getPresets(caps);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        capabilities = caps;
        imaging = imagingSettings;
        presets = presetItems;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = e.toString();
      });
    }
  }

  Future<void> _move({double pan = 0, double tilt = 0, double zoom = 0}) async {
    final caps = capabilities;
    if (caps == null || !caps.supportsContinuousMove || moving) return;
    setState(() => moving = true);
    try {
      await service.continuousMove(capabilities: caps, pan: pan, tilt: tilt, zoom: zoom);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await service.stop(caps);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PTZ failed: $e')));
      }
    } finally {
      if (mounted) setState(() => moving = false);
    }
  }

  Future<void> _gotoPreset(OnvifPreset preset) async {
    final caps = capabilities;
    if (caps == null) return;
    try {
      await service.gotoPreset(caps, preset.token);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Preset failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111419),
        foregroundColor: Colors.white,
        title: Text(widget.cameraName),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded), tooltip: 'Refresh capabilities'),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? _errorState()
              : _content(),
    );
  }

  Widget _errorState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 52),
              const SizedBox(height: 12),
              Text(error ?? 'Could not read ONVIF capabilities', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 14),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );

  Widget _content() {
    final caps = capabilities!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _section(
          title: 'Detected capabilities',
          child: Column(
            children: [
              _capabilityRow('ONVIF Media', true),
              _capabilityRow('PTZ', caps.supportsPtz),
              _capabilityRow('Continuous PTZ', caps.supportsContinuousMove),
              _capabilityRow('Relative PTZ', caps.supportsRelativeMove),
              _capabilityRow('Absolute PTZ', caps.supportsAbsoluteMove),
              _capabilityRow('Presets', caps.supportsPresets || presets.isNotEmpty),
              _capabilityRow('Imaging settings', caps.imagingSupported),
              _capabilityRow('Events service', caps.eventsXAddr != null),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (caps.supportsContinuousMove)
          _section(
            title: 'PTZ control',
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ptzButton(Icons.keyboard_arrow_up_rounded, () => _move(tilt: 0.6)),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ptzButton(Icons.keyboard_arrow_left_rounded, () => _move(pan: -0.6)),
                    const SizedBox(width: 10),
                    _ptzButton(Icons.stop_rounded, () async {
                      final c = capabilities;
                      if (c != null) await service.stop(c);
                    }),
                    const SizedBox(width: 10),
                    _ptzButton(Icons.keyboard_arrow_right_rounded, () => _move(pan: 0.6)),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ptzButton(Icons.keyboard_arrow_down_rounded, () => _move(tilt: -0.6)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(onPressed: moving ? null : () => _move(zoom: -0.6), icon: const Icon(Icons.zoom_out_rounded), label: const Text('Zoom out')),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(onPressed: moving ? null : () => _move(zoom: 0.6), icon: const Icon(Icons.zoom_in_rounded), label: const Text('Zoom in')),
                  ],
                ),
              ],
            ),
          ),
        if (caps.supportsContinuousMove) const SizedBox(height: 14),
        if (presets.isNotEmpty)
          _section(
            title: 'PTZ presets',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: presets.map((preset) => ActionChip(label: Text(preset.name), onPressed: () => _gotoPreset(preset))).toList(),
            ),
          ),
        if (presets.isNotEmpty) const SizedBox(height: 14),
        if (caps.imagingSupported)
          _section(
            title: 'Imaging',
            child: imaging == null
                ? const Text('The camera reports an ONVIF Imaging service.', style: TextStyle(color: Colors.white70))
                : Column(
                    children: [
                      _valueRow('Brightness', imaging!.brightness),
                      _valueRow('Contrast', imaging!.contrast),
                      _valueRow('Saturation', imaging!.colorSaturation),
                      _valueRow('Sharpness', imaging!.sharpness),
                    ],
                  ),
          ),
        const SizedBox(height: 14),
        _section(
          title: 'Connection',
          child: Column(
            children: [
              _textRow('Host', widget.host),
              _textRow('HTTP port', '${widget.httpPort}'),
              _textRow('Media', caps.mediaXAddr.toString()),
              _textRow('PTZ', caps.ptzXAddr?.toString() ?? 'Not reported'),
              _textRow('Imaging', caps.imagingXAddr?.toString() ?? 'Not reported'),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Controls are shown only when the connected camera reports the corresponding ONVIF service/capability. Unsupported controls are not simulated.',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }

  Widget _section({required String title, required Widget child}) => Container(
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

  Widget _capabilityRow(String label, bool supported) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(supported ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded, color: supported ? Colors.greenAccent : Colors.white30, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: const TextStyle(color: Colors.white70))),
          ],
        ),
      );

  Widget _ptzButton(IconData icon, VoidCallback onPressed) => Padding(
        padding: const EdgeInsets.all(5),
        child: SizedBox.square(
          dimension: 58,
          child: FilledButton(onPressed: moving ? null : onPressed, child: Icon(icon, size: 30)),
        ),
      );

  Widget _valueRow(String label, double? value) => _textRow(label, value == null ? 'Not reported' : value.toStringAsFixed(1));

  Widget _textRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 105, child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
            Expanded(child: Text(value, style: const TextStyle(color: Colors.white70))),
          ],
        ),
      );
}

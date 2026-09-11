from pathlib import Path

# V112b — reliability guard for the native Dahua controls introduced by V112.
# Dahua is intentionally non-ONVIF in this flow, so refresh must never touch the
# uninitialized ONVIF service. Also make the center Stop button a real action.

p = Path('lib/monitoring/camera_control_page.dart')
s = p.read_text(encoding='utf-8')

old_load = """  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
"""
new_load = """  Future<void> _load() async {
    if (_isDahua) {
      if (mounted) {
        setState(() {
          loading = false;
          error = null;
        });
      }
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
"""
if old_load in s:
    s = s.replace(old_load, new_load, 1)
elif "if (_isDahua) {\n      if (mounted)" not in s:
    raise SystemExit('V112b: Dahua refresh guard anchor missing')

if 'Future<void> _dahuaStop() async {' not in s:
    anchor = '  Future<void> _dahuaMove(String code) async {\n'
    helper = r'''  Future<void> _dahuaStop() async {
    if (moving && mounted) setState(() => moving = false);
    const codes = <String>[
      'Up',
      'Down',
      'Left',
      'Right',
      'ZoomWide',
      'ZoomTele',
    ];
    for (final code in codes) {
      try {
        await nativeConnector.dahuaPtz(
          host: widget.host,
          port: widget.httpPort,
          username: widget.username,
          password: widget.password,
          code: code,
          stop: true,
        );
      } catch (_) {
        // Some firmware only accepts stop for the currently active command.
      }
    }
  }

'''
    if anchor not in s:
        raise SystemExit('V112b: Dahua move helper anchor missing')
    s = s.replace(anchor, helper + anchor, 1)

s = s.replace(
    "_ptzButton(Icons.stop_rounded, () async {}),",
    "_ptzButton(Icons.stop_rounded, _dahuaStop),",
    1,
)
if "_ptzButton(Icons.stop_rounded, _dahuaStop)" not in s:
    raise SystemExit('V112b: real Dahua Stop button wiring missing')

p.write_text(s, encoding='utf-8')

for token in [
    'Future<void> _dahuaStop() async',
    "_ptzButton(Icons.stop_rounded, _dahuaStop)",
    "if (_isDahua)",
]:
    if token not in s:
        raise SystemExit(f'V112b verification missing: {token}')

print('V112b Dahua native control refresh/stop reliability applied')

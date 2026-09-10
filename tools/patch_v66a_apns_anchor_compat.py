from pathlib import Path

# V66 depends on the standard APNs registration/logout anchors. Native
# Codemagic already gets them from V44; GitHub web/analyze jobs intentionally
# start at the later patch chain, so recreate only those harmless Dart anchors
# when they are absent. All APNs methods are iOS-guarded.

app_path = Path('lib/v5_app.dart')
app = app_path.read_text(encoding='utf-8')
reg = "unawaited(VetAlertNotificationService.instance.registerRemotePushForFarm(farm['id']?.toString() ?? ''));"
if reg not in app:
    class_pos = app.find('class _V5DashboardState extends State<V5Dashboard>')
    if class_pos < 0:
        raise SystemExit('V66a: dashboard state marker missing')
    marker = '    farm = Map<String, dynamic>.from(widget.initialFarm);\n'
    marker_pos = app.find(marker, class_pos)
    if marker_pos < 0:
        raise SystemExit('V66a: dashboard farm initialization marker missing')
    app = app[:marker_pos] + app[marker_pos:].replace(
        marker,
        marker + f'    {reg}\n',
        1,
    )
app_path.write_text(app, encoding='utf-8')

backend_path = Path('lib/services/vet_backend.dart')
backend = backend_path.read_text(encoding='utf-8')
if "import 'alert_notification_service.dart';" not in backend:
    anchor = "import 'package:supabase_flutter/supabase_flutter.dart';\n"
    if anchor not in backend:
        raise SystemExit('V66a: backend Supabase import missing')
    backend = backend.replace(
        anchor,
        anchor + "\nimport 'alert_notification_service.dart';\n",
        1,
    )

if 'VetAlertNotificationService.instance.unregisterRemotePush()' not in backend:
    old = '  Future<void> signOut() => client.auth.signOut();'
    new = '''  Future<void> signOut() async {
    await VetAlertNotificationService.instance.unregisterRemotePush();
    await client.auth.signOut();
  }'''
    if old not in backend:
        raise SystemExit('V66a: backend signOut anchor missing')
    backend = backend.replace(old, new, 1)
backend_path.write_text(backend, encoding='utf-8')

print('Vet AI V66a applied: standard APNs Dart anchors available for native CallKit patch')

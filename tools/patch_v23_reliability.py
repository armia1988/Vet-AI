from pathlib import Path
import re


def sub_once(path: str, pattern: str, replacement: str, label: str, flags=0):
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    updated, count = re.subn(pattern, replacement, text, count=1, flags=flags)
    if count != 1:
        raise SystemExit(f'Expected exactly one match for {label} in {path}; got {count}')
    p.write_text(updated, encoding='utf-8')
    print(f'patched: {label}')


# Vet AI's own privacy explanation should appear only once per signed-in account.
sub_once(
    'lib/v5_app.dart',
    r"  Future<bool> _confirmMedia\(ImageSource source\) async \{.*?\n  \}\n\n  Future<void> pick\(ImageSource source\) async \{",
    """  Future<bool> _confirmMedia(ImageSource source) async {
    final userId = VetBackend.instance.currentUser?.id;
    final prefs = await SharedPreferences.getInstance();
    final key = 'vet_ai_scan_privacy_ack_${userId ?? 'signed_out'}';
    if (prefs.getBool(key) == true) return true;

    final isCamera = source == ImageSource.camera;
    final approved = await _confirmAccess(
      title: tr(
        context,
        'Before your first Vet AI scan',
        'قبل أول فحص على Vet AI',
        'Voor je eerste Vet AI-scan',
      ),
      message: tr(
        context,
        'This one-time explanation is saved for this account. Vet AI only uploads an animal image after you choose it and start analysis. iOS or Android may still show their own camera or photo permission when required by the operating system.',
        'الرسالة دي هتظهر مرة واحدة بس للحساب ده. Vet AI مش بيرفع صورة الحيوان إلا بعد ما تختارها وتبدأ التحليل بنفسك. iOS أو Android ممكن يعرضوا إذن النظام للكاميرا أو الصور وقت ما نظام التشغيل يحتاجه.',
        'Deze uitleg verschijnt één keer voor dit account. Vet AI uploadt een dierenfoto pas nadat je die kiest en zelf de analyse start. iOS of Android kan nog een systeempop-up voor camera of foto’s tonen wanneer dat nodig is.',
      ),
      icon: isCamera ? Icons.photo_camera_rounded : Icons.photo_library_rounded,
    );
    if (approved) await prefs.setBool(key, true);
    return approved;
  }

  Future<void> pick(ImageSource source) async {""",
    'one-time per-account scan privacy acknowledgement',
    re.S,
)

# Once the account has acknowledged scan privacy, do not ask again on every analysis.
sub_once(
    'lib/v5_app.dart',
    r"  Future<void> analyze\(\) async \{\n    if \(file == null \|\| bytes == null\) return;\n    final approved = await _confirmAccess\(.*?\n    if \(!approved \|\| !mounted\) return;\n    setState\(\(\) \{",
    """  Future<void> analyze() async {
    if (file == null || bytes == null) return;
    setState(() {""",
    'remove repeated upload confirmation',
    re.S,
)

# The recovered approved artwork is now high-resolution. Render it directly instead of magnifying a tiny bitmap.
sub_once(
    'lib/v5_app.dart',
    r"scale: 1\.9,\n\s+child: Image\.asset\(\n\s+asset,\n\s+width: 220,\n\s+height: 145,",
    """scale: 1.0,
                      child: Image.asset(
                        asset,
                        width: 300,
                        height: 168,""",
    'sharp dashboard animal artwork sizing',
)

# Final report can use provider failover, so the client must not kill a valid request after only 20 seconds.
sub_once(
    'lib/services/vet_case_workflow.dart',
    r"\.timeout\(const Duration\(seconds: 20\)\);",
    ".timeout(const Duration(seconds: 60));",
    'final report client timeout',
)
sub_once(
    'lib/services/vet_case_workflow.dart',
    r"clean\.length > 3900 \? clean\.substring\(0, 3900\) : clean",
    "clean.length > 1800 ? clean.substring(0, 1800) : clean",
    'natural voice text bound',
)
sub_once(
    'lib/services/vet_case_workflow.dart',
    r"\.timeout\(const Duration\(seconds: 24\)\);",
    ".timeout(const Duration(seconds: 40));",
    'natural voice failover timeout',
)

# Arabic should never silently fall back to the robotic device voice. Keep written text available instead.
sub_once(
    'lib/analysis/vet_analysis_report.dart',
    r"    \} catch \(_\) \{\n      // Fall through to the local device voice\.\n    \}\n\n    try \{\n      await _tts\.stop\(\);",
    """    } catch (_) {
      // Natural network voice was unavailable.
    }

    if (widget.languageCode.toLowerCase().startsWith('ar')) return;

    try {
      await _tts.stop();""",
    'disable robotic Arabic device fallback',
)

# Ship as a new build.
sub_once(
    'pubspec.yaml',
    r"version: 0\.6\.8\+20",
    "version: 0.6.9+21",
    'V23 app version',
)

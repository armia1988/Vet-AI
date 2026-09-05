from pathlib import Path
import re


def replace_once(path: str, old: str, new: str, label: str):
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'missing marker for {label} in {path}')
    text = text.replace(old, new, 1)
    p.write_text(text, encoding='utf-8')
    print(f'patched: {label}')


def sub_once(path: str, pattern: str, replacement: str, label: str, flags=0):
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    updated, count = re.subn(pattern, replacement, text, count=1, flags=flags)
    if count != 1:
        raise SystemExit(f'expected one match for {label} in {path}; got {count}')
    p.write_text(updated, encoding='utf-8')
    print(f'patched: {label}')


# Persist Vet AI's own privacy acknowledgement at account level, not only on one device.
insert_marker = "  Future<void> updateProfile({\n"
backend_methods = """  Future<bool> scanPrivacyAcknowledged() async {
    final user = currentUser;
    if (user == null) return false;
    final rows = await client
        .from('profiles')
        .select('scan_privacy_acknowledged_at')
        .eq('id', user.id)
        .limit(1);
    return rows.isNotEmpty && rows.first['scan_privacy_acknowledged_at'] != null;
  }

  Future<void> acknowledgeScanPrivacy() async {
    final user = currentUser;
    if (user == null) throw StateError('You must be signed in.');
    await client
        .from('profiles')
        .update({'scan_privacy_acknowledged_at': DateTime.now().toIso8601String()})
        .eq('id', user.id);
  }

"""
replace_once('lib/services/vet_backend.dart', insert_marker, backend_methods + insert_marker, 'account-level scan privacy backend methods')

sub_once(
    'lib/v5_app.dart',
    r"  Future<bool> _confirmMedia\(ImageSource source\) async \{.*?\n  \}\n\n  Future<void> pick\(ImageSource source\) async \{",
    """  Future<bool> _confirmMedia(ImageSource source) async {
    final userId = VetBackend.instance.currentUser?.id;
    final prefs = await SharedPreferences.getInstance();
    final key = 'vet_ai_scan_privacy_ack_${userId ?? 'signed_out'}';
    if (prefs.getBool(key) == true) return true;

    try {
      if (await VetBackend.instance.scanPrivacyAcknowledged()) {
        await prefs.setBool(key, true);
        return true;
      }
    } catch (_) {
      // A temporary profile read problem must not block the picker.
    }

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
        'This one-time explanation is saved to your Vet AI account. Vet AI only uploads an animal image after you choose it and start analysis. iOS or Android may still show their own camera or photo permission when required by the operating system.',
        'الرسالة دي هتظهر مرة واحدة بس للحساب ده وهنحفظ الموافقة على حساب Vet AI نفسه. Vet AI مش بيرفع صورة الحيوان إلا بعد ما تختارها وتبدأ التحليل بنفسك. iOS أو Android ممكن يعرضوا إذن النظام للكاميرا أو الصور وقت ما نظام التشغيل يحتاجه.',
        'Deze uitleg verschijnt één keer per Vet AI-account en wordt op het account opgeslagen. Vet AI uploadt een dierenfoto pas nadat je die kiest en zelf de analyse start. iOS of Android kan nog een systeempop-up voor camera of foto’s tonen wanneer dat nodig is.',
      ),
      icon: isCamera ? Icons.photo_camera_rounded : Icons.photo_library_rounded,
    );
    if (approved) {
      await prefs.setBool(key, true);
      try {
        await VetBackend.instance.acknowledgeScanPrivacy();
      } catch (_) {
        // Local acknowledgement still prevents repeated dialogs on this device.
      }
    }
    return approved;
  }

  Future<void> pick(ImageSource source) async {""",
    'one-time scan privacy per account',
    re.S,
)

# Use a fallback Gemini model that is available on the current account.
replace_once(
    'supabase/functions/analyze-case/index.ts',
    'const FALLBACK_MODEL = Deno.env.get("VET_AI_GEMINI_ANALYSIS_FALLBACK_MODEL") ?? "gemini-2.5-flash";',
    'const FALLBACK_MODEL = Deno.env.get("VET_AI_GEMINI_ANALYSIS_FALLBACK_MODEL") ?? "gemini-3.5-flash-lite";',
    'analysis fallback Gemini model',
)
replace_once(
    'supabase/functions/finalize-case-report/index.ts',
    'const FALLBACK_MODEL = Deno.env.get("VET_AI_GEMINI_FINAL_FALLBACK_MODEL") ?? "gemini-2.5-flash";',
    'const FALLBACK_MODEL = Deno.env.get("VET_AI_GEMINI_FINAL_FALLBACK_MODEL") ?? "gemini-3.5-flash-lite";',
    'final report fallback Gemini model',
)
replace_once(
    'supabase/functions/case-voice/index.ts',
    'const PRIMARY_MODEL = Deno.env.get("VET_AI_GEMINI_TTS_MODEL") ?? "gemini-2.5-flash-preview-tts";\nconst FALLBACK_MODEL = Deno.env.get("VET_AI_GEMINI_TTS_FALLBACK_MODEL") ?? "gemini-3.1-flash-tts-preview";',
    'const PRIMARY_MODEL = Deno.env.get("VET_AI_GEMINI_TTS_MODEL") ?? "gemini-3.1-flash-tts-preview";\nconst FALLBACK_MODEL = Deno.env.get("VET_AI_GEMINI_TTS_FALLBACK_MODEL") ?? "gemini-2.5-flash-preview-tts";',
    'natural voice primary Gemini model',
)

# Build-time enhancement keeps the approved animal artwork but removes the 128px blur.
marker = "      - name: Generate Vet AI launcher icons\n"
enhancement_step = """      - name: Enhance approved Vet AI animal icons
        script: |
          python3 -m pip install --quiet pillow
          python3 - <<'PY'
          from PIL import Image, ImageEnhance, ImageFilter
          from pathlib import Path

          for raw in [
              'assets/icons/livestock_final.png',
              'assets/icons/poultry_final.png',
              'assets/icons/dog_final.png',
          ]:
              path = Path(raw)
              image = Image.open(path).convert('RGBA')
              alpha = image.getchannel('A')
              bbox = alpha.getbbox()
              if bbox:
                  image = image.crop(bbox)
              alpha = image.getchannel('A')
              rgb = image.convert('RGB')
              rgb = ImageEnhance.Color(rgb).enhance(1.35)
              rgb = ImageEnhance.Contrast(rgb).enhance(1.18)
              rgb = ImageEnhance.Sharpness(rgb).enhance(2.5)
              rgb = rgb.filter(ImageFilter.UnsharpMask(radius=1.2, percent=190, threshold=2))

              target = 900
              scale = min(target / rgb.width, target / rgb.height)
              size = (max(1, round(rgb.width * scale)), max(1, round(rgb.height * scale)))
              rgb = rgb.resize(size, Image.Resampling.LANCZOS)
              alpha = alpha.resize(size, Image.Resampling.LANCZOS)
              alpha = alpha.point(lambda x: 0 if x < 5 else min(255, round(x * 1.08)))
              art = rgb.convert('RGBA')
              art.putalpha(alpha)

              canvas = Image.new('RGBA', (1024, 1024), (255, 255, 255, 0))
              x = (1024 - art.width) // 2
              y = (1024 - art.height) // 2
              canvas.alpha_composite(art, (x, y))
              canvas.save(path, optimize=True)
              print(f'Enhanced {path}: {image.size} -> {canvas.size}')
          PY
"""
replace_once('codemagic.yaml', marker, enhancement_step + marker, 'high-resolution approved animal icon build step')

replace_once('pubspec.yaml', 'version: 0.6.9+21', 'version: 0.6.10+22', 'release version 0.6.10')

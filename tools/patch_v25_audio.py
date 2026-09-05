from pathlib import Path


def require_replace(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise SystemExit(f"Missing expected marker for {label} in {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


report = Path("lib/analysis/vet_analysis_report.dart")
require_replace(
    report,
    "if (normalized == 'ar') return 'ar-SA';",
    "if (normalized == 'ar') return 'ar-EG';",
    "Egyptian Arabic device locale",
)
require_replace(
    report,
    "    if (widget.languageCode.toLowerCase().startsWith('ar')) return;\n\n",
    "",
    "remove Arabic silent exit",
)
require_replace(
    report,
    "      await _tts.setLanguage(_speechLanguage(widget.languageCode));\n      await _tts.setSpeechRate(.47);",
    """      final isArabic = widget.languageCode.toLowerCase().startsWith('ar');
      if (isArabic) {
        var configured = false;
        for (final locale in const ['ar-EG', 'ar-SA', 'ar']) {
          try {
            final result = await _tts.setLanguage(locale);
            if (result != false) {
              configured = true;
              break;
            }
          } catch (_) {
            // Try the next Arabic locale available on this device.
          }
        }
        if (!configured) {
          await _tts.setLanguage('ar-SA');
        }
      } else {
        await _tts.setLanguage(_speechLanguage(widget.languageCode));
      }
      await _tts.setVolume(1.0);
      await _tts.setSpeechRate(.47);""",
    "Arabic device TTS fallback",
)

voice = Path("supabase/functions/case-voice/index.ts")
require_replace(
    voice,
    "              languageCode: languageCode(language),\n              voiceConfig: { prebuiltVoiceConfig: { voiceName: \"Sulafat\" } },",
    """              // Gemini Developer API TTS auto-detects the input language.
              // Its generateContent SpeechConfig accepts voiceConfig here; adding
              // languageCode causes provider-side request rejection on this API.
              voiceConfig: { prebuiltVoiceConfig: { voiceName: \"Sulafat\" } },""",
    "Gemini TTS speechConfig",
)

pubspec = Path("pubspec.yaml")
require_replace(
    pubspec,
    "version: 0.6.10+22",
    "version: 0.6.11+23",
    "release version",
)

print("V25 audio patch applied")

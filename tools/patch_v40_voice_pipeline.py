from pathlib import Path

REPORT = Path('lib/analysis/vet_analysis_report.dart')
text = REPORT.read_text(encoding='utf-8')

# Cancellation token so tapping the speaker OFF cannot leave an old queued
# request able to resume playback later.
field_marker = '  bool _finalizing = false;\n'
if 'int _speechRequestId = 0;' not in text:
    if field_marker not in text:
        raise SystemExit('0.6.24 voice pipeline: state field marker not found')
    text = text.replace(field_marker, field_marker + '  int _speechRequestId = 0;\n', 1)

start_marker = '  Future<void> _speakCurrent() async {'
end_marker = '  Future<void> _toggleMute() async {'
start = text.find(start_marker)
end = text.find(end_marker)
if start < 0 or end < 0 or end <= start:
    raise SystemExit('0.6.24 voice pipeline: speak/toggle boundaries not found')

replacement = r'''  String _buildSpokenReportText() {
    final parts = <String>[];
    final summary = (_result['summary'] ?? '').toString().trim();
    if (summary.isNotEmpty) parts.add(summary);

    if (_isFinal) {
      final primary = _result['primary_condition'] is Map
          ? Map<String, dynamic>.from(_result['primary_condition'] as Map)
          : <String, dynamic>{};
      final name = (primary['name'] ?? '').toString().trim();
      if (name.isNotEmpty) {
        parts.add(widget.translate(
          'Most likely condition: $name',
          'أقرب احتمال للحالة هو $name',
          'Meest waarschijnlijke aandoening: $name',
        ));
      }
      final cause = (_result['cause'] ?? '').toString().trim();
      if (cause.isNotEmpty) {
        parts.add(widget.translate('Cause: $cause', 'السبب: $cause', 'Oorzaak: $cause'));
      }
      final now = _strings(_result['what_to_do_now']);
      if (now.isNotEmpty) {
        parts.add(widget.translate(
          'What you should do now. ${now.join('. ')}',
          'تعمل إيه دلوقتي. ${now.join('. ')}',
          'Wat je nu moet doen. ${now.join('. ')}',
        ));
      }
      final treatment = _strings(_result['treatment_and_management']);
      if (treatment.isNotEmpty) {
        parts.add(widget.translate(
          'Treatment and management. ${treatment.join('. ')}',
          'العلاج والتعامل. ${treatment.join('. ')}',
          'Behandeling en management. ${treatment.join('. ')}',
        ));
      }
      final redFlags = _strings(_result['red_flags']);
      if (redFlags.isNotEmpty) {
        parts.add(widget.translate(
          'Danger signs. ${redFlags.join('. ')}',
          'علامات الخطر. ${redFlags.join('. ')}',
          'Alarmsignalen. ${redFlags.join('. ')}',
        ));
      }
    } else {
      final differentials = _maps(_result['differential_diagnoses']);
      if (differentials.isNotEmpty) {
        final top = differentials.first;
        final name = (top['name'] ?? '').toString().trim();
        if (name.isNotEmpty) {
          parts.add(widget.translate(
            'Most likely at this stage: $name',
            'أقرب احتمال دلوقتي هو $name',
            'Meest waarschijnlijk in deze fase: $name',
          ));
        }
      }
      final actions = _strings(_result['immediate_actions']);
      if (actions.isNotEmpty) {
        parts.add(widget.translate(
          'What to do now. ${actions.join('. ')}',
          'تعمل إيه دلوقتي. ${actions.join('. ')}',
          'Wat je nu moet doen. ${actions.join('. ')}',
        ));
      }
    }

    return parts.join('. ');
  }

  List<String> _splitVoiceChunks(String input, {int maxChars = 520}) {
    final clean = input.trim();
    if (clean.isEmpty) return const <String>[];
    if (clean.length <= maxChars) return <String>[clean];

    final pieces = RegExp(r'[^.!؟]+[.!؟]?')
        .allMatches(clean)
        .map((m) => (m.group(0) ?? '').trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final chunks = <String>[];
    var current = '';

    void flush() {
      final value = current.trim();
      if (value.isNotEmpty) chunks.add(value);
      current = '';
    }

    for (final piece in pieces) {
      if (piece.length > maxChars) {
        flush();
        final words = piece.split(RegExp(r'\s+'));
        var longPart = '';
        for (final word in words) {
          final candidate = longPart.isEmpty ? word : '$longPart $word';
          if (candidate.length > maxChars && longPart.isNotEmpty) {
            chunks.add(longPart.trim());
            longPart = word;
          } else {
            longPart = candidate;
          }
        }
        if (longPart.trim().isNotEmpty) chunks.add(longPart.trim());
        continue;
      }
      final candidate = current.isEmpty ? piece : '$current $piece';
      if (candidate.length > maxChars && current.isNotEmpty) {
        flush();
        current = piece;
      } else {
        current = candidate;
      }
    }
    flush();
    return chunks;
  }

  Future<void> _playVoiceBytes(List<int> natural, int requestId, int index) async {
    if (_muted || !mounted || requestId != _speechRequestId) return;
    final isWav = natural.length >= 12 &&
        natural[0] == 0x52 && natural[1] == 0x49 &&
        natural[2] == 0x46 && natural[3] == 0x46;
    final tempDir = await getTemporaryDirectory();
    final voiceFile = File(
      '${tempDir.path}/vet_ai_voice_${requestId}_$index.${isWav ? 'wav' : 'mp3'}',
    );
    await voiceFile.writeAsBytes(natural, flush: true);
    await VetBackend.instance.logVoiceClientEvent(
      stage: 'audio_player_start',
      route: 'device_file_pipeline',
      detail: 'chunk=$index; audio_bytes=${natural.length}; file=${voiceFile.path}',
      appVersion: '0.6.24',
    );
    final completed = _audio.onPlayerComplete.first;
    await _audio.setPlayerMode(PlayerMode.mediaPlayer);
    await _audio.setReleaseMode(ReleaseMode.stop);
    await _audio.play(DeviceFileSource(voiceFile.path));
    await VetBackend.instance.logVoiceClientEvent(
      stage: 'audio_player_started',
      route: 'device_file_pipeline',
      detail: 'chunk=$index; audio_bytes=${natural.length}',
      appVersion: '0.6.24',
    );
    try {
      await completed.timeout(const Duration(seconds: 90));
    } catch (_) {}
  }

  Future<void> _speakCurrent() async {
    if (_muted || !mounted) return;
    final requestId = ++_speechRequestId;

    var text = _buildSpokenReportText();
    if (widget.languageCode.toLowerCase().startsWith('ar')) {
      text = _egyptianSpeechText(text);
    }
    text = _speechSafeText(text);
    final chunks = _splitVoiceChunks(text);
    if (chunks.isEmpty) {
      if (mounted) setState(() => _muted = true);
      return;
    }

    try {
      await _audio.stop();
      await _tts.stop();

      // Request only the first short chunk before playback. As soon as it is
      // ready, start it and prefetch the next chunk while the current one talks.
      var pending = VetBackend.instance.naturalCaseVoice(
        text: chunks.first,
        language: widget.languageCode,
      );

      for (var i = 0; i < chunks.length; i++) {
        final natural = await pending;
        if (_muted || !mounted || requestId != _speechRequestId) return;
        if (natural == null || natural.isEmpty) {
          throw StateError('voice_chunk_${i + 1}_empty');
        }

        if (i + 1 < chunks.length) {
          pending = VetBackend.instance.naturalCaseVoice(
            text: chunks[i + 1],
            language: widget.languageCode,
          );
        }

        await _playVoiceBytes(natural, requestId, i + 1);
        if (_muted || !mounted || requestId != _speechRequestId) return;
      }
      return;
    } catch (e) {
      try {
        await VetBackend.instance.logVoiceClientEvent(
          stage: 'voice_pipeline_error',
          route: 'device_file_pipeline',
          detail: e.toString(),
          appVersion: '0.6.24',
        );
      } catch (_) {}
    }

    if (mounted && !_muted && requestId == _speechRequestId) {
      setState(() => _muted = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.translate(
            'Natural voice could not continue. Tap the speaker to retry.',
            'الصوت الطبيعي ماقدرش يكمل. اضغط على السماعة وجرب تاني.',
            'De natuurlijke stem kon niet doorgaan. Tik op de luidspreker om opnieuw te proberen.',
          )),
        ),
      );
    }
  }

'''

text = text[:start] + replacement + text[end:]

# Make OFF immediately invalidate any prefetched chunk.
toggle_old = """    if (!_muted) {
      setState(() => _muted = true);
      await _audio.stop();
      await _tts.stop();
      return;
    }

    setState(() => _muted = false);
    await _speakCurrent();
"""
toggle_new = """    if (!_muted) {
      _speechRequestId++;
      setState(() => _muted = true);
      await _audio.stop();
      await _tts.stop();
      return;
    }

    setState(() => _muted = false);
    await _speakCurrent();
"""
if toggle_old in text:
    text = text.replace(toggle_old, toggle_new, 1)
elif '_speechRequestId++;' not in text:
    raise SystemExit('0.6.24 voice pipeline: toggle cancellation marker not installed')

REPORT.write_text(text, encoding='utf-8')
check = REPORT.read_text(encoding='utf-8')
for marker in (
    '_buildSpokenReportText()',
    '_splitVoiceChunks',
    'actions.join',
    'device_file_pipeline',
    'chunks[i + 1]',
    '_speechRequestId',
):
    if marker not in check:
        raise SystemExit(f'0.6.24 voice pipeline verification missing: {marker}')
if "String text = (_result['voice_summary']" in check:
    raise SystemExit('0.6.24 voice pipeline regression: old partial voice_summary path still active')
print('Vet AI 0.6.24 fast complete pipelined voice installed')

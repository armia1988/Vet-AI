from pathlib import Path
import math
import struct
import wave

# Vet AI V47 — generate and bundle two native iOS notification sounds.
# Orange: short two-tone warning.
# Red: rapid repeated emergency "tr-tr-tr-tr" alarm.

runner = Path('ios/Runner')
runner.mkdir(parents=True, exist_ok=True)

SAMPLE_RATE = 11025


def write_wav(path: Path, samples: list[float]) -> None:
    peak = max((abs(v) for v in samples), default=1.0) or 1.0
    with wave.open(str(path), 'wb') as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        frames = bytearray()
        for value in samples:
            scaled = max(-1.0, min(1.0, (value / peak) * 0.84))
            frames.extend(struct.pack('<h', int(scaled * 32767)))
        wav.writeframes(bytes(frames))


def orange_sound() -> list[float]:
    duration = 1.55
    total = int(SAMPLE_RATE * duration)
    out: list[float] = []
    for i in range(total):
        t = i / SAMPLE_RATE
        value = 0.0
        for start, freq, decay, amp in [
            (0.00, 587.33, 0.34, 0.58),
            (0.27, 698.46, 0.48, 0.68),
        ]:
            if t >= start:
                x = t - start
                env = math.exp(-x / decay)
                value += amp * env * (
                    math.sin(2 * math.pi * freq * x)
                    + 0.24 * math.sin(2 * math.pi * (freq * 2.01) * x)
                )
        if t < 0.018:
            value *= t / 0.018
        if t > duration - 0.10:
            value *= max(0.0, (duration - t) / 0.10)
        out.append(value)
    return out


def red_sound() -> list[float]:
    duration = 2.55
    total = int(SAMPLE_RATE * duration)
    out: list[float] = [0.0] * total
    on = 0.080
    off = 0.045
    period = on + off
    bursts = int(duration / period) + 1
    for burst in range(bursts):
        start = burst * period
        freq = 930.0 if burst % 2 == 0 else 1080.0
        start_i = int(start * SAMPLE_RATE)
        end_i = min(total, int((start + on) * SAMPLE_RATE))
        for i in range(start_i, end_i):
            x = (i / SAMPLE_RATE) - start
            attack = min(1.0, x / 0.006)
            release = min(1.0, max(0.0, (on - x) / 0.010))
            env = max(0.0, attack * release)
            out[i] += env * (
                math.sin(2 * math.pi * freq * x)
                + 0.35 * math.sin(2 * math.pi * (freq * 1.5) * x)
                + 0.10 * math.sin(2 * math.pi * 230.0 * x)
            )
    return out


orange_name = 'vet_ai_orange_alert.wav'
red_name = 'vet_ai_red_trtr_alert.wav'
write_wav(runner / orange_name, orange_sound())
write_wav(runner / red_name, red_sound())

pbx_path = Path('ios/Runner.xcodeproj/project.pbxproj')
pbx = pbx_path.read_text(encoding='utf-8')

# Stable 24-character Xcode object IDs reserved for Vet AI V47.
ORANGE_FILE = 'A14700000000000000000001'
ORANGE_BUILD = 'A14700000000000000000002'
RED_FILE = 'A14700000000000000000003'
RED_BUILD = 'A14700000000000000000004'

if ORANGE_FILE not in pbx:
    build_marker = '/* Begin PBXBuildFile section */\n'
    file_marker = '/* Begin PBXFileReference section */\n'
    if build_marker not in pbx or file_marker not in pbx:
        raise SystemExit('V47 sounds: expected Xcode PBX sections were not found')

    pbx = pbx.replace(
        build_marker,
        build_marker
        + f'\t\t{ORANGE_BUILD} /* {orange_name} in Resources */ = {{isa = PBXBuildFile; fileRef = {ORANGE_FILE} /* {orange_name} */; }};\n'
        + f'\t\t{RED_BUILD} /* {red_name} in Resources */ = {{isa = PBXBuildFile; fileRef = {RED_FILE} /* {red_name} */; }};\n',
        1,
    )
    pbx = pbx.replace(
        file_marker,
        file_marker
        + f'\t\t{ORANGE_FILE} /* {orange_name} */ = {{isa = PBXFileReference; lastKnownFileType = audio.wav; path = {orange_name}; sourceTree = "<group>"; }};\n'
        + f'\t\t{RED_FILE} /* {red_name} */ = {{isa = PBXFileReference; lastKnownFileType = audio.wav; path = {red_name}; sourceTree = "<group>"; }};\n',
        1,
    )

    # Add files to the Runner group.
    runner_group_candidates = [
        '97C146E51CF9000F007C117D /* Runner */ = {',
        '/* Runner */ = {',
    ]
    group_pos = -1
    for marker in runner_group_candidates:
        group_pos = pbx.find(marker)
        if group_pos >= 0:
            break
    if group_pos < 0:
        raise SystemExit('V47 sounds: Runner PBXGroup not found')
    children_pos = pbx.find('children = (', group_pos)
    if children_pos < 0:
        raise SystemExit('V47 sounds: Runner group children list not found')
    insert_pos = pbx.find('\n', children_pos) + 1
    pbx = (
        pbx[:insert_pos]
        + f'\t\t\t\t{ORANGE_FILE} /* {orange_name} */,\n'
        + f'\t\t\t\t{RED_FILE} /* {red_name} */,\n'
        + pbx[insert_pos:]
    )

    # Add both sounds to the first Resources build phase for Runner.
    resources_section = pbx.find('isa = PBXResourcesBuildPhase;')
    if resources_section < 0:
        raise SystemExit('V47 sounds: PBXResourcesBuildPhase not found')
    files_pos = pbx.find('files = (', resources_section)
    if files_pos < 0:
        raise SystemExit('V47 sounds: resources files list not found')
    insert_pos = pbx.find('\n', files_pos) + 1
    pbx = (
        pbx[:insert_pos]
        + f'\t\t\t\t{ORANGE_BUILD} /* {orange_name} in Resources */,\n'
        + f'\t\t\t\t{RED_BUILD} /* {red_name} in Resources */,\n'
        + pbx[insert_pos:]
    )

    pbx_path.write_text(pbx, encoding='utf-8')

# Final build-time guard.
pbx = pbx_path.read_text(encoding='utf-8')
for sound_name in [orange_name, red_name]:
    if not (runner / sound_name).exists() or sound_name not in pbx:
        raise SystemExit(f'V47 sounds: failed to bundle {sound_name}')

print('Vet AI V47 custom orange/red iOS notification sounds bundled')

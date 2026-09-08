from pathlib import Path
import re
import subprocess

# Vet AI V48 — convert the V47 WAV sounds to Apple CAF and attach them to the
# Runner target's *actual* Resources build phase. V47 used the first resources
# phase it found, which can belong to another target on newer generated Xcode
# projects. iOS falls back to the default notification tone whenever a custom
# sound file is missing or cannot be resolved from the app bundle.

runner = Path('ios/Runner')
pbx_path = Path('ios/Runner.xcodeproj/project.pbxproj')

orange_wav = runner / 'vet_ai_orange_alert.wav'
red_wav = runner / 'vet_ai_red_trtr_alert.wav'
if not orange_wav.exists() or not red_wav.exists():
    raise SystemExit('V48 sounds: V47 WAV source files are missing')

orange_name = 'vet_ai_orange_alert.caf'
red_name = 'vet_ai_red_trtr_alert.caf'
orange_caf = runner / orange_name
red_caf = runner / red_name

# CAF/IMA4 is a native Apple notification-sound format.
for source, target in [(orange_wav, orange_caf), (red_wav, red_caf)]:
    subprocess.run(
        ['afconvert', '-f', 'caff', '-d', 'ima4', str(source), str(target)],
        check=True,
    )
    if not target.exists() or target.stat().st_size < 256:
        raise SystemExit(f'V48 sounds: failed to create {target.name}')

pbx = pbx_path.read_text(encoding='utf-8')

# Stable Xcode object ids for V48.
ORANGE_FILE = 'A14800000000000000000001'
ORANGE_BUILD = 'A14800000000000000000002'
RED_FILE = 'A14800000000000000000003'
RED_BUILD = 'A14800000000000000000004'

# File references use SOURCE_ROOT so they resolve to ios/Runner/<file> even if
# Xcode changes the visible group layout.
if ORANGE_FILE not in pbx:
    file_marker = '/* Begin PBXFileReference section */\n'
    build_marker = '/* Begin PBXBuildFile section */\n'
    if file_marker not in pbx or build_marker not in pbx:
        raise SystemExit('V48 sounds: PBX file/build sections not found')

    pbx = pbx.replace(
        file_marker,
        file_marker
        + f'\t\t{ORANGE_FILE} /* {orange_name} */ = {{isa = PBXFileReference; lastKnownFileType = file; path = Runner/{orange_name}; sourceTree = SOURCE_ROOT; }};\n'
        + f'\t\t{RED_FILE} /* {red_name} */ = {{isa = PBXFileReference; lastKnownFileType = file; path = Runner/{red_name}; sourceTree = SOURCE_ROOT; }};\n',
        1,
    )
    pbx = pbx.replace(
        build_marker,
        build_marker
        + f'\t\t{ORANGE_BUILD} /* {orange_name} in Resources */ = {{isa = PBXBuildFile; fileRef = {ORANGE_FILE} /* {orange_name} */; }};\n'
        + f'\t\t{RED_BUILD} /* {red_name} in Resources */ = {{isa = PBXBuildFile; fileRef = {RED_FILE} /* {red_name} */; }};\n',
        1,
    )

# Locate the Runner native target and its build phases.
target_match = re.search(
    r'(?P<id>[A-F0-9]{24}) /\* Runner \*/ = \{\s*isa = PBXNativeTarget;(?P<body>.*?)\n\s*\};',
    pbx,
    re.S,
)
if not target_match:
    raise SystemExit('V48 sounds: Runner PBXNativeTarget not found')

target_body = target_match.group('body')
phases_match = re.search(r'buildPhases = \((.*?)\);', target_body, re.S)
if not phases_match:
    raise SystemExit('V48 sounds: Runner buildPhases list not found')
phase_ids = re.findall(r'([A-F0-9]{24}) /\*', phases_match.group(1))

runner_resources_id = None
runner_resources_block = None
for phase_id in phase_ids:
    m = re.search(
        rf'{re.escape(phase_id)} /\*.*?\*/ = \{{(?P<body>.*?)\n\s*\}};',
        pbx,
        re.S,
    )
    if m and 'isa = PBXResourcesBuildPhase;' in m.group('body'):
        runner_resources_id = phase_id
        runner_resources_block = m.group(0)
        break

if not runner_resources_id or not runner_resources_block:
    raise SystemExit('V48 sounds: Runner Resources build phase not found')

if ORANGE_BUILD not in runner_resources_block:
    files_marker = 'files = (\n'
    if files_marker not in runner_resources_block:
        raise SystemExit('V48 sounds: Runner resources files list not found')
    patched_block = runner_resources_block.replace(
        files_marker,
        files_marker
        + f'\t\t\t\t{ORANGE_BUILD} /* {orange_name} in Resources */,\n'
        + f'\t\t\t\t{RED_BUILD} /* {red_name} in Resources */,\n',
        1,
    )
    pbx = pbx.replace(runner_resources_block, patched_block, 1)

pbx_path.write_text(pbx, encoding='utf-8')

# Build-time source guard. A second guard in codemagic.yaml inspects the final
# signed IPA and refuses upload unless both CAF files are at the app-bundle root.
final_pbx = pbx_path.read_text(encoding='utf-8')
for path, name, build_id in [
    (orange_caf, orange_name, ORANGE_BUILD),
    (red_caf, red_name, RED_BUILD),
]:
    if not path.exists() or name not in final_pbx or build_id not in final_pbx:
        raise SystemExit(f'V48 sounds: bundle configuration incomplete for {name}')

print(f'Vet AI V48 CAF notification sounds attached to Runner resources phase {runner_resources_id}')

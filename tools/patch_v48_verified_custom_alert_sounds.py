from pathlib import Path
import subprocess

# Vet AI V48 — convert the V47 WAV sounds to Apple CAF and attach them to the
# Runner target using Xcodeproj itself instead of parsing project.pbxproj with
# brittle regexes. This works with the newer Flutter-generated iOS project
# structure used by Codemagic.

runner = Path('ios/Runner')
project_path = Path('ios/Runner.xcodeproj')

orange_wav = runner / 'vet_ai_orange_alert.wav'
red_wav = runner / 'vet_ai_red_trtr_alert.wav'
if not orange_wav.exists() or not red_wav.exists():
    raise SystemExit('V48 sounds: V47 WAV source files are missing')

orange_name = 'vet_ai_orange_alert.caf'
red_name = 'vet_ai_red_trtr_alert.caf'
orange_caf = runner / orange_name
red_caf = runner / red_name

# CAF/IMA4 is a native Apple notification-sound format supported by iOS.
for source, target in [(orange_wav, orange_caf), (red_wav, red_caf)]:
    subprocess.run(
        ['afconvert', '-f', 'caff', '-d', 'ima4', str(source), str(target)],
        check=True,
    )
    if not target.exists() or target.stat().st_size < 256:
        raise SystemExit(f'V48 sounds: failed to create {target.name}')

# Codemagic macOS images normally include CocoaPods/Xcodeproj already. If the
# gem is missing, install only this tiny dependency rather than guessing PBX IDs.
probe = subprocess.run(
    ['ruby', '-e', "require 'xcodeproj'"],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)
if probe.returncode != 0:
    subprocess.run(['gem', 'install', 'xcodeproj', '--no-document'], check=True)

ruby_script = r'''
require 'xcodeproj'

project = Xcodeproj::Project.open('ios/Runner.xcodeproj')
target = project.targets.find { |t| t.name == 'Runner' }
abort 'V48 sounds: Runner target not found' unless target

runner_group = project.main_group.groups.find do |g|
  g.display_name == 'Runner' || g.path == 'Runner'
end
abort 'V48 sounds: Runner group not found' unless runner_group

names = ['vet_ai_orange_alert.caf', 'vet_ai_red_trtr_alert.caf']

names.each do |name|
  file_ref = project.files.find do |f|
    f.path == name || f.path == "Runner/#{name}"
  end

  file_ref ||= runner_group.new_file(name)

  unless target.resources_build_phase.files_references.include?(file_ref)
    target.resources_build_phase.add_file_reference(file_ref, true)
  end
end

project.save

resource_paths = target.resources_build_phase.files_references.map(&:path)
names.each do |name|
  unless resource_paths.include?(name) || resource_paths.include?("Runner/#{name}")
    abort "V48 sounds: #{name} was not attached to Runner Resources"
  end
end

puts "Vet AI V48 Xcode resources verified: #{names.join(', ')}"
'''

subprocess.run(['ruby', '-e', ruby_script], check=True)

# Source-side guard. codemagic.yaml performs the stronger final guard after the
# signed IPA is built and refuses upload if either CAF file is absent from the
# .app bundle root.
for path in [orange_caf, red_caf]:
    if not path.exists() or path.stat().st_size < 256:
        raise SystemExit(f'V48 sounds: generated sound is invalid: {path.name}')

print('Vet AI V48 custom CAF notification sounds attached to Runner via Xcodeproj')

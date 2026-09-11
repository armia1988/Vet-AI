from pathlib import Path
import plistlib

for patch_name in [
    'tools/patch_v108_camera_vendor_profiles.py',
    'tools/patch_v109_dmss_camera_connect.py',
    'tools/patch_v111_dahua_direct_camera_hub.py',
    'tools/patch_v112_dahua_live_and_controls.py',
    'tools/patch_v112b_dahua_control_reliability.py',
]:
    patch = Path(patch_name)
    if not patch.exists():
        raise SystemExit(f'Camera release patch is missing: {patch_name}')
    source = patch.read_text(encoding='utf-8')
    # V112 runtime code uses `final path = ...`; its original release guard
    # accidentally looked for `path: ...` and stopped CI before analysis.
    # Correct only that verifier token while keeping the runtime patch intact.
    if patch_name == 'tools/patch_v112_dahua_live_and_controls.py':
        source = source.replace(
            '"path: \'/cgi-bin/ptz.cgi"',
            '"final path = \'/cgi-bin/ptz.cgi"',
        )
    exec(compile(source, str(patch), 'exec'))

# App Store Connect ITMS-90683 hardening. Some linked iOS location APIs are
# detected statically even though Vet AI normally requests foreground location.
# Keep both modern location purpose strings in the final Runner Info.plist so
# App Store Connect can validate the binary without a missing-purpose warning.
plist_path = Path('ios/Runner/Info.plist')
if not plist_path.exists():
    raise SystemExit('V110: ios/Runner/Info.plist is missing')

with plist_path.open('rb') as f:
    info = plistlib.load(f)

info['NSLocationWhenInUseUsageDescription'] = (
    'Vet AI uses your location, after your approval, while you use the app to '
    'provide location-aware veterinary guidance and nearby services.'
)
info['NSLocationAlwaysAndWhenInUseUsageDescription'] = (
    'Vet AI uses location only for features you explicitly enable that require '
    'location-aware veterinary guidance or nearby services, including when iOS '
    'allows those features to continue outside the foreground.'
)

with plist_path.open('wb') as f:
    plistlib.dump(info, f)

print('V110/V111/V112 iOS privacy, Dahua live and native camera controls applied')

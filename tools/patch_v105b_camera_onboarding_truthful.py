from pathlib import Path
import plistlib

for patch_name in [
    'tools/patch_v108_camera_vendor_profiles.py',
    'tools/patch_v109_dmss_camera_connect.py',
]:
    patch = Path(patch_name)
    if not patch.exists():
        raise SystemExit(f'Camera release patch is missing: {patch_name}')
    exec(compile(patch.read_text(encoding='utf-8'), str(patch), 'exec'))

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

print('V110 iOS privacy purpose strings applied')

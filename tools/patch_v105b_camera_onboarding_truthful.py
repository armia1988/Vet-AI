from pathlib import Path

for patch_name in [
    'tools/patch_v108_camera_vendor_profiles.py',
    'tools/patch_v109_dmss_camera_connect.py',
]:
    patch = Path(patch_name)
    if not patch.exists():
        raise SystemExit(f'Camera release patch is missing: {patch_name}')
    exec(compile(patch.read_text(encoding='utf-8'), str(patch), 'exec'))

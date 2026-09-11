from pathlib import Path

patch = Path('tools/patch_v108_camera_vendor_profiles.py')
if not patch.exists():
    raise SystemExit('V108 camera vendor profile patch is missing')
exec(compile(patch.read_text(encoding='utf-8'), str(patch), 'exec'))

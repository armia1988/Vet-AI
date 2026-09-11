from pathlib import Path

files = [
    Path('codemagic.yaml'),
    Path('.github/workflows/ios-v96-release-readiness.yml'),
    Path('.github/workflows/ios-v84-camera-discovery-check.yml'),
]

for p in files:
    s = p.read_text(encoding='utf-8')
    if 'python3 tools/patch_v105_camera_connection_compat.py' in s:
        continue

    anchors = [
        '          python3 tools/patch_v95a_materialized_idempotency.py\n',
        '          python3 tools/patch_v84_onvif_network_discovery.py\n',
    ]
    anchor = next((a for a in anchors if a in s), None)
    if anchor is None:
        raise SystemExit(f'V105c: no patch-chain anchor in {p}')
    addition = (
        '          python3 tools/patch_v105_camera_connection_compat.py\n'
        '          python3 tools/patch_v105b_camera_onboarding_truthful.py\n'
    )
    s = s.replace(anchor, anchor + addition, 1)

    if p.name == 'ios-v96-release-readiness.yml' and "      - 'tools/patch_v105*.py'" not in s:
        path_anchor = "      - 'tools/patch_v99*.py'\n"
        if path_anchor in s:
            s = s.replace(path_anchor, path_anchor + "      - 'tools/patch_v105*.py'\n", 1)
    if p.name == 'ios-v84-camera-discovery-check.yml' and "      - 'tools/patch_v105*.py'" not in s:
        path_anchor = "      - 'tools/patch_v84*.py'\n"
        if path_anchor in s:
            s = s.replace(path_anchor, path_anchor + "      - 'tools/patch_v105*.py'\n", 1)

    p.write_text(s, encoding='utf-8')
    print(f'updated {p}')

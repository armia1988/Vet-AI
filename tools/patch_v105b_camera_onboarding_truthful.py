from pathlib import Path

p = Path('lib/monitoring/dahua_thermal_camera_onboarding_page.dart')
s = p.read_text(encoding='utf-8')

old = """  String? testDetails;\n"""
new = """  String? testDetails;\n  bool verifiedOnvif = false;\n  bool verifiedRtsp = false;\n"""
if old in s and 'bool verifiedOnvif' not in s:
    s = s.replace(old, new, 1)

old = """      testDetails = null;\n    });\n  }\n"""
new = """      testDetails = null;\n      verifiedOnvif = false;\n      verifiedRtsp = false;\n    });\n  }\n"""
if old in s and 'verifiedOnvif = false;' not in s[s.find(old):s.find(old)+len(new)+100]:
    s = s.replace(old, new, 1)

old = """      testDetails = null;\n    });\n\n    try {\n      final result = await _connector.test("""
new = """      testDetails = null;\n      verifiedOnvif = false;\n      verifiedRtsp = false;\n    });\n\n    try {\n      final result = await _connector.test("""
if old in s:
    s = s.replace(old, new, 1)

old = """      setState(() {\n        testedSuccessfully = result.success;\n        discoveredStreamUri = discoveredProfiles?.mainStreamUri ?? result.streamUri;\n        discoveredSubStreamUri = discoveredProfiles?.subStreamUri;\n        discoveredProfileCount = discoveredProfiles?.profiles.length ?? 0;\n        testDetails = result.message;\n      });\n"""
new = """      final usableStream = discoveredProfiles?.mainStreamUri ?? result.streamUri;\n      final connectionUsable = result.success || (result.rtspOk && usableStream != null);\n      setState(() {\n        verifiedOnvif = result.onvifOk;\n        verifiedRtsp = result.rtspOk;\n        testedSuccessfully = connectionUsable;\n        discoveredStreamUri = usableStream;\n        discoveredSubStreamUri = discoveredProfiles?.subStreamUri;\n        discoveredProfileCount = discoveredProfiles?.profiles.length ?? 0;\n        testDetails = result.message;\n        if (result.rtspOk && !result.onvifOk) protocol = 'RTSP';\n        if (result.onvifOk && !result.rtspOk) protocol = 'ONVIF';\n      });\n"""
if old in s:
    s = s.replace(old, new, 1)
elif 'final connectionUsable = result.success || (result.rtspOk && usableStream != null);' not in s:
    raise SystemExit('V105b: result state anchor missing')

if 'final connectionUsable =' in s:
    s = s.replace('      if (result.success) {\n', '      if (connectionUsable) {\n', 1)

s = s.replace("            'onvif': protocol.contains('ONVIF'),\n            'rtsp': protocol.contains('RTSP'),\n            'connection_verified': true,\n",
              "            'onvif': verifiedOnvif,\n            'rtsp': verifiedRtsp,\n            'connection_verified': testedSuccessfully,\n", 1)

needle = "            'camera_type': cameraType,\n"
insert = "            'camera_type': cameraType,\n            'serial_number': serial.text.trim().isEmpty ? null : serial.text.trim(),\n"
if needle in s and "'serial_number': serial.text" not in s:
    s = s.replace(needle, insert, 1)

p.write_text(s, encoding='utf-8')
print('V105b truthful camera onboarding applied')

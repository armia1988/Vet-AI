from pathlib import Path

path = Path('lib/v5_app.dart')
text = path.read_text()
old = "              text: (result!['message'] ?? _errorMessage(code)).toString(),"
new = "              text: code == 'AI_PROVIDER_RATE_LIMIT' ? _errorMessage(code) : (result!['message'] ?? _errorMessage(code)).toString(),"
count = text.count(old)
if count != 1:
    raise SystemExit(f'AI message override: expected 1 match, found {count}')
path.write_text(text.replace(old, new, 1))
print('V20b AI rate-limit message override applied.')

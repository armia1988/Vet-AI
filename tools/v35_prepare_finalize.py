from pathlib import Path

p = Path('supabase/functions/finalize-case-report/index.ts')
s = p.read_text(encoding='utf-8')
marker = 'User-selected species: ${selectedSpecies}'
if marker not in s:
    start = s.find('const input=`Animal group:')
    if start < 0:
        raise SystemExit('V35 final prompt start not found')
    at = s.find('Symptoms/history:', start)
    if at < 0:
        raise SystemExit('V35 final prompt symptoms line not found')
    s = s[:at] + 'User-selected species: ${selectedSpecies}\\\n' + s[at:]
    p.write_text(s, encoding='utf-8')
print('V35 final-report species prompt prepared')

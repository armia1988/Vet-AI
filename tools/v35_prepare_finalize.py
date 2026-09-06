from pathlib import Path

# Prepare the final-report prompt directly because it is a multiline template.
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

# Prepare the one-time source patch so it remains compatible with dormant legacy
# V2/V3 callers. Empty species is NOT treated as a real species: the production
# analysis function still rejects it with SPECIES_REQUIRED. V5 always supplies
# the user's explicit selection.
patch = Path('tools/apply_v35_species_voice.py')
ps = patch.read_text(encoding='utf-8')
lines = ps.splitlines(keepends=True)
filtered = [line for line in lines if 'final model species prompt' not in line]
ps = ''.join(filtered)
ps = ps.replace('    required String speciesCode,\\n    String? birdType,', "    String speciesCode = '',\\n    String? birdType,")
patch.write_text(ps, encoding='utf-8')

print('V35 final prompt prepared; legacy callers remain compile-safe without species guessing')

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

# The main patch used to repeat the same multiline prompt replacement. Remove that
# one redundant line at runtime so the rest of the source patch remains idempotent.
patch = Path('tools/apply_v35_species_voice.py')
ps = patch.read_text(encoding='utf-8')
lines = ps.splitlines(keepends=True)
filtered = [line for line in lines if 'final model species prompt' not in line]
if len(filtered) == len(lines):
    print('V35 duplicate final prompt marker already absent')
else:
    patch.write_text(''.join(filtered), encoding='utf-8')
    print('V35 duplicate final prompt marker removed')

print('V35 final-report species prompt prepared')

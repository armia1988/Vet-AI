from pathlib import Path

p = Path('lib/admin/admin_dashboard.dart')
s = p.read_text(encoding='utf-8')

wide_open = """    return VetIncomingSupportCallLayer(
      role: 'support',
      child: Scaffold(
"""
fixed_tail = """        ],
      ),
    ),
  );
  }
}
"""
malformed_tail = """        ],
      ),
    );
  }
}
"""

if wide_open in s and fixed_tail not in s:
    marker = '\nclass _AdminDestination'
    end = s.find(marker)
    if end < 0:
        raise SystemExit('V65c: admin destination marker missing')
    before = s[:end]
    pos = before.rfind(malformed_tail)
    if pos < 0:
        raise SystemExit('V65c: malformed wide call-layer tail not found')
    before = before[:pos] + fixed_tail + before[pos + len(malformed_tail):]
    s = before + s[end:]
elif wide_open not in s:
    raise SystemExit('V65c: wide incoming-call layer open marker missing')

# The mobile wrapper is already balanced by V65. This guard makes sure both
# layouts keep the call listener after repairing the wide closing parentheses.
if s.count("role: 'support'") < 2:
    raise SystemExit('V65c: expected mobile and desktop support call layers')

p.write_text(s, encoding='utf-8')
print('Vet AI V65c applied: admin incoming-call layer parentheses balanced for mobile and desktop')

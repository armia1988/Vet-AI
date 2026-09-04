from pathlib import Path

v5 = Path('lib/v5_app.dart')
s = v5.read_text()
s = s.replace("final complete = code == 'AI_ANALYSIS_COMPLETE';", "final complete = code == 'AI_ANALYSIS_COMPLETE' || code == 'FINAL_REPORT_COMPLETE';")
s = s.replace("const Color(0xFF344740)", "VetColors.surface3")
s = s.replace("danger?const Color(0xFF38262A):VetColors.surface", "danger?VetColors.softRed:VetColors.surface")
v5.write_text(s)

support = Path('lib/support/support_chat_v6.dart')
s = support.read_text()
s = s.replace("mine ? const Color(0xFF3C5550) : VetColors.surface2", "mine ? VetColors.softBlue : VetColors.surface")
s = s.replace("mine ? VetColors.primaryDark : VetColors.border", "mine ? VetColors.blue : VetColors.border")
support.write_text(s)

report = Path('lib/analysis/vet_analysis_report.dart')
s = report.read_text()
old = """        if (questions.isNotEmpty) ...[\n          const SizedBox(height: 18),"""
new = """        if (questions.isNotEmpty) ...[\n          const SizedBox(height: 18),"""
# Keep the existing question block, then add a final-report action for cases where no questions were needed.
s = s.replace(old, new)
needle = """          if (_finalError != null) ...[\n            const SizedBox(height: 10),\n            _ErrorBox(text: _finalError!),\n          ],\n        ],\n      ],\n    );\n  }"""
replacement = """          if (_finalError != null) ...[\n            const SizedBox(height: 10),\n            _ErrorBox(text: _finalError!),\n          ],\n        ],\n        if (questions.isEmpty) ...[\n          const SizedBox(height: 18),\n          FilledButton.icon(\n            onPressed: _finalizing ? null : _finalize,\n            style: FilledButton.styleFrom(backgroundColor: VetColors.blue, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(58)),\n            icon: _finalizing\n                ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))\n                : const Icon(Icons.fact_check_outlined, size: 28),\n            label: Text(_finalizing\n                ? widget.translate('Checking trusted sources…', 'جاري مراجعة المصادر الموثوقة…', 'Betrouwbare bronnen controleren…')\n                : widget.translate('Create final verified report', 'إنشاء التقرير النهائي الموثق', 'Definitief geverifieerd rapport maken')),\n          ),\n          if (_finalError != null) ...[\n            const SizedBox(height: 10),\n            _ErrorBox(text: _finalError!),\n          ],\n        ],\n      ],\n    );\n  }"""
if needle not in s:
    raise SystemExit('final report insertion point not found')
s = s.replace(needle, replacement, 1)
report.write_text(s)

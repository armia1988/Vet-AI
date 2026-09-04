from pathlib import Path

report = Path('lib/analysis/vet_analysis_report.dart')
s = report.read_text()
old = """    final text = (_result['voice_summary'] ?? _result['summary'] ?? '').toString().trim();\n    if (text.isEmpty) return;"""
new = """    String text = (_result['voice_summary'] ?? '').toString().trim();\n    if (text.isEmpty) {\n      final parts = <String>[];\n      final summary = (_result['summary'] ?? '').toString().trim();\n      if (summary.isNotEmpty) parts.add(summary);\n      final differentials = _maps(_result['differential_diagnoses']);\n      if (differentials.isNotEmpty) {\n        final top = differentials.first;\n        final name = (top['name'] ?? '').toString().trim();\n        final cause = (top['cause'] ?? '').toString().trim();\n        final treatment = (top['treatment_summary'] ?? '').toString().trim();\n        final prevention = (top['prevention_summary'] ?? '').toString().trim();\n        if (name.isNotEmpty) parts.add(widget.translate('Most likely at this stage: $name.', 'الأكثر احتمالًا في هذه المرحلة: $name.', 'Meest waarschijnlijk in deze fase: $name.'));\n        if (cause.isNotEmpty) parts.add(widget.translate('Cause: $cause.', 'السبب: $cause.', 'Oorzaak: $cause.'));\n        if (treatment.isNotEmpty) parts.add(widget.translate('Management: $treatment', 'التعامل والعلاج: $treatment', 'Behandeling en management: $treatment'));\n        if (prevention.isNotEmpty) parts.add(widget.translate('Prevention: $prevention', 'الوقاية: $prevention', 'Preventie: $prevention'));\n      }\n      final actions = _strings(_result['immediate_actions']);\n      if (actions.isNotEmpty) parts.add(widget.translate('Do now: ${actions.first}', 'افعل الآن: ${actions.first}', 'Doe nu: ${actions.first}'));\n      text = parts.join(' ');\n    }\n    if (text.isEmpty) return;"""
if old not in s:
    raise SystemExit('voice insertion point not found')
s = s.replace(old, new, 1)
report.write_text(s)

app = Path('lib/v5_app.dart')
s = app.read_text()
s = s.replace("const _BrandLockup(markWidth: 112, compact: true)", "const _BrandLockup(markWidth: 132, compact: true)")
s = s.replace("const _BrandLockup(markWidth: 154)", "const _BrandLockup(markWidth: 178)")
s = s.replace("_BrandLockup(markWidth: 150)", "_BrandLockup(markWidth: 170)")
s = s.replace("icon: Icon(icon, size: 30, color: VetColors.muted),", "icon: Icon(icon, size: 30, color: color.withValues(alpha: .78)),")
app.write_text(s)

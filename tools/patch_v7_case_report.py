from pathlib import Path

p = Path('lib/v5_app.dart')
s = p.read_text()

s = s.replace("import 'services/vet_backend.dart';\n", "import 'services/vet_backend.dart';\nimport 'analysis/vet_analysis_report.dart';\n")
s = s.replace("import 'v3_app.dart' show V3AnalysisCard;\n", "")
s = s.replace("  Map<String, dynamic>? result;\n  late String group;", "  Map<String, dynamic>? result;\n  String? assessmentId;\n  late String group;")
s = s.replace(
"      final assessmentId = await VetBackend.instance.createDraftAssessment(farmId: farmId, mediaPath: path, symptomNotes: notes.text, animalGroup: group);\n      final response = await VetBackend.instance.analyzeAssessment(assessmentId, language: Localizations.localeOf(context).languageCode);",
"      final newAssessmentId = await VetBackend.instance.createDraftAssessment(farmId: farmId, mediaPath: path, symptomNotes: notes.text, animalGroup: group);\n      assessmentId = newAssessmentId;\n      final response = await VetBackend.instance.analyzeAssessment(newAssessmentId, language: Localizations.localeOf(context).languageCode);"
)
s = s.replace(
"          if (complete)\n            V3AnalysisCard(result: result!)",
"          if (complete)\n            VetAnalysisReportCard(\n              initialResult: result!,\n              assessmentId: assessmentId ?? result!['assessment_id']?.toString() ?? '',\n              languageCode: Localizations.localeOf(context).languageCode,\n              translate: (en, ar, nl) => tr(context, en, ar, nl),\n              onFinalized: (finalReport) { if (mounted) setState(() => result = finalReport); },\n            )"
)
p.write_text(s)

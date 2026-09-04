from pathlib import Path

locale = Path('lib/i18n/vet_locale.dart')
s = locale.read_text()
s = s.replace(
"""    if (missing.isEmpty) return true;\n    if (Supabase.instance.client.auth.currentSession == null) return false;\n\n    var changed = false;\n    for (var i = 0; i < missing.length; i += 70) {\n      final batch = missing.sublist(i, i + 70 > missing.length ? missing.length : i + 70);""",
"""    if (missing.isEmpty) return true;\n    final hasSession = Supabase.instance.client.auth.currentSession != null;\n    final permitted = hasSession ? missing : missing.where(vetCoreUiStrings.contains).toList();\n    if (permitted.isEmpty) return false;\n\n    var changed = false;\n    for (var i = 0; i < permitted.length; i += 70) {\n      final batch = permitted.sublist(i, i + 70 > permitted.length ? permitted.length : i + 70);"""
)
s = s.replace(
"""  void _queue(String language, String source) {\n    if (!_loaded || source.trim().isEmpty || Supabase.instance.client.auth.currentSession == null) return;\n    final set = _queued.putIfAbsent(language, () => <String>{});""",
"""  void _queue(String language, String source) {\n    if (!_loaded || source.trim().isEmpty) return;\n    final signedIn = Supabase.instance.client.auth.currentSession != null;\n    if (!signedIn && !vetCoreUiStrings.contains(source.trim())) return;\n    final set = _queued.putIfAbsent(language, () => <String>{});"""
)
locale.write_text(s)

app = Path('lib/v5_app.dart')
s = app.read_text()
s = s.replace(
"""class _VetAIAppV5State extends State<VetAIAppV5> {\n  final localeController = VetLocaleController.instance;\n  final translator = VetTranslator.instance;""",
"""class _VetAIAppV5State extends State<VetAIAppV5> {\n  final localeController = VetLocaleController.instance;\n  final translator = VetTranslator.instance;\n  bool ready = false;"""
)
s = s.replace(
"""    localeController.addListener(_refresh);\n    translator.addListener(_refresh);\n    localeController.load();\n    translator.load();\n  }\n\n  void _refresh() { if (mounted) setState(() {}); }""",
"""    localeController.addListener(_refresh);\n    translator.addListener(_refresh);\n    _bootstrap();\n  }\n\n  Future<void> _bootstrap() async {\n    await localeController.load();\n    await translator.load();\n    final requested = localeController.manualCode ?? WidgetsBinding.instance.platformDispatcher.locale.languageCode;\n    if (vetLanguages.any((l) => l.code == requested)) {\n      await translator.prepareLanguage(requested, vetCoreUiStrings);\n    }\n    if (mounted) setState(() => ready = true);\n  }\n\n  void _refresh() { if (mounted) setState(() {}); }"""
)
s = s.replace(
"""  @override\n  Widget build(BuildContext context) {\n    return MaterialApp(""",
"""  @override\n  Widget build(BuildContext context) {\n    if (!ready) {\n      return MaterialApp(\n        debugShowCheckedModeBanner: false,\n        theme: buildVetTheme(),\n        home: const Scaffold(\n          body: Center(\n            child: Column(mainAxisSize: MainAxisSize.min, children: [\n              _BrandLockup(markWidth: 150),\n              SizedBox(height: 22),\n              SizedBox.square(dimension: 30, child: CircularProgressIndicator(strokeWidth: 3)),\n            ]),\n          ),\n        ),\n      );\n    }\n    return MaterialApp(""",
1
)
app.write_text(s)

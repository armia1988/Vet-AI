from pathlib import Path

# Fix the stale startup block left from the earlier loading implementation.
p = Path('lib/v5_app.dart')
s = p.read_text()
broken = """    return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildVetTheme(),
        home: const Scaffold(
          body: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _BrandLockup(markWidth: 170),
              SizedBox(height: 22),
              SizedBox.square(dimension: 30, child: CircularProgressIndicator(strokeWidth: 3)),
            ]),
          ),
        ),
      );
    }
    return MaterialApp(
"""
replacement = """    return MaterialApp(
"""
if broken not in s:
    raise SystemExit('stale startup MaterialApp block not found')
s = s.replace(broken, replacement, 1)
p.write_text(s)

# Remove the obsolete raw-web-source UI. Customer reports no longer expose links.
p = Path('lib/analysis/vet_analysis_report.dart')
s = p.read_text()
s = s.replace("import 'package:url_launcher/url_launcher.dart';\n", "")
start = s.find('class _SourceTile extends StatelessWidget {')
if start >= 0:
    end = s.find('class _ErrorBox extends StatelessWidget {', start)
    if end < 0:
        raise SystemExit('source tile end not found')
    s = s[:start] + s[end:]
p.write_text(s)

from pathlib import Path

p = Path('lib/v5_app.dart')
s = p.read_text()
old = "            const Center(child: _BrandLockup(markWidth: 154)),\n"
new = """            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(),
                const _BrandLockup(markWidth: 154),
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.topEnd,
                    child: IconButton.filledTonal(
                      tooltip: tr(context, 'Language', 'اللغة', 'Taal'),
                      style: IconButton.styleFrom(backgroundColor: VetColors.surface3),
                      icon: const Icon(Icons.language_rounded, size: 31, color: VetColors.blue),
                      onPressed: () => showVetLanguagePicker(context),
                    ),
                  ),
                ),
              ],
            ),
"""
if old not in s:
    raise SystemExit('auth brand snippet not found')
s = s.replace(old, new, 1)

old = """      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 28), onPressed: VetBackend.instance.signOut),
        title: Text(tr(context, 'Verify account', 'تفعيل الحساب', 'Account bevestigen')),
      ),
"""
new = """      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 28), onPressed: VetBackend.instance.signOut),
        title: Text(tr(context, 'Verify account', 'تفعيل الحساب', 'Account bevestigen')),
        actions: [IconButton(onPressed: () => showVetLanguagePicker(context), icon: const Icon(Icons.language_rounded, color: VetColors.blue))],
      ),
"""
if old not in s:
    raise SystemExit('verify appbar snippet not found')
s = s.replace(old, new, 1)
p.write_text(s)
print('pre-login language buttons added')

from pathlib import Path

p = Path('lib/v5_app.dart')
s = p.read_text()
needle = "import 'services/vet_backend.dart';\n"
if "import 'support/support_chat_v6.dart';" not in s:
    s = s.replace(needle, needle + "import 'support/support_chat_v6.dart';\n", 1)

old = "_MenuTile(icon: Icons.support_agent_rounded, title: tr(context, 'Support chat', 'شات الدعم', 'Supportchat'), subtitle: tr(context, 'Messages are stored and update live. Human replies require the support console.', 'الرسائل محفوظة وتتحدث مباشرة. الرد البشري يحتاج تشغيل لوحة الدعم.', 'Berichten worden opgeslagen en live bijgewerkt. Menselijke antwoorden vereisen de supportconsole.'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => V5SupportScreen(farmId: farm['id'] as String)))),"
new = "_MenuTile(icon: Icons.support_agent_rounded, title: tr(context, 'Support chat', 'شات الدعم', 'Supportchat'), subtitle: tr(context, 'Realtime private chat with photos, marked images and files.', 'شات خاص مباشر مع الصور والتعديل عليها والملفات.', 'Privé realtime chat met foto’s, gemarkeerde beelden en bestanden.'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => V6SupportScreen(farmId: farm['id'] as String)))),"
if old not in s:
    raise SystemExit('support menu tile not found')
s = s.replace(old, new, 1)

subscription = "_MenuTile(icon: Icons.workspace_premium_outlined, title: tr(context, 'Subscription', 'الاشتراك', 'Abonnement'), subtitle: tr(context, 'Animal groups, monthly/annual and sensor access.', 'أنواع الحيوانات والشهري/السنوي وصلاحية الحساسات.', 'Diergroepen, maandelijks/jaarlijks en sensortoegang.'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => V5SubscriptionScreen(farm: farm)))),\n"
language = "        _MenuTile(icon: Icons.language_rounded, title: tr(context, 'Language', 'اللغة', 'Taal'), subtitle: tr(context, 'Automatic device language or choose manually.', 'تلقائي حسب لغة الهاتف أو اختر اللغة يدويًا.', 'Automatisch volgens het toestel of handmatig kiezen.'), onTap: () => showVetLanguagePicker(context)),\n"
if language not in s:
    if subscription not in s:
        raise SystemExit('subscription tile not found')
    s = s.replace(subscription, subscription + language, 1)

p.write_text(s)
print('support UI integration applied')

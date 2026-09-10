from pathlib import Path

# V93a: Dart type fix for gateway UID suffix generation.
# Keep this patch idempotent because later camera versions may format the
# already-correct List<String>.generate call across multiple lines.
p = Path('lib/monitoring/camera_gateway_page.dart')
s = p.read_text(encoding='utf-8')

if 'List<String>.generate' not in s:
    if 'List<int>.generate' not in s:
        raise SystemExit('V93a gateway suffix anchor missing')
    s = s.replace('List<int>.generate', 'List<String>.generate', 1)

p.write_text(s, encoding='utf-8')
assert 'List<String>.generate' in p.read_text(encoding='utf-8')

# V94 compatibility: Dart cannot promote a nullable local across async
# reassignments. Pin the active PullPoint session to non-null locals before
# renewal and pull operations.
page = Path('lib/monitoring/camera_intelligence_page.dart')
t = page.read_text(encoding='utf-8')
old = '''          if (session.shouldRenew()) {
            session = await analyticsService.renewPullPointSubscription(session);
            eventSession = session;
            eventRenewals += 1;
            if (mounted) setState(() {});
          }

          final rawPulled = await analyticsService.pullMessages(session);
'''
new = '''          final activeSession = session;
          if (activeSession == null) break;
          if (activeSession.shouldRenew()) {
            session = await analyticsService.renewPullPointSubscription(activeSession);
            eventSession = session;
            eventRenewals += 1;
            if (mounted) setState(() {});
          }

          final pullSession = session;
          if (pullSession == null) break;
          final rawPulled = await analyticsService.pullMessages(pullSession);
'''
if new not in t:
    if old not in t:
        raise SystemExit('V94 nullable PullPoint session anchor missing')
    t = t.replace(old, new, 1)
page.write_text(t, encoding='utf-8')

print('Vet AI V93a/V94 compile compatibility applied: gateway suffix and nullable PullPoint session are safe')

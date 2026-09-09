from pathlib import Path


def must_replace(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f'V61b: {label} anchor missing')
    return text.replace(old, new, 1)


# 1) Cache admin reads and prewarm them in parallel.
p = Path('lib/admin/admin_service.dart')
s = p.read_text(encoding='utf-8')
service_anchor = """class VetAdminService {
  VetAdminService._();
  static final instance = VetAdminService._();

  SupabaseClient get client => VetBackend.instance.client;
"""
service_new = """class VetAdminService {
  VetAdminService._();
  static final instance = VetAdminService._();

  final Map<String, Object> _readCache = <String, Object>{};
  final Map<String, DateTime> _readCacheAt = <String, DateTime>{};
  static const Duration _defaultReadTtl = Duration(minutes: 2);

  SupabaseClient get client => VetBackend.instance.client;

  Future<T> _cached<T>(
    String key,
    Future<T> Function() loader, {
    Duration ttl = _defaultReadTtl,
  }) {
    final now = DateTime.now();
    final cached = _readCache[key];
    final cachedAt = _readCacheAt[key];
    if (cached is Future<T> && cachedAt != null && now.difference(cachedAt) < ttl) {
      return cached;
    }
    late Future<T> future;
    future = loader().then<T>(
      (value) => value,
      onError: (Object error, StackTrace stack) {
        if (identical(_readCache[key], future)) {
          _readCache.remove(key);
          _readCacheAt.remove(key);
        }
        Error.throwWithStackTrace(error, stack);
      },
    );
    _readCache[key] = future;
    _readCacheAt[key] = now;
    return future;
  }

  void invalidateCache([String? key]) {
    if (key == null) {
      _readCache.clear();
      _readCacheAt.clear();
      return;
    }
    _readCache.remove(key);
    _readCacheAt.remove(key);
  }

  Future<void> prewarm() async {
    await Future.wait<dynamic>(<Future<dynamic>>[
      stats(), farms(), profiles(), animals(), sensors(), sensorRules(), alerts(),
      supportThreads(), subscriptions(), plans(), payments(), notifications(),
      admins(), pushDevices(), auditLog(),
    ]);
  }
"""
s = must_replace(s, service_anchor, service_new, 'service cache')

old_stats = """  Future<Map<String, dynamic>> stats() async {
    final value = await client.rpc('admin_dashboard_stats');
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }
"""
new_stats = """  Future<Map<String, dynamic>> stats() => _cached<Map<String, dynamic>>(
        'stats',
        () async {
          final value = await client.rpc('admin_dashboard_stats');
          if (value is Map) return Map<String, dynamic>.from(value);
          return <String, dynamic>{};
        },
        ttl: const Duration(seconds: 45),
      );
"""
s = must_replace(s, old_stats, new_stats, 'stats cache')

old_rows = """  Future<List<Map<String, dynamic>>> _rows(
    String table, {
    String select = '*',
    String? orderBy,
    bool ascending = false,
    int limit = 500,
  }) async {
    dynamic query = client.from(table).select(select);
    if (orderBy != null) query = query.order(orderBy, ascending: ascending);
    final rows = await query.limit(limit);
    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }
"""
new_rows = """  Future<List<Map<String, dynamic>>> _rows(
    String table, {
    String select = '*',
    String? orderBy,
    bool ascending = false,
    int limit = 500,
  }) {
    final cacheKey = 'rows:$table:$select:${orderBy ?? ''}:$ascending:$limit';
    return _cached<List<Map<String, dynamic>>>(cacheKey, () async {
      dynamic query = client.from(table).select(select);
      if (orderBy != null) query = query.order(orderBy, ascending: ascending);
      final rows = await query.limit(limit);
      return (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    });
  }
"""
s = must_replace(s, old_rows, new_rows, 'row cache')

# Clear cached reads after the common admin mutations.
for old, new in [
    ("await client.from('farms').update(values).eq('id', id);", "await client.from('farms').update(values).eq('id', id);\n    invalidateCache();"),
    ("await client.from('profiles').update(values).eq('id', id);", "await client.from('profiles').update(values).eq('id', id);\n    invalidateCache();"),
    ("await client.from('sensor_devices').update(values).eq('id', id);", "await client.from('sensor_devices').update(values).eq('id', id);\n    invalidateCache();"),
    ("await client.from('sensor_alert_rules').update(values).eq('id', id);", "await client.from('sensor_alert_rules').update(values).eq('id', id);\n    invalidateCache();"),
    ("await client.from('push_devices').update({'enabled': enabled}).eq('id', id);", "await client.from('push_devices').update({'enabled': enabled}).eq('id', id);\n    invalidateCache();"),
    ("await client.from('support_threads').update(values).eq('id', id);", "await client.from('support_threads').update(values).eq('id', id);\n    invalidateCache();"),
    ("await client.rpc('admin_mark_support_read', params: {'p_thread_id': id});", "await client.rpc('admin_mark_support_read', params: {'p_thread_id': id});\n    invalidateCache();"),
    ("await client.from('farm_subscriptions').update(values).eq('id', id);", "await client.from('farm_subscriptions').update(values).eq('id', id);\n    invalidateCache();"),
    ("await client.from('subscription_plans').update(values).eq('id', id);", "await client.from('subscription_plans').update(values).eq('id', id);\n    invalidateCache();"),
    ("await client.from('payments').update(values).eq('id', id);", "await client.from('payments').update(values).eq('id', id);\n    invalidateCache();"),
    ("await client.from('admin_accounts').delete().eq('user_id', userId);", "await client.from('admin_accounts').delete().eq('user_id', userId);\n    invalidateCache();"),
]:
    if new not in s and old in s:
        s = s.replace(old, new, 1)

# Handle multi-line writes by inserting invalidation before the next method.
for old, new in [
    ("    }).eq('id', id);\n  }\n\n  Future<void> updateSensorRule", "    }).eq('id', id);\n    invalidateCache();\n  }\n\n  Future<void> updateSensorRule"),
    ("    }).eq('id', id);\n  }\n\n  Future<void> updateSupportThread", "    }).eq('id', id);\n    invalidateCache();\n  }\n\n  Future<void> updateSupportThread"),
    ("    });\n  }\n\n  Future<void> removeAdmin", "    });\n    invalidateCache();\n  }\n\n  Future<void> removeAdmin"),
]:
    if new not in s and old in s:
        s = s.replace(old, new, 1)

# Creation methods should force the next read to be fresh.
s = s.replace(
    """        .select()
        .single();
    return Map<String, dynamic>.from(row);
  }

  Future<void> updatePlan""",
    """        .select()
        .single();
    invalidateCache();
    return Map<String, dynamic>.from(row);
  }

  Future<void> updatePlan""",
    1,
)
s = s.replace(
    """        .select()
        .single();
    return Map<String, dynamic>.from(row);
  }

  Future<Map<String, dynamic>> sendNotification""",
    """        .select()
        .single();
    invalidateCache();
    return Map<String, dynamic>.from(row);
  }

  Future<Map<String, dynamic>> sendNotification""",
    1,
)

for marker in ['_readCache', 'Future<void> prewarm()', "'rows:$table:$select", 'invalidateCache();']:
    if marker not in s:
        raise SystemExit(f'V61b service verification missing: {marker}')
p.write_text(s, encoding='utf-8')


# 2) Dashboard: prewarm immediately and stop route/page taps from creating a
# fresh network request. The RBAC patch changes _loadRole, so insert helpers at
# the stable dispose anchor instead of matching the role method body.
p = Path('lib/admin/admin_dashboard.dart')
s = p.read_text(encoding='utf-8')
old_init = """    _loadRole();
    refreshTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (mounted && index == 0) setState(() => refreshTick++);
    });
"""
new_init = """    _loadRole();
    unawaited(admin.prewarm());
    refreshTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (mounted && index == 0) {
        admin.invalidateCache('stats');
        setState(() => refreshTick++);
      }
    });
"""
s = must_replace(s, old_init, new_init, 'dashboard prewarm')

if 'void _refreshCurrent()' not in s:
    dispose_anchor = """  @override
  void dispose() {
"""
    helper = """  void _refreshCurrent() {
    admin.invalidateCache();
    setState(() => refreshTick++);
    unawaited(admin.prewarm());
  }

"""
    if dispose_anchor not in s:
        raise SystemExit('V61b dashboard dispose anchor missing')
    s = s.replace(dispose_anchor, helper + dispose_anchor, 1)

s = s.replace('onRefresh: () => setState(() => refreshTick++),', 'onRefresh: _refreshCurrent,', 1)
s = s.replace('onPressed: () => setState(() => refreshTick++),', 'onPressed: _refreshCurrent,', 1)
s = s.replace('        Expanded(child: _page()),', '        Expanded(child: RepaintBoundary(child: _page())),', 1)
s = s.replace('        body: _page(),', '        body: RepaintBoundary(child: _page()),', 1)

for marker in ['unawaited(admin.prewarm())', 'void _refreshCurrent()', "admin.invalidateCache('stats')", 'RepaintBoundary(child: _page())']:
    if marker not in s:
        raise SystemExit(f'V61b dashboard verification missing: {marker}')
p.write_text(s, encoding='utf-8')


# 3) Browser navigation: remove built-in route transition delay only on web.
p = Path('lib/theme/app_theme.dart')
s = p.read_text(encoding='utf-8')
if "package:flutter/foundation.dart" not in s:
    s = s.replace("import 'package:flutter/material.dart';", "import 'package:flutter/foundation.dart';\nimport 'package:flutter/material.dart';", 1)
if 'class _VetInstantPageTransitionsBuilder' not in s:
    marker = '\nThemeData buildVetTheme() {'
    if marker not in s:
        raise SystemExit('V61b theme function anchor missing')
    s = s.replace(marker, r'''

class _VetInstantPageTransitionsBuilder extends PageTransitionsBuilder {
  const _VetInstantPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
''' + marker, 1)
if 'pageTransitionsTheme: kIsWeb' not in s:
    anchor = '    useMaterial3: true,\n'
    setting = """    pageTransitionsTheme: kIsWeb
        ? const PageTransitionsTheme(
            builders: <TargetPlatform, PageTransitionsBuilder>{
              TargetPlatform.android: _VetInstantPageTransitionsBuilder(),
              TargetPlatform.iOS: _VetInstantPageTransitionsBuilder(),
              TargetPlatform.macOS: _VetInstantPageTransitionsBuilder(),
              TargetPlatform.windows: _VetInstantPageTransitionsBuilder(),
              TargetPlatform.linux: _VetInstantPageTransitionsBuilder(),
              TargetPlatform.fuchsia: _VetInstantPageTransitionsBuilder(),
            },
          )
        : const PageTransitionsTheme(),
"""
    if anchor not in s:
        raise SystemExit('V61b ThemeData anchor missing')
    s = s.replace(anchor, anchor + setting, 1)

for marker in ['kIsWeb', '_VetInstantPageTransitionsBuilder', 'pageTransitionsTheme: kIsWeb']:
    if marker not in s:
        raise SystemExit(f'V61b theme verification missing: {marker}')
p.write_text(s, encoding='utf-8')

print('Vet AI V61b applied: parallel data prewarm, cached admin reads, instant browser routes, reduced repainting')

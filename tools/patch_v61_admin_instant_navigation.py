from pathlib import Path


def must_replace(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f'V61: {label} anchor missing')
    return text.replace(old, new, 1)


# ---------------------------------------------------------------------------
# 1) Admin service: reuse in-flight/completed reads instead of hitting Supabase
#    again on every Flutter rebuild/navigation. Also prewarm the core admin data
#    in parallel right after admin login.
# ---------------------------------------------------------------------------
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
      stats(),
      farms(),
      profiles(),
      animals(),
      sensors(),
      sensorRules(),
      alerts(),
      supportThreads(),
      subscriptions(),
      plans(),
      payments(),
      notifications(),
      admins(),
      pushDevices(),
      auditLog(),
    ]);
  }
"""
s = must_replace(s, service_anchor, service_new, 'admin service cache fields')

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

# Reads must refresh immediately after admin writes, not two minutes later.
write_replacements = [
    ("await client.from('farms').update(values).eq('id', id);", "await client.from('farms').update(values).eq('id', id);\n    invalidateCache();"),
    ("await client.from('profiles').update(values).eq('id', id);", "await client.from('profiles').update(values).eq('id', id);\n    invalidateCache();"),
    ("await client.from('sensor_devices').update(values).eq('id', id);", "await client.from('sensor_devices').update(values).eq('id', id);\n    invalidateCache();"),
    ("    }).eq('id', id);\n  }\n\n  Future<void> updateSensorRule", "    }).eq('id', id);\n    invalidateCache();\n  }\n\n  Future<void> updateSensorRule"),
    ("await client.from('sensor_alert_rules').update(values).eq('id', id);", "await client.from('sensor_alert_rules').update(values).eq('id', id);\n    invalidateCache();"),
    ("await client.from('push_devices').update({'enabled': enabled}).eq('id', id);", "await client.from('push_devices').update({'enabled': enabled}).eq('id', id);\n    invalidateCache();"),
    ("    }).eq('id', id);\n  }\n\n  Future<void> updateSupportThread", "    }).eq('id', id);\n    invalidateCache();\n  }\n\n  Future<void> updateSupportThread"),
    ("await client.from('support_threads').update(values).eq('id', id);", "await client.from('support_threads').update(values).eq('id', id);\n    invalidateCache();"),
    ("await client.rpc('admin_mark_support_read', params: {'p_thread_id': id});", "await client.rpc('admin_mark_support_read', params: {'p_thread_id': id});\n    invalidateCache();"),
    ("await client.from('farm_subscriptions').update(values).eq('id', id);", "await client.from('farm_subscriptions').update(values).eq('id', id);\n    invalidateCache();"),
    ("await client.from('subscription_plans').update(values).eq('id', id);", "await client.from('subscription_plans').update(values).eq('id', id);\n    invalidateCache();"),
    ("await client.from('payments').update(values).eq('id', id);", "await client.from('payments').update(values).eq('id', id);\n    invalidateCache();"),
    ("    await client.from('admin_accounts').upsert({", "    await client.from('admin_accounts').upsert({"),
    ("    });\n  }\n\n  Future<void> removeAdmin", "    });\n    invalidateCache();\n  }\n\n  Future<void> removeAdmin"),
    ("await client.from('admin_accounts').delete().eq('user_id', userId);", "await client.from('admin_accounts').delete().eq('user_id', userId);\n    invalidateCache();"),
]
for old, new in write_replacements:
    if new not in s and old in s:
        s = s.replace(old, new, 1)

# Creation paths return fresh rows; clear cache immediately before returning.
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
        raise SystemExit(f'V61: admin service verification missing: {marker}')
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# 2) Admin dashboard: warm data once in parallel. Every destination tap then
#    renders from the same already-running/completed Future instead of starting
#    another network round trip. Manual refresh still forces live data.
# ---------------------------------------------------------------------------
p = Path('lib/admin/admin_dashboard.dart')
s = p.read_text(encoding='utf-8')

s = must_replace(
    s,
    """    _loadRole();
    refreshTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (mounted && index == 0) setState(() => refreshTick++);
    });
""",
    """    _loadRole();
    unawaited(admin.prewarm());
    refreshTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (mounted && index == 0) {
        admin.invalidateCache('stats');
        setState(() => refreshTick++);
      }
    });
""",
    'dashboard prewarm',
)

load_role_marker = """  Future<void> _loadRole() async {
    final value = await admin.role();
    if (mounted) setState(() => role = value);
  }
"""
load_role_new = load_role_marker + """

  void _refreshCurrent() {
    admin.invalidateCache();
    setState(() => refreshTick++);
    unawaited(admin.prewarm());
  }
"""
s = must_replace(s, load_role_marker, load_role_new, 'dashboard refresh helper')

s = s.replace("onRefresh: () => setState(() => refreshTick++),", "onRefresh: _refreshCurrent,", 1)
s = s.replace("onPressed: () => setState(() => refreshTick++),", "onPressed: _refreshCurrent,", 1)

# Avoid repainting the whole dashboard chrome when only the current page changes.
s = s.replace('        Expanded(child: _page()),', '        Expanded(child: RepaintBoundary(child: _page())),', 1)
s = s.replace('        body: _page(),', '        body: RepaintBoundary(child: _page()),', 1)

for marker in ['unawaited(admin.prewarm())', 'void _refreshCurrent()', "admin.invalidateCache('stats')", 'RepaintBoundary(child: _page())']:
    if marker not in s:
        raise SystemExit(f'V61: dashboard verification missing: {marker}')
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# 3) Web route transitions: remove the built-in ~300ms Material/iOS route
#    animation on the browser. Page changes should happen on the tap frame.
#    Native iOS/Android keeps the normal app transitions.
# ---------------------------------------------------------------------------
p = Path('lib/theme/app_theme.dart')
s = p.read_text(encoding='utf-8')
if "package:flutter/foundation.dart" not in s:
    s = s.replace("import 'package:flutter/material.dart';", "import 'package:flutter/foundation.dart';\nimport 'package:flutter/material.dart';", 1)

if 'class _VetInstantPageTransitionsBuilder' not in s:
    marker = '\nThemeData buildVetTheme() {'
    if marker not in s:
        raise SystemExit('V61: theme function marker missing')
    builder = r'''

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
'''
    s = s.replace(marker, builder + marker, 1)

transition_setting = """    pageTransitionsTheme: kIsWeb
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
if 'pageTransitionsTheme: kIsWeb' not in s:
    theme_anchor = "    useMaterial3: true,\n"
    if theme_anchor not in s:
        raise SystemExit('V61: ThemeData anchor missing')
    s = s.replace(theme_anchor, theme_anchor + transition_setting, 1)

for marker in ['kIsWeb', '_VetInstantPageTransitionsBuilder', 'pageTransitionsTheme: kIsWeb']:
    if marker not in s:
        raise SystemExit(f'V61: theme verification missing: {marker}')
p.write_text(s, encoding='utf-8')

print('Vet AI V61 applied: cached admin reads, parallel prewarm, instant web routes, reduced dashboard repainting')

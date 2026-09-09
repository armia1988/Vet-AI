from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f'V63: {label} anchor missing')
    return text.replace(old, new, 1)


# ---------------------------------------------------------------------------
# 1) Account center: refresh locally after mutations and make account rows
#    readable on narrow phone screens instead of squeezing email vertically.
# ---------------------------------------------------------------------------
p = Path('lib/admin/admin_account_control_v2.dart')
s = p.read_text(encoding='utf-8')

old_reload = """  void reload() {
    admin.invalidateCache();
    setState(() => future = _load());
  }
"""
new_reload = """  Future<void> reload() async {
    admin.invalidateCache();
    final next = _load();
    if (mounted) setState(() => future = next);
    await next;
  }
"""
s = replace_once(s, old_reload, new_reload, 'account local reload')

s = s.replace('      reload();\n    } catch (e) {', '      await reload();\n    } catch (e) {', 2)

old_card = """                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(children: [
                        CircleAvatar(child: Icon(staff == null ? Icons.person_rounded : Icons.admin_panel_settings_rounded)),
                        const SizedBox(width: 11),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${p['full_name'] ?? _uct(context, 'Unnamed account', 'حساب بدون اسم', 'Naamloos account')}', style: const TextStyle(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 2),
                          Text('${auth?['email'] ?? '-'} • ${p['phone'] ?? '-'}', style: const TextStyle(color: VetColors.muted, fontSize: 12)),
                          const SizedBox(height: 4),
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            Chip(label: Text(_roleLabel(context, role))),
                            Chip(label: Text('${p['account_status'] ?? 'active'}')),
                          ]),
                        ])),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(onPressed: () => _manage(p, data), icon: const Icon(Icons.manage_accounts_rounded), label: Text(_uct(context, 'Manage', 'إدارة', 'Beheren'))),
                      ]),
                    ),
                  );
"""
new_card = """                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: LayoutBuilder(builder: (context, c) {
                        final narrow = c.maxWidth < 520;
                        final details = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${p['full_name'] ?? _uct(context, 'Unnamed account', 'حساب بدون اسم', 'Naamloos account')}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${auth?['email'] ?? '-'}',
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: VetColors.muted, fontSize: 12),
                            ),
                            if ('${p['phone'] ?? ''}'.trim().isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text('${p['phone']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: VetColors.muted, fontSize: 11.5)),
                            ],
                            const SizedBox(height: 6),
                            Wrap(spacing: 5, runSpacing: 5, children: [
                              Chip(visualDensity: VisualDensity.compact, label: Text(_roleLabel(context, role), style: const TextStyle(fontSize: 10.5))),
                              Chip(visualDensity: VisualDensity.compact, label: Text('${p['account_status'] ?? 'active'}', style: const TextStyle(fontSize: 10.5))),
                            ]),
                          ],
                        );
                        if (narrow) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(radius: 22, child: Icon(staff == null ? Icons.person_rounded : Icons.admin_panel_settings_rounded)),
                              const SizedBox(width: 10),
                              Expanded(child: details),
                              const SizedBox(width: 6),
                              IconButton.filledTonal(
                                tooltip: _uct(context, 'Manage', 'إدارة', 'Beheren'),
                                onPressed: () => _manage(p, data),
                                icon: const Icon(Icons.manage_accounts_rounded, size: 20),
                              ),
                            ],
                          );
                        }
                        return Row(children: [
                          CircleAvatar(child: Icon(staff == null ? Icons.person_rounded : Icons.admin_panel_settings_rounded)),
                          const SizedBox(width: 11),
                          Expanded(child: details),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(onPressed: () => _manage(p, data), icon: const Icon(Icons.manage_accounts_rounded), label: Text(_uct(context, 'Manage', 'إدارة', 'Beheren'))),
                        ]);
                      }),
                    ),
                  );
"""
s = replace_once(s, old_card, new_card, 'responsive account card')
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# 2) Staff/RBAC dialog: keep field labels permanently visible, include Manager
#    and Assistant Manager, and invalidate cached staff lists after changes.
# ---------------------------------------------------------------------------
p = Path('lib/admin/admin_staff_center.dart')
s = p.read_text(encoding='utf-8')

s = s.replace(
    "decoration: InputDecoration(labelText: _st(context, 'User account', 'حساب المستخدم', 'Gebruikersaccount')),
",
    "decoration: InputDecoration(labelText: _st(context, 'User account', 'حساب المستخدم', 'Gebruikersaccount'), floatingLabelBehavior: FloatingLabelBehavior.always, hintText: _st(context, 'Select an account', 'اختر حسابًا', 'Selecteer een account')),
",
    1,
)
s = s.replace(
    "decoration: InputDecoration(labelText: _st(context, 'Base role', 'الدور الأساسي', 'Basisrol')),
",
    "decoration: InputDecoration(labelText: _st(context, 'Base role', 'الدور الأساسي', 'Basisrol'), floatingLabelBehavior: FloatingLabelBehavior.always),
",
    1,
)
role_anchor = """                    DropdownMenuItem(value: 'super_admin', child: Text('Super Admin')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
"""
role_new = """                    DropdownMenuItem(value: 'super_admin', child: Text('Super Admin')),
                    DropdownMenuItem(value: 'manager', child: Text('Manager')),
                    DropdownMenuItem(value: 'assistant_manager', child: Text('Assistant Manager')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
"""
if "value: 'manager'" not in s:
    s = replace_once(s, role_anchor, role_new, 'staff manager roles')

s = s.replace('  void reload() => setState(() => future = _load());', """  Future<void> reload() async {
    admin.invalidateCache();
    final next = _load();
    if (mounted) setState(() => future = next);
    await next;
  }""", 1)
s = s.replace("    reload();\n  }\n\n  Future<void> _remove", "    await reload();\n  }\n\n  Future<void> _remove", 1)
s = s.replace("    reload();\n  }\n\n  String _permissionLabel", "    await reload();\n  }\n\n  String _permissionLabel", 1)
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# 3) Dashboard: clickable own-account tile in the drawer/sidebar. This opens a
#    complete editable account page without changing the current dashboard tab.
# ---------------------------------------------------------------------------
p = Path('lib/admin/admin_dashboard.dart')
s = p.read_text(encoding='utf-8')
if "import 'admin_my_account_page.dart';" not in s:
    s = s.replace("import 'admin_service.dart';\n", "import 'admin_service.dart';\nimport 'admin_my_account_page.dart';\n", 1)

if 'void _openMyAccount()' not in s:
    anchor = """  @override
  void dispose() {
"""
    helper = """  void _openMyAccount() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VetAdminMyAccountPage()),
    );
  }

"""
    if anchor not in s:
        raise SystemExit('V63: dashboard profile method anchor missing')
    s = s.replace(anchor, helper + anchor, 1)

mobile_anchor = """                const _AdminBrandHeader(),
                Expanded(
"""
mobile_new = """                const _AdminBrandHeader(),
                _AdminProfileTile(
                  role: role ?? 'admin',
                  onTap: _openMyAccount,
                ),
                const Divider(height: 1),
                Expanded(
"""
s = replace_once(s, mobile_anchor, mobile_new, 'mobile profile tile')

old_signed = """                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: VetColors.surface3,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: VetColors.border),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_at(context, 'Signed in as', 'تسجيل الدخول كـ', 'Ingelogd als'), style: const TextStyle(color: VetColors.muted, fontSize: 11)),
                        const SizedBox(height: 4),
                        Text(role ?? 'admin', style: const TextStyle(fontWeight: FontWeight.w900)),
                      ]),
                    ),
                  ),
"""
new_signed = """                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: _AdminProfileTile(
                      role: role ?? 'admin',
                      onTap: _openMyAccount,
                      compact: true,
                    ),
                  ),
"""
s = replace_once(s, old_signed, new_signed, 'desktop profile tile')

if 'class _AdminProfileTile extends StatelessWidget' not in s:
    marker = "class _AdminDestination {"
    widget = r'''class _AdminProfileTile extends StatelessWidget {
  const _AdminProfileTile({
    required this.role,
    required this.onTap,
    this.compact = false,
  });

  final String role;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final user = VetAdminService.instance.client.auth.currentUser;
    final metadata = user?.userMetadata;
    final rawName = metadata is Map ? metadata['full_name'] : null;
    final name = '${rawName ?? ''}'.trim().isNotEmpty
        ? '${rawName}'.trim()
        : (user?.email?.split('@').first ?? _at(context, 'My account', 'حسابي', 'Mijn account'));
    final email = user?.email ?? '';
    return Material(
      color: compact ? VetColors.surface3 : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16, vertical: compact ? 11 : 10),
          child: Row(children: [
            CircleAvatar(
              radius: compact ? 18 : 20,
              backgroundColor: VetColors.softGreen,
              child: const Icon(Icons.person_rounded, color: VetColors.green),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
              if (!compact && email.isNotEmpty) Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: VetColors.muted, fontSize: 10.5)),
              Text(role, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: VetColors.muted, fontSize: 10.5)),
            ])),
            const Icon(Icons.chevron_right_rounded, color: VetColors.muted),
          ]),
        ),
      ),
    );
  }
}

'''
    if marker not in s:
        raise SystemExit('V63: profile tile class anchor missing')
    s = s.replace(marker, widget + marker, 1)
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# 4) Mobile overview: two compact KPI cards per row instead of a tall single
#    card stack. Desktop/tablet keep 3–4 columns.
# ---------------------------------------------------------------------------
p = Path('lib/admin/admin_operations_center.dart')
s = p.read_text(encoding='utf-8')
old_width = """                    final w = c.maxWidth;
                    final cardWidth = w >= 1200 ? (w - 48) / 4 : w >= 760 ? (w - 32) / 3 : w >= 500 ? (w - 16) / 2 : w;
                    return Wrap(spacing: 16, runSpacing: 16, children: [for (final m in metrics) SizedBox(width: cardWidth, child: _OpsMetricCard(m))]);
"""
new_width = """                    final w = c.maxWidth;
                    final columns = w >= 1200 ? 4 : w >= 760 ? 3 : 2;
                    const gap = 10.0;
                    final cardWidth = (w - gap * (columns - 1)) / columns;
                    return Wrap(spacing: gap, runSpacing: gap, children: [for (final m in metrics) SizedBox(width: cardWidth, child: _OpsMetricCard(m))]);
"""
s = replace_once(s, old_width, new_width, 'operations two-column mobile grid')
p.write_text(s, encoding='utf-8')


# ---------------------------------------------------------------------------
# 5) Guard markers: reports must be the real intelligence page and profile page
#    must exist. This prevents a generated build from silently dropping them.
# ---------------------------------------------------------------------------
checks = {
    'lib/admin/admin_account_control_v2.dart': ['softWrap: false', 'Future<void> reload() async'],
    'lib/admin/admin_staff_center.dart': ['FloatingLabelBehavior.always', "value: 'manager'", "value: 'assistant_manager'"],
    'lib/admin/admin_dashboard.dart': ['VetAdminMyAccountPage', '_AdminProfileTile', 'void _openMyAccount()'],
    'lib/admin/admin_operations_center.dart': ['final columns = w >= 1200 ? 4 : w >= 760 ? 3 : 2'],
    'lib/admin/admin_reports_center.dart': ['latest_sensor_telemetry', 'Telemetry quality & credibility', 'AI + veterinary decision intelligence'],
    'lib/admin/admin_my_account_page.dart': ['My Vet AI account', 'Save all changes'],
}
for path, markers in checks.items():
    text = Path(path).read_text(encoding='utf-8')
    for marker in markers:
        if marker not in text:
            raise SystemExit(f'V63 verification missing {marker} in {path}')

print('Vet AI V63 applied: responsive accounts, live local refresh, stable RBAC labels, editable admin profile, 2-column mobile dashboard, flagship intelligence reports')

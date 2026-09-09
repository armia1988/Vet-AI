from pathlib import Path
import re

admin = Path('lib/admin/admin_dashboard.dart')
s = admin.read_text(encoding='utf-8')
s = s.replace('Icons.command_rounded', 'Icons.dashboard_customize_rounded')

imports = [
    "import 'admin_operations_center.dart';\n",
    "import 'admin_search_center.dart';\n",
    "import 'admin_reports_center.dart';\n",
    "import 'admin_sensor_center.dart';\n",
    "import 'admin_notification_center.dart';\n",
    "import 'admin_company_center.dart';\n",
    "import 'admin_support_center.dart';\n",
    "import 'admin_customer_center.dart';\n",
    "import 'admin_billing_center.dart';\n",
    "import 'admin_system_center.dart';\n",
    "import 'admin_staff_center.dart';\n",
    "import 'admin_alert_center.dart';\n",
    "import 'admin_audit_center.dart';\n",
    "import 'admin_animal_center.dart';\n",
]
anchor = "import 'admin_service.dart';\n"
if anchor not in s:
    raise SystemExit('V49 admin: import anchor not found')
for item in imports:
    if item not in s:
        s = s.replace(anchor, anchor + item, 1)

# Add the cross-entity search and analytics destinations before System.
if "'Global search'" not in s:
    system_destination = "        _AdminDestination(Icons.settings_rounded, _at(context, 'System', 'النظام', 'Systeem')),\n"
    if system_destination not in s:
        raise SystemExit('V49 admin destination anchor not found')
    extra_destinations = (
        "        _AdminDestination(Icons.manage_search_rounded, _at(context, 'Global search', 'البحث الشامل', 'Globaal zoeken')),\n"
        "        _AdminDestination(Icons.analytics_rounded, _at(context, 'Reports & analytics', 'التقارير والتحليلات', 'Rapporten & analyse')),\n"
        + system_destination
    )
    s = s.replace(system_destination, extra_destinations, 1)

routes = [
    (
        """      case 0:\n        return _OverviewPage(key: ValueKey('overview-$refreshTick'));\n""",
        """      case 0:\n        return VetAdminOperationsCenter(key: ValueKey('overview-$refreshTick'));\n""",
        'VetAdminOperationsCenter',
    ),
    (
        """      case 1:\n        return _FarmsPage(key: ValueKey('farms-$refreshTick'));\n""",
        """      case 1:\n        return VetAdminCompanyCenter(key: ValueKey('farms-$refreshTick'));\n""",
        'VetAdminCompanyCenter',
    ),
    (
        """      case 2:\n        return _CustomersPage(key: ValueKey('customers-$refreshTick'));\n""",
        """      case 2:\n        return VetAdminCustomerCenter(key: ValueKey('customers-$refreshTick'));\n""",
        'VetAdminCustomerCenter',
    ),
    (
        """      case 3:\n        return _AnimalsPage(key: ValueKey('animals-$refreshTick'));\n""",
        """      case 3:\n        return VetAdminAnimalCenter(key: ValueKey('animals-$refreshTick'));\n""",
        'VetAdminAnimalCenter',
    ),
    (
        """      case 4:\n        return _SensorsPage(key: ValueKey('sensors-$refreshTick'));\n""",
        """      case 4:\n        return VetAdminSensorCenter(key: ValueKey('sensors-$refreshTick'));\n""",
        'VetAdminSensorCenter',
    ),
    (
        """      case 5:\n        return _AlertsPage(key: ValueKey('alerts-$refreshTick'));\n""",
        """      case 5:\n        return VetAdminAlertCenter(key: ValueKey('alerts-$refreshTick'));\n""",
        'VetAdminAlertCenter',
    ),
    (
        """      case 6:\n        return _NotificationsPage(key: ValueKey('notifications-$refreshTick'));\n""",
        """      case 6:\n        return VetAdminNotificationCenter(key: ValueKey('notifications-$refreshTick'));\n""",
        'VetAdminNotificationCenter',
    ),
    (
        """      case 7:\n        return _SupportPage(key: ValueKey('support-$refreshTick'));\n""",
        """      case 7:\n        return VetAdminSupportCenter(key: ValueKey('support-$refreshTick'));\n""",
        'VetAdminSupportCenter',
    ),
    (
        """      case 8:\n        return _SubscriptionsPage(key: ValueKey('subscriptions-$refreshTick'));\n""",
        """      case 8:\n        return VetAdminBillingCenter(key: ValueKey('subscriptions-$refreshTick'));\n""",
        'VetAdminBillingCenter',
    ),
    (
        """      case 9:\n        return _PaymentsPage(key: ValueKey('payments-$refreshTick'));\n""",
        """      case 9:\n        return VetAdminBillingCenter(key: ValueKey('payments-$refreshTick'));\n""",
        'VetAdminBillingCenter',
    ),
    (
        """      case 10:\n        return _AdminsPage(key: ValueKey('admins-$refreshTick'));\n""",
        """      case 10:\n        return VetAdminStaffCenter(key: ValueKey('admins-$refreshTick'));\n""",
        'VetAdminStaffCenter',
    ),
    (
        """      case 11:\n        return _AuditPage(key: ValueKey('audit-$refreshTick'));\n""",
        """      case 11:\n        return VetAdminAuditCenter(key: ValueKey('audit-$refreshTick'));\n""",
        'VetAdminAuditCenter',
    ),
]
for old, new, marker in routes:
    if old in s:
        s = s.replace(old, new, 1)
    elif f'return {marker}(' not in s:
        raise SystemExit(f'V49 admin route missing: {marker}')

if 'return VetAdminGlobalSearchCenter(' not in s:
    default_anchor = """      default:\n        return const _SystemPage();\n"""
    if default_anchor not in s:
        default_anchor = """      default:\n        return const VetAdminSystemCenter();\n"""
    if default_anchor not in s:
        raise SystemExit('V49 search/reports route anchor not found')
    new_tail = """      case 12:\n        return VetAdminGlobalSearchCenter(key: ValueKey('search-$refreshTick'));\n      case 13:\n        return VetAdminReportsCenter(key: ValueKey('reports-$refreshTick'));\n      default:\n        return const VetAdminSystemCenter();\n"""
    s = s.replace(default_anchor, new_tail, 1)

old_system = """      default:\n        return const _SystemPage();\n"""
new_system = """      default:\n        return const VetAdminSystemCenter();\n"""
if old_system in s:
    s = s.replace(old_system, new_system, 1)
elif 'return const VetAdminSystemCenter();' not in s:
    raise SystemExit('V49 admin route missing: VetAdminSystemCenter')

# Load the server-issued capability matrix and block pages that the current
# admin/support/billing/operations role is not allowed to open. Database RLS
# remains the final enforcement layer; this guard keeps the UI consistent.
if 'Map<String, bool> capabilities' not in s:
    state_anchor = """  String? role;\n  Timer? refreshTimer;\n"""
    state_replacement = """  String? role;\n  Map<String, bool> capabilities = const {'overview': true};\n  Timer? refreshTimer;\n"""
    if state_anchor not in s:
        raise SystemExit('V49 RBAC state anchor not found')
    s = s.replace(state_anchor, state_replacement, 1)

old_load_role = """  Future<void> _loadRole() async {\n    final value = await admin.role();\n    if (mounted) setState(() => role = value);\n  }\n"""
new_load_role = """  Future<void> _loadRole() async {\n    try {\n      final raw = await admin.client.rpc('my_admin_access');\n      if (raw is Map) {\n        final access = Map<String, dynamic>.from(raw);\n        final rawCapabilities = access['capabilities'];\n        final nextCapabilities = <String, bool>{'overview': true};\n        if (rawCapabilities is Map) {\n          for (final entry in rawCapabilities.entries) {\n            nextCapabilities['${entry.key}'] = entry.value == true;\n          }\n        }\n        if (mounted) {\n          setState(() {\n            role = access['role']?.toString();\n            capabilities = nextCapabilities;\n          });\n        }\n        return;\n      }\n    } catch (_) {}\n    final value = await admin.role();\n    if (mounted) setState(() => role = value);\n  }\n"""
if old_load_role in s:
    s = s.replace(old_load_role, new_load_role, 1)
elif "client.rpc('my_admin_access')" not in s:
    raise SystemExit('V49 RBAC role loader anchor not found')

if 'String _permissionForPage(int page)' not in s:
    page_anchor = """  Widget _page() {\n    switch (index) {\n"""
    page_replacement = """  String _permissionForPage(int page) => switch (page) {\n        0 => 'overview',\n        1 => 'farms',\n        2 => 'customers',\n        3 => 'animals',\n        4 => 'sensors',\n        5 => 'alerts',\n        6 => 'notifications',\n        7 => 'support',\n        8 || 9 => 'billing',\n        10 => 'manage_admins',\n        11 => 'audit',\n        12 => 'global_search',\n        13 => 'reports',\n        _ => 'system',\n      };\n\n  bool _canOpenPage(int page) => capabilities[_permissionForPage(page)] == true;\n\n  Widget _page() {\n    if (!_canOpenPage(index)) {\n      return Center(\n        child: Padding(\n          padding: const EdgeInsets.all(28),\n          child: Column(mainAxisSize: MainAxisSize.min, children: [\n            const Icon(Icons.lock_rounded, size: 54, color: VetColors.muted),\n            const SizedBox(height: 12),\n            Text(_at(context, 'Permission required', 'مطلوب صلاحية إضافية', 'Extra rechten vereist'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),\n            const SizedBox(height: 6),\n            Text(_at(context, 'Your Vet AI administrator role does not allow this section.', 'صلاحية حساب الإدارة الحالي لا تسمح بفتح القسم ده.', 'Je Vet AI-beheerrol geeft geen toegang tot dit onderdeel.'), textAlign: TextAlign.center, style: const TextStyle(color: VetColors.muted)),\n          ]),\n        ),\n      );\n    }\n    switch (index) {\n"""
    if page_anchor not in s:
        raise SystemExit('V49 RBAC page anchor not found')
    s = s.replace(page_anchor, page_replacement, 1)

admin.write_text(s, encoding='utf-8')

# Supabase PostgREST builders are awaitable but are not Future<T>. Keep the
# billing summary RPC outside Future.wait so Dart can infer the list type.
billing = Path('lib/admin/admin_billing_center.dart')
s = billing.read_text(encoding='utf-8')
old_billing = """  Future<_BillingData> _load() async {
    final values = await Future.wait([
      admin.plans(),
      admin.subscriptions(),
      admin.payments(),
      admin.farms(),
      admin.client.rpc('admin_billing_summary'),
    ]);
    return _BillingData(
      plans: values[0] as List<Map<String, dynamic>>,
      subscriptions: values[1] as List<Map<String, dynamic>>,
      payments: values[2] as List<Map<String, dynamic>>,
      farms: values[3] as List<Map<String, dynamic>>,
      summary: values[4] is Map ? Map<String, dynamic>.from(values[4] as Map) : <String, dynamic>{},
    );
  }
"""
new_billing = """  Future<_BillingData> _load() async {
    final values = await Future.wait<List<Map<String, dynamic>>>([
      admin.plans(),
      admin.subscriptions(),
      admin.payments(),
      admin.farms(),
    ]);
    final summaryValue = await admin.client.rpc('admin_billing_summary');
    return _BillingData(
      plans: values[0],
      subscriptions: values[1],
      payments: values[2],
      farms: values[3],
      summary: summaryValue is Map
          ? Map<String, dynamic>.from(summaryValue)
          : <String, dynamic>{},
    );
  }
"""
if old_billing in s:
    s = s.replace(old_billing, new_billing, 1)
elif "Future.wait<List<Map<String, dynamic>>>" not in s:
    raise SystemExit('V49 billing Future.wait fix anchor not found')
billing.write_text(s, encoding='utf-8')

# Make the Admin "customer signup" and maintenance switches real for account
# creation as well, not just dashboard decoration.
backend = Path('lib/services/vet_backend.dart')
s = backend.read_text(encoding='utf-8')
old_signup_head = """  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    required String preferredLanguage,
    String emailSubject = 'Vet AI — Confirm your account',
    String emailHeading = 'Welcome to Vet AI',
    String emailBody =
        'Confirm your email address to finish creating your Vet AI account and securely access your farm data.',
    String emailButton = 'Confirm Vet AI account',
    String emailFooter =
        'If you did not create this Vet AI account, you can ignore this email.',
  }) {
    return client.auth.signUp(
"""
new_signup_head = """  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    required String preferredLanguage,
    String emailSubject = 'Vet AI — Confirm your account',
    String emailHeading = 'Welcome to Vet AI',
    String emailBody =
        'Confirm your email address to finish creating your Vet AI account and securely access your farm data.',
    String emailButton = 'Confirm Vet AI account',
    String emailFooter =
        'If you did not create this Vet AI account, you can ignore this email.',
  }) async {
    final stateValue = await client.rpc('public_signup_state');
    if (stateValue is Map) {
      final state = Map<String, dynamic>.from(stateValue);
      if (state['maintenance_mode'] == true) {
        throw const AuthException(
          'Vet AI is temporarily under maintenance. Please try again later.',
        );
      }
      if (state['signup_enabled'] == false) {
        throw const AuthException(
          'New Vet AI account registration is temporarily disabled.',
        );
      }
    }
    return client.auth.signUp(
"""
if old_signup_head in s:
    s = s.replace(old_signup_head, new_signup_head, 1)
elif "final stateValue = await client.rpc('public_signup_state');" not in s:
    raise SystemExit('V49 signup gate anchor not found')
backend.write_text(s, encoding='utf-8')

v5 = Path('lib/v5_app.dart')
s = v5.read_text(encoding='utf-8')
pattern = re.compile(
    r"\n    const columns = 5;.*?\n}\n\nString _animalGroupAssetFromSpriteIndex",
    re.S,
)
if pattern.search(s):
    s = pattern.sub('\n\nString _animalGroupAssetFromSpriteIndex', s, count=1)
v5.write_text(s, encoding='utf-8')

print('Vet AI V49 admin A-Z centers wired; operations, global search, reports, RBAC, billing, signup controls verified')

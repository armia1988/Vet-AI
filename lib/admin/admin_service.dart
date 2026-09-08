import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/vet_backend.dart';

class VetAdminService {
  VetAdminService._();
  static final instance = VetAdminService._();

  SupabaseClient get client => VetBackend.instance.client;

  Future<bool> isAdmin() async {
    if (client.auth.currentUser == null) return false;
    try {
      final value = await client.rpc('is_admin_account');
      return value == true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> role() async {
    try {
      final value = await client.rpc('my_admin_role');
      return value?.toString();
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> stats() async {
    final value = await client.rpc('admin_dashboard_stats');
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> _rows(
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

  Future<List<Map<String, dynamic>>> farms() =>
      _rows('farms', orderBy: 'created_at');

  Future<List<Map<String, dynamic>>> profiles() =>
      _rows('profiles', orderBy: 'created_at');

  Future<List<Map<String, dynamic>>> animals() =>
      _rows('animals', orderBy: 'created_at');

  Future<List<Map<String, dynamic>>> sensors() =>
      _rows('sensor_devices', orderBy: 'created_at');

  Future<List<Map<String, dynamic>>> sensorRules() =>
      _rows('sensor_alert_rules', orderBy: 'updated_at');

  Future<List<Map<String, dynamic>>> alerts() =>
      _rows('alerts', orderBy: 'created_at', limit: 1000);

  Future<List<Map<String, dynamic>>> supportThreads() =>
      _rows('support_threads', orderBy: 'updated_at', limit: 500);

  Future<List<Map<String, dynamic>>> subscriptions() =>
      _rows('farm_subscriptions', orderBy: 'updated_at');

  Future<List<Map<String, dynamic>>> plans() =>
      _rows('subscription_plans', orderBy: 'monthly_price', ascending: true);

  Future<List<Map<String, dynamic>>> payments() =>
      _rows('payments', orderBy: 'created_at', limit: 1000);

  Future<List<Map<String, dynamic>>> notifications() =>
      _rows('admin_notifications', orderBy: 'created_at', limit: 500);

  Future<List<Map<String, dynamic>>> admins() =>
      _rows('admin_accounts', orderBy: 'created_at');

  Future<List<Map<String, dynamic>>> pushDevices() =>
      _rows('push_devices', orderBy: 'last_seen_at');

  Future<List<Map<String, dynamic>>> auditLog() =>
      _rows('admin_audit_log', orderBy: 'created_at', limit: 1000);

  Future<void> updateFarm(String id, Map<String, dynamic> values) async {
    await client.from('farms').update(values).eq('id', id);
  }

  Future<void> updateProfile(String id, Map<String, dynamic> values) async {
    await client.from('profiles').update(values).eq('id', id);
  }

  Future<void> updateSensor(String id, Map<String, dynamic> values) async {
    await client.from('sensor_devices').update(values).eq('id', id);
  }

  Future<void> setSensorActive(
    String id,
    bool active, {
    String? reason,
  }) async {
    await client.from('sensor_devices').update({
      'active': active,
      'admin_disabled_reason': active ? null : reason,
    }).eq('id', id);
  }

  Future<void> updateSensorRule(String id, Map<String, dynamic> values) async {
    await client.from('sensor_alert_rules').update(values).eq('id', id);
  }

  Future<void> setPushDeviceEnabled(String id, bool enabled) async {
    await client.from('push_devices').update({'enabled': enabled}).eq('id', id);
  }

  Future<void> acknowledgeAlert(String id) async {
    await client.from('alerts').update({
      'acknowledged_at': DateTime.now().toIso8601String(),
      'acknowledged_by': client.auth.currentUser!.id,
    }).eq('id', id);
  }

  Future<void> updateSupportThread(
    String id,
    Map<String, dynamic> values,
  ) async {
    await client.from('support_threads').update(values).eq('id', id);
  }

  Future<void> markSupportRead(String id) async {
    await client.rpc('admin_mark_support_read', params: {'p_thread_id': id});
  }

  Future<void> updateSubscription(
    String id,
    Map<String, dynamic> values,
  ) async {
    await client.from('farm_subscriptions').update(values).eq('id', id);
  }

  Future<Map<String, dynamic>> createSubscription({
    required String farmId,
    required String? planId,
    required String status,
    required String billingCycle,
    required String currency,
    required double amount,
    DateTime? periodEnd,
  }) async {
    final row = await client
        .from('farm_subscriptions')
        .insert({
          'farm_id': farmId,
          'plan_id': planId,
          'status': status,
          'billing_cycle': billingCycle,
          'currency': currency,
          'amount': amount,
          if (periodEnd != null)
            'current_period_end': periodEnd.toUtc().toIso8601String(),
        })
        .select()
        .single();
    return Map<String, dynamic>.from(row);
  }

  Future<void> updatePlan(String id, Map<String, dynamic> values) async {
    await client.from('subscription_plans').update(values).eq('id', id);
  }

  Future<void> updatePayment(String id, Map<String, dynamic> values) async {
    await client.from('payments').update(values).eq('id', id);
  }

  Future<Map<String, dynamic>> createPayment({
    required String farmId,
    String? subscriptionId,
    required double amount,
    required String currency,
    required String status,
    String provider = 'manual',
    String? description,
    DateTime? dueAt,
  }) async {
    final row = await client
        .from('payments')
        .insert({
          'farm_id': farmId,
          'subscription_id': subscriptionId,
          'amount': amount,
          'currency': currency,
          'status': status,
          'provider': provider,
          'description': description,
          if (dueAt != null) 'due_at': dueAt.toUtc().toIso8601String(),
          if (status == 'paid') 'paid_at': DateTime.now().toUtc().toIso8601String(),
        })
        .select()
        .single();
    return Map<String, dynamic>.from(row);
  }

  Future<Map<String, dynamic>> sendNotification({
    required String targetScope,
    String? farmId,
    String? userId,
    required String title,
    required String body,
    required String severity,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Admin login required.');
    final inserted = await client
        .from('admin_notifications')
        .insert({
          'created_by': user.id,
          'target_scope': targetScope,
          'farm_id': farmId,
          'user_id': userId,
          'title': title.trim(),
          'body': body.trim(),
          'severity': severity,
          'status': 'sending',
        })
        .select()
        .single();
    final id = inserted['id'].toString();
    final response = await client.functions.invoke(
      'admin-push-notification',
      body: {'notification_id': id},
    );
    if (response.data is Map) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    return {'ok': false, 'notification_id': id};
  }

  Future<void> upsertAdmin({
    required String userId,
    required String role,
    required bool active,
    Map<String, bool> permissions = const {},
  }) async {
    await client.from('admin_accounts').upsert({
      'user_id': userId,
      'role': role,
      'active': active,
      'permissions': permissions,
    });
  }

  Future<void> removeAdmin(String userId) async {
    await client.from('admin_accounts').delete().eq('user_id', userId);
  }
}

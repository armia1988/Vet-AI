import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class FarmSetupPayload {
  const FarmSetupPayload({
    required this.companyName,
    required this.farmName,
    required this.country,
    required this.region,
    required this.workerCount,
    required this.veterinarianCount,
    required this.barnCount,
    required this.totalIndoorAreaM2,
    required this.livestockCount,
    required this.poultryCount,
    required this.dogCount,
    required this.breeds,
    required this.ageRange,
    required this.productionPurpose,
    required this.ventilationSystem,
    required this.vaccinationNotes,
    required this.diseaseHistory,
    required this.subscriptionTier,
    required this.billingCycle,
  });

  final String companyName;
  final String farmName;
  final String country;
  final String region;
  final int workerCount;
  final int veterinarianCount;
  final int barnCount;
  final double totalIndoorAreaM2;
  final int livestockCount;
  final int poultryCount;
  final int dogCount;
  final String breeds;
  final String ageRange;
  final String productionPurpose;
  final String ventilationSystem;
  final String vaccinationNotes;
  final String diseaseHistory;
  final String subscriptionTier;
  final String billingCycle;

  Map<String, dynamic> toRpcJson() => {
        'company_name': companyName.trim(),
        'farm_name': farmName.trim(),
        'country': country.trim(),
        'region': region.trim(),
        'worker_count': workerCount,
        'veterinarian_count': veterinarianCount,
        'barn_count': barnCount,
        'total_indoor_area_m2': totalIndoorAreaM2,
        'livestock_count': livestockCount,
        'poultry_count': poultryCount,
        'dog_count': dogCount,
        'breeds': breeds.trim(),
        'age_range': ageRange.trim(),
        'production_purpose': productionPurpose.trim(),
        'ventilation_system': ventilationSystem.trim(),
        'vaccination_notes': vaccinationNotes.trim(),
        'disease_history': diseaseHistory.trim(),
        'subscription_tier': subscriptionTier,
        'billing_cycle': billingCycle,
      };
}

class VetBackend {
  VetBackend._();

  static final VetBackend instance = VetBackend._();
  static const authCallbackUrl = 'vetai://login-callback/';

  SupabaseClient get client => Supabase.instance.client;
  User? get currentUser => client.auth.currentUser;
  bool get signedIn => currentUser != null;
  bool get emailConfirmed => currentUser?.emailConfirmedAt != null;

  Stream<AuthState> get authChanges => client.auth.onAuthStateChange;

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    required String preferredLanguage,
  }) {
    return client.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: authCallbackUrl,
      data: {
        'full_name': fullName.trim(),
        'phone': phone.trim(),
        'preferred_language': preferredLanguage,
      },
    );
  }

  Future<AuthResponse> signIn({required String email, required String password}) async {
    final response = await client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    if (response.user?.emailConfirmedAt == null) {
      await client.auth.signOut();
      throw const AuthException('Please confirm your email address before signing in.');
    }
    return response;
  }

  Future<void> signOut() => client.auth.signOut();

  Future<Map<String, dynamic>?> myFarm() async {
    final user = currentUser;
    if (user == null || !emailConfirmed) return null;
    final rows = await client
        .from('farms')
        .select()
        .eq('owner_id', user.id)
        .order('created_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  Future<String> createFarm(FarmSetupPayload p) async {
    if (!signedIn) throw StateError('You must be signed in.');
    if (!emailConfirmed) throw StateError('Confirm your email address first.');

    final result = await client.rpc(
      'create_farm_onboarding',
      params: {'p': p.toRpcJson()},
    );
    if (result is String && result.isNotEmpty) return result;
    throw StateError('The farm could not be created. Please try again.');
  }

  Future<List<Map<String, dynamic>>> recentAlerts(String farmId) async {
    final rows = await client
        .from('alerts')
        .select()
        .eq('farm_id', farmId)
        .order('created_at', ascending: false)
        .limit(30);
    return rows.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<Map<String, dynamic>>> recentAssessments(String farmId) async {
    final rows = await client
        .from('assessments')
        .select()
        .eq('farm_id', farmId)
        .order('created_at', ascending: false)
        .limit(30);
    return rows.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<String> uploadDiagnosticMedia({
    required String farmId,
    required Uint8List bytes,
    required String extension,
  }) async {
    final user = currentUser;
    if (user == null || !emailConfirmed) {
      throw StateError('A verified account is required.');
    }

    final safeExtension = extension.replaceAll('.', '').toLowerCase();
    final path = '${user.id}/$farmId/${DateTime.now().millisecondsSinceEpoch}.$safeExtension';
    await client.storage.from('diagnostic-media').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: false),
        );
    return path;
  }

  Future<String> createDraftAssessment({
    required String farmId,
    required String mediaPath,
    String symptomNotes = '',
    String animalGroup = 'livestock',
  }) async {
    final user = currentUser;
    if (user == null || !emailConfirmed) {
      throw StateError('A verified account is required.');
    }
    final row = await client
        .from('assessments')
        .insert({
          'farm_id': farmId,
          'created_by': user.id,
          'media_path': mediaPath,
          'symptom_notes': symptomNotes.trim(),
          'animal_group': animalGroup,
          'risk': 'insufficient_data',
          'status': 'draft',
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<Map<String, dynamic>> analyzeAssessment(
    String assessmentId, {
    String language = 'en',
  }) async {
    final response = await client.functions.invoke(
      'analyze-case',
      body: {
        'assessment_id': assessmentId,
        'language': language,
      },
    );
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {
      'code': 'INVALID_AI_RESPONSE',
      'risk': 'insufficient_data',
      'message': 'The protected AI service returned an unreadable response.',
    };
  }
}

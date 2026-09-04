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
}

class VetBackend {
  VetBackend._();

  static final VetBackend instance = VetBackend._();

  SupabaseClient get client => Supabase.instance.client;
  User? get currentUser => client.auth.currentUser;
  bool get signedIn => currentUser != null;

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
      data: {
        'full_name': fullName.trim(),
        'phone': phone.trim(),
        'preferred_language': preferredLanguage,
      },
    );
  }

  Future<AuthResponse> signIn({required String email, required String password}) {
    return client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signOut() => client.auth.signOut();

  Future<Map<String, dynamic>?> myFarm() async {
    final user = currentUser;
    if (user == null) return null;
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
    final user = currentUser;
    if (user == null) throw StateError('You must be signed in.');

    final row = await client
        .from('farms')
        .insert({
          'owner_id': user.id,
          'company_name': p.companyName.trim(),
          'farm_name': p.farmName.trim(),
          'country': p.country.trim(),
          'region': p.region.trim(),
          'worker_count': p.workerCount,
          'veterinarian_count': p.veterinarianCount,
          'barn_count': p.barnCount,
          'total_indoor_area_m2': p.totalIndoorAreaM2,
          'livestock_count': p.livestockCount,
          'poultry_count': p.poultryCount,
          'dog_count': p.dogCount,
          'breeds': p.breeds.trim(),
          'age_range': p.ageRange.trim(),
          'production_purpose': p.productionPurpose.trim(),
          'ventilation_system': p.ventilationSystem.trim(),
          'vaccination_notes': p.vaccinationNotes.trim(),
          'disease_history': p.diseaseHistory.trim(),
          'subscription_tier': p.subscriptionTier,
          'billing_cycle': p.billingCycle,
        })
        .select('id')
        .single();

    final farmId = row['id'] as String;

    final barnRows = <Map<String, dynamic>>[];
    for (var i = 0; i < p.barnCount; i++) {
      String group = 'livestock';
      if (p.poultryCount > 0 && p.livestockCount == 0) group = 'poultry';
      if (p.dogCount > 0 && p.livestockCount == 0 && p.poultryCount == 0) {
        group = 'dogs';
      }
      barnRows.add({
        'farm_id': farmId,
        'name': 'Barn ${i + 1}',
        'animal_group': group,
        'indoor_area_m2': p.totalIndoorAreaM2 / p.barnCount,
      });
    }
    if (barnRows.isNotEmpty) await client.from('barns').insert(barnRows);

    if (p.poultryCount > 0) {
      await client.from('flocks').insert({
        'farm_id': farmId,
        'animal_group': 'poultry',
        'name': 'Primary poultry flock',
        'head_count': p.poultryCount,
        'breed_or_strain': p.breeds.trim(),
        'production_cycle': p.ageRange.trim(),
      });
    }

    if (p.livestockCount > 0) {
      await client.from('flocks').insert({
        'farm_id': farmId,
        'animal_group': 'livestock',
        'name': 'Primary livestock group',
        'head_count': p.livestockCount,
        'breed_or_strain': p.breeds.trim(),
        'production_cycle': p.ageRange.trim(),
      });
    }

    if (p.dogCount > 0) {
      await client.from('flocks').insert({
        'farm_id': farmId,
        'animal_group': 'dogs',
        'name': 'Dogs',
        'head_count': p.dogCount,
        'breed_or_strain': p.breeds.trim(),
        'production_cycle': p.ageRange.trim(),
      });
    }

    return farmId;
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
    if (user == null) throw StateError('You must be signed in.');

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
    if (user == null) throw StateError('You must be signed in.');
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

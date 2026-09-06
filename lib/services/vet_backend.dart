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
    String emailSubject = 'Vet AI — Confirm your account',
    String emailHeading = 'Welcome to Vet AI',
    String emailBody =
        'Confirm your email address to finish creating your Vet AI account and securely access your farm data.',
    String emailButton = 'Confirm Vet AI account',
    String emailFooter =
        'If you did not create this Vet AI account, you can ignore this email.',
  }) {
    return client.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: authCallbackUrl,
      data: {
        'full_name': fullName.trim(),
        'phone': phone.trim(),
        'preferred_language': preferredLanguage,
        'language': preferredLanguage,
        'brand_name': 'Vet AI',
        'email_subject': emailSubject,
        'email_heading': emailHeading,
        'email_body': emailBody,
        'email_button': emailButton,
        'email_footer': emailFooter,
      },
    );
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    final response = await client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    if (response.user?.emailConfirmedAt == null) {
      await client.auth.signOut();
      throw const AuthException(
        'Please confirm your email address before signing in.',
      );
    }
    return response;
  }

  Future<void> signOut() => client.auth.signOut();

  Future<ResendResponse> resendSignupConfirmation(String email) {
    return client.auth.resend(
      type: OtpType.signup,
      email: email.trim(),
      emailRedirectTo: authCallbackUrl,
    );
  }

  Future<AuthResponse> refreshAuthSession() => client.auth.refreshSession();

  Future<void> sendPasswordReset(String email) {
    return client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: authCallbackUrl,
    );
  }

  Future<UserResponse> updatePassword(String password) {
    return client.auth.updateUser(UserAttributes(password: password));
  }

  Future<Map<String, dynamic>?> myProfile() async {
    final user = currentUser;
    if (user == null) return null;
    final rows = await client
        .from('profiles')
        .select()
        .eq('id', user.id)
        .limit(1);
    if (rows.isEmpty) {
      return {
        'id': user.id,
        'full_name': user.userMetadata?['full_name'] ?? '',
        'phone': user.userMetadata?['phone'] ?? '',
        'preferred_language': user.userMetadata?['preferred_language'] ?? 'en',
      };
    }
    return Map<String, dynamic>.from(rows.first);
  }

  Future<bool> scanPrivacyAcknowledged() async {
    final user = currentUser;
    if (user == null) return false;
    final rows = await client
        .from('profiles')
        .select('scan_privacy_acknowledged_at')
        .eq('id', user.id)
        .limit(1);
    return rows.isNotEmpty &&
        rows.first['scan_privacy_acknowledged_at'] != null;
  }

  Future<void> acknowledgeScanPrivacy() async {
    final user = currentUser;
    if (user == null) throw StateError('You must be signed in.');
    await client
        .from('profiles')
        .update({
          'scan_privacy_acknowledged_at': DateTime.now().toIso8601String(),
        })
        .eq('id', user.id);
  }

  Future<void> updateProfile({
    required String fullName,
    required String phone,
    required String preferredLanguage,
    String jobTitle = '',
  }) async {
    final user = currentUser;
    if (user == null) throw StateError('You must be signed in.');
    await client.from('profiles').upsert({
      'id': user.id,
      'full_name': fullName.trim(),
      'phone': phone.trim(),
      'preferred_language': preferredLanguage,
      'job_title': jobTitle.trim(),
    });
    await client.auth.updateUser(
      UserAttributes(
        data: {
          'full_name': fullName.trim(),
          'phone': phone.trim(),
          'preferred_language': preferredLanguage,
        },
      ),
    );
  }

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

  Future<Map<String, dynamic>> updateFarm(
    String farmId, {
    required String companyName,
    required String farmName,
    required String country,
    required String region,
    required int workerCount,
    required int veterinarianCount,
    required int barnCount,
    required double totalIndoorAreaM2,
    required int livestockCount,
    required int poultryCount,
    required int dogCount,
    required String breeds,
    required String ageRange,
    required String productionPurpose,
    required String ventilationSystem,
    required String vaccinationNotes,
    required String diseaseHistory,
  }) async {
    final row = await client
        .from('farms')
        .update({
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
        })
        .eq('id', farmId)
        .select()
        .single();
    return Map<String, dynamic>.from(row);
  }

  Future<Map<String, dynamic>> updateSubscription(
    String farmId, {
    required String subscriptionTier,
    required String billingCycle,
  }) async {
    final row = await client
        .from('farms')
        .update({
          'subscription_tier': subscriptionTier,
          'billing_cycle': billingCycle,
          'subscription_status': 'selected',
          'subscription_updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', farmId)
        .select()
        .single();
    return Map<String, dynamic>.from(row);
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

  Future<List<Map<String, dynamic>>> sensorDevices(String farmId) async {
    final rows = await client
        .from('sensor_devices')
        .select()
        .eq('farm_id', farmId)
        .eq('active', true)
        .order('created_at');
    return rows.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<Map<String, dynamic>>> latestSensorReadings(String farmId) async {
    final rows = await client
        .from('sensor_readings')
        .select()
        .eq('farm_id', farmId)
        .order('recorded_at', ascending: false)
        .limit(50);
    return rows.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<String> getOrCreateSupportThread(String farmId) async {
    final user = currentUser;
    if (user == null) throw StateError('You must be signed in.');
    final rows = await client
        .from('support_threads')
        .select('id')
        .eq('farm_id', farmId)
        .eq('status', 'open')
        .order('created_at', ascending: false)
        .limit(1);
    if (rows.isNotEmpty) return rows.first['id'] as String;
    final row = await client
        .from('support_threads')
        .insert({
          'farm_id': farmId,
          'created_by': user.id,
          'subject': 'Vet AI support',
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  Stream<List<Map<String, dynamic>>> supportMessagesStream(String threadId) {
    return client
        .from('support_messages')
        .stream(primaryKey: ['id'])
        .eq('thread_id', threadId)
        .order('created_at');
  }

  String _safeSupportFileName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return cleaned.isEmpty ? 'attachment' : cleaned;
  }

  Future<Map<String, dynamic>> uploadSupportAttachment({
    required String threadId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final user = currentUser;
    if (user == null || !emailConfirmed)
      throw StateError('A verified account is required.');
    if (bytes.isEmpty || bytes.length > 25 * 1024 * 1024) {
      throw StateError('Support attachments must be between 1 byte and 25 MB.');
    }
    final safeName = _safeSupportFileName(fileName);
    final path =
        '$threadId/${user.id}/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    await client.storage
        .from('support-attachments')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: false, contentType: mimeType),
        );
    return {
      'path': path,
      'name': fileName,
      'mime': mimeType,
      'size': bytes.length,
    };
  }

  Future<Uint8List> downloadSupportAttachment(String path) async {
    return client.storage.from('support-attachments').download(path);
  }

  Future<String> signedSupportAttachmentUrl(String path) async {
    return client.storage
        .from('support-attachments')
        .createSignedUrl(path, 3600);
  }

  Future<void> sendSupportMessage(
    String threadId,
    String message, {
    Map<String, dynamic>? attachment,
    String? annotatedFromMessageId,
  }) async {
    final user = currentUser;
    if (user == null) throw StateError('You must be signed in.');
    final clean = message.trim();
    if (clean.isEmpty && attachment == null) return;
    await client.from('support_messages').insert({
      'thread_id': threadId,
      'sender_id': user.id,
      'sender_role': 'user',
      'message': clean.isEmpty ? null : clean,
      if (attachment != null) 'attachment_path': attachment['path'],
      if (attachment != null) 'attachment_name': attachment['name'],
      if (attachment != null) 'attachment_mime': attachment['mime'],
      if (attachment != null) 'attachment_size_bytes': attachment['size'],
      if (annotatedFromMessageId != null)
        'annotated_from_message_id': annotatedFromMessageId,
    });
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
    final path =
        '${user.id}/$farmId/${DateTime.now().millisecondsSinceEpoch}.$safeExtension';
    await client.storage
        .from('diagnostic-media')
        .uploadBinary(
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
    String speciesCode = '',
    String? birdType,
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
          'species_code': speciesCode,
          'bird_type': birdType,
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
    try {
      final response = await client.functions.invoke(
        'analyze-case',
        body: {'assessment_id': assessmentId, 'language': language},
      );
      final data = response.data;
      Map<String, dynamic>? result;
      if (data is Map<String, dynamic>) {
        result = data;
      } else if (data is Map) {
        result = Map<String, dynamic>.from(data);
      }

      if (result != null &&
          result['code'] == 'AI_ANALYSIS_COMPLETE' &&
          result['group_match'] != 'mismatch') {
        try {
          final verifiedResponse = await client.functions
              .invoke(
                'verify-case-evidence',
                body: {'assessment_id': assessmentId, 'language': language},
              )
              .timeout(const Duration(seconds: 7));
          final verifiedData = verifiedResponse.data;
          Map<String, dynamic>? verified;
          if (verifiedData is Map<String, dynamic>) {
            verified = verifiedData;
          } else if (verifiedData is Map) {
            verified = Map<String, dynamic>.from(verifiedData);
          }
          if (verified != null &&
              verified['code'] == 'AI_ANALYSIS_COMPLETE' &&
              verified['official_evidence_verified'] == true) {
            return verified;
          }
        } catch (_) {
          // Official web verification is an accuracy layer, not a single point
          // of failure. The reviewed local veterinary knowledge result remains.
        }
      }

      if (result != null) return result;
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map<String, dynamic>) return details;
      if (details is Map) return Map<String, dynamic>.from(details);
      return {
        'code': 'AI_FUNCTION_ERROR',
        'risk': 'insufficient_data',
        'message':
            error.reasonPhrase ??
            'The protected AI service could not complete the case.',
      };
    }
    return {
      'code': 'INVALID_AI_RESPONSE',
      'risk': 'insufficient_data',
      'message': 'The protected AI service returned an unreadable response.',
    };
  }
}

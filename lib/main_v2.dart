import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'v5_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!SupabaseConfig.isConfigured || !SupabaseConfig.pointsToProduction) {
    throw StateError(
      'Vet AI production backend configuration is invalid. '
      'Expected project ${SupabaseConfig.projectRef}.',
    );
  }

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  runApp(const VetAIAppV5());
}

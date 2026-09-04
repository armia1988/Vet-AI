import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'main.dart' show VetAiApp;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!SupabaseConfig.isConfigured) {
    throw StateError(
      'Supabase is not configured. Provide SUPABASE_URL and '
      'SUPABASE_PUBLISHABLE_KEY with --dart-define.',
    );
  }

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  runApp(const VetAiApp());
}

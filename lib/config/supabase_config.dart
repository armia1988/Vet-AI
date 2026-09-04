class SupabaseConfig {
  const SupabaseConfig._();

  // These are public client credentials by design. They identify the Supabase
  // project but do not bypass Row Level Security. A build-time override is
  // still supported for staging or future key rotation.
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://mzqwjyantyvizwbzetwf.supabase.co',
  );

  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_NKsKVNCISEZSx_zOetm2rA_LlzcIDXS',
  );

  static bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;
}

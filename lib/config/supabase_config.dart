class SupabaseConfig {
  const SupabaseConfig._();

  /// Vet AI production backend. These are public client identifiers only;
  /// database access remains protected by Supabase Auth and Row Level Security.
  static const projectRef = 'mzqwjyantyvizwbzetwf';
  static const url = 'https://mzqwjyantyvizwbzetwf.supabase.co';
  static const publishableKey =
      'sb_publishable_NKsKVNCISEZSx_zOetm2rA_LlzcIDXS';

  static bool get isConfigured =>
      url.isNotEmpty && publishableKey.isNotEmpty && pointsToProduction;

  static bool get pointsToProduction {
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host == '$projectRef.supabase.co';
  }
}

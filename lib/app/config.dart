/// Configuração pública, lida de `--dart-define-from-file=config/public.json`.
///
/// Só contém valores que podem estar dentro da app. Ver config/README.md.
final class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    required this.powerSyncUrl,
  });

  factory AppConfig.fromEnvironment() => const AppConfig(
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    supabasePublishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
    powerSyncUrl: String.fromEnvironment('POWERSYNC_URL'),
  );

  final String supabaseUrl;
  final String supabasePublishableKey;
  final String powerSyncUrl;

  bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  /// Sem URL do PowerSync a app funciona localmente, mas não sincroniza.
  bool get hasPowerSync => powerSyncUrl.isNotEmpty;

  /// Deep link de regresso do OAuth no Android.
  static const androidAuthRedirect =
      'pt.rafaelfaria.guarda_roupa://login-callback';
}

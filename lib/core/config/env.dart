/// Public client config. Override per environment with --dart-define.
/// The publishable key is safe to ship; RLS enforces access.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://edarzlqkxgobdffcfnpx.supabase.co',
  );
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_jnjcRP9-THNbwNmyLRQKRQ_B42GVL7A',
  );
  /// VAPID public key for Web Push (the private key stays in Supabase Vault).
  static const vapidPublicKey = String.fromEnvironment(
    'VAPID_PUBLIC_KEY',
    defaultValue: 'BCukkPN0I1_c211Fz29uhXOYmjCXwwBLlAdYBTt8ayYI-Q_t_888di-p7Zu3d_pa-en_5OiLSJDYeKfW2GlO7pU',
  );
}

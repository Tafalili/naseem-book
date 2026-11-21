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
}

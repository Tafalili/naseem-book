import 'package:supabase_flutter/supabase_flutter.dart';

/// Public URL for an object in the public "templates" bucket.
String? templatesUrl(String? path) {
  if (path == null || path.isEmpty) return null;
  return Supabase.instance.client.storage.from('templates').getPublicUrl(path);
}

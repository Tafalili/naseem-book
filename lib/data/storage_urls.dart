import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Public URL for an object in the public "templates" bucket.
String? templatesUrl(String? path) {
  if (path == null || path.isEmpty) return null;
  return Supabase.instance.client.storage.from('templates').getPublicUrl(path);
}

/// Catalog image paths are either bundled ("asset:catalog/...") or
/// objects in the "templates" bucket. Admin uploads (phase 5) use the bucket.
ImageProvider? catalogImage(String? path) {
  if (path == null || path.isEmpty) return null;
  if (path.startsWith('asset:')) return AssetImage('assets/${path.substring(6)}');
  return NetworkImage(templatesUrl(path)!);
}

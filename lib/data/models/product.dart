import 'package:material_ui/material_ui.dart';

import '../storage_urls.dart';

class Product {
  const Product({
    required this.id,
    required this.slug,
    required this.title,
    required this.basePrice,
    required this.pageCount,
    required this.photoCapacity,
    this.description,
    this.tagline,
    this.badge,
    this.coverImagePath,
    this.gallery = const [],
    this.specs = const {},
    this.isFeatured = false,
  });

  final String id;
  final String slug;
  final String title;
  final String? description;
  final String? tagline;
  final String? badge;
  final int basePrice;
  final int pageCount;
  final int photoCapacity;
  final String? coverImagePath;
  final List<String> gallery;
  final Map<String, dynamic> specs;
  final bool isFeatured;

  static const columns =
      'id,slug,title,description,tagline,badge,base_price,page_count,photo_capacity,'
      'cover_image_path,gallery,specs,is_featured';

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'] as String,
        slug: j['slug'] as String,
        title: j['title'] as String,
        description: j['description'] as String?,
        tagline: j['tagline'] as String?,
        badge: j['badge'] as String?,
        basePrice: (j['base_price'] as num?)?.toInt() ?? 0,
        pageCount: (j['page_count'] as num?)?.toInt() ?? 0,
        photoCapacity: (j['photo_capacity'] as num?)?.toInt() ?? 0,
        coverImagePath: j['cover_image_path'] as String?,
        gallery: (j['gallery'] as List?)?.whereType<String>().toList() ?? const [],
        specs: (j['specs'] as Map?)?.cast<String, dynamic>() ?? const {},
        isFeatured: j['is_featured'] as bool? ?? false,
      );

  ImageProvider? get coverImage => catalogImage(coverImagePath);
  List<ImageProvider> get galleryImages =>
      gallery.map(catalogImage).whereType<ImageProvider>().toList();

  /// Trim size in cm from specs.trim_mm, e.g. "18.55 × 27.45 سم".
  String? get trimSizeLabel {
    final t = specs['trim_mm'];
    if (t is! Map) return null;
    String cm(Object? mm) => ((mm as num) / 10).toStringAsFixed(2);
    return '${cm(t['w'])} × ${cm(t['h'])} سم';
  }

  String? get paperLabel => switch (specs['paper']) {
        'Matte 250gsm' => 'ورق مطفي 250 غرام',
        final String s => s,
        _ => null,
      };
}

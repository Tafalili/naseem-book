import 'package:material_ui/material_ui.dart';

import '../storage_urls.dart';
import 'public_settings.dart';

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
    this.kind = 'book',
    this.options = const ItemOptions(),
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
  /// 'book' (designed in the editor) or 'item' (frames, cards, tags...).
  final String kind;
  final ItemOptions options;

  bool get isItem => kind == 'item';

  /// Books may have their own add-on prices (specs.prices) instead of the store-wide ones.
  int priceOf(Addon a, PublicSettings s) {
    final own = (specs['prices'] as Map?)?[a.key];
    return own is num ? own.toInt() : s.priceOf(a);
  }

  /// False for books sold without cover options (no child name, no «اتركه لذوقكم»).
  bool get coverCustom => specs['cover_custom'] as bool? ?? true;

  static const columns =
      'id,slug,title,description,tagline,badge,base_price,page_count,photo_capacity,'
      'cover_image_path,gallery,specs,is_featured,kind,options';

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
        kind: j['kind'] as String? ?? 'book',
        options: ItemOptions.fromJson((j['options'] as Map?)?.cast<String, dynamic>() ?? const {}),
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

  /// Inside-cover (endpaper) and back-cover artwork for the flip preview.
  ImageProvider? get endpaperImage => catalogImage(specs['endpaper_path'] as String?);
  ImageProvider? get backCoverImage => catalogImage(specs['back_cover_path'] as String?);
}

enum FieldType { text, longtext, date, time, photos }

/// One thing the customer fills in for a shop item (name, date, photos...).
class ItemField {
  const ItemField({
    required this.id,
    required this.label,
    this.type = FieldType.text,
    this.required = false,
    this.max = 60,
    this.min = 1,
    this.hint,
  });
  final String id;
  final String label;
  final FieldType type;
  final bool required;
  final int max; // characters, or photos for FieldType.photos
  final int min; // photos needed when required
  final String? hint;

  factory ItemField.fromJson(Map<String, dynamic> j) {
    final type = FieldType.values.asNameMap()[j['type']] ?? FieldType.text;
    return ItemField(
      id: j['id'] as String,
      label: j['label'] as String? ?? '',
      type: type,
      required: j['required'] as bool? ?? false,
      max: (j['max'] as num?)?.toInt() ?? (type == FieldType.photos ? 10 : 60),
      min: (j['min'] as num?)?.toInt() ?? 1,
      hint: j['hint'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'type': type.name,
        if (required) 'required': true,
        'max': max,
        if (type == FieldType.photos && min != 1) 'min': min,
        if (hint != null && hint!.isNotEmpty) 'hint': hint,
      };
}

/// products.options for shop items. submit_order() checks the same rules.
class ItemOptions {
  const ItemOptions({this.minQty = 1, this.maxQty = 99, this.unitLabel = 'قطعة', this.fields = const []});
  final int minQty, maxQty;
  final String unitLabel;
  final List<ItemField> fields;

  factory ItemOptions.fromJson(Map<String, dynamic> j) => ItemOptions(
        minQty: (j['min_qty'] as num?)?.toInt() ?? 1,
        maxQty: (j['max_qty'] as num?)?.toInt() ?? 99,
        unitLabel: j['unit_label'] as String? ?? 'قطعة',
        fields: ((j['fields'] as List?) ?? const [])
            .map((e) => ItemField.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'min_qty': minQty,
        'max_qty': maxQty,
        'unit_label': unitLabel,
        'fields': [for (final f in fields) f.toJson()],
      };
}

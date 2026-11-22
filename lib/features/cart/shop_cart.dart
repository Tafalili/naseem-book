import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/product.dart';
import '../editor/draft/image_tools.dart';
import '../editor/draft/photo_store.dart';

/// One shop item in the cart (a frame, a pack of cards...). Photos stay on the
/// device (PhotoStore) until checkout, like the books' photos.
class ShopLine {
  const ShopLine({
    required this.id,
    required this.slug,
    required this.qty,
    this.texts = const {},
    this.photos = const {},
  });
  final String id;
  final String slug;
  final int qty;
  final Map<String, String> texts; // field id -> value
  final Map<String, List<String>> photos; // field id -> PhotoStore ids

  Iterable<String> get photoIds => photos.values.expand((e) => e);

  ShopLine copyWith({int? qty, Map<String, String>? texts, Map<String, List<String>>? photos}) => ShopLine(
        id: id,
        slug: slug,
        qty: qty ?? this.qty,
        texts: texts ?? this.texts,
        photos: photos ?? this.photos,
      );

  /// First missing required field, or null when the line can be ordered.
  String? missing(Product p) {
    for (final f in p.options.fields.where((f) => f.required)) {
      if (f.type == FieldType.photos) {
        if ((photos[f.id]?.length ?? 0) < f.min) return f.label;
      } else if ((texts[f.id] ?? '').trim().isEmpty) {
        return f.label;
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {'id': id, 'slug': slug, 'qty': qty, 'texts': texts, 'photos': photos};

  factory ShopLine.fromJson(Map<String, dynamic> j) => ShopLine(
        id: j['id'] as String,
        slug: j['slug'] as String,
        qty: (j['qty'] as num).toInt(),
        texts: (j['texts'] as Map? ?? const {}).map((k, v) => MapEntry(k as String, v as String)),
        photos: (j['photos'] as Map? ?? const {})
            .map((k, v) => MapEntry(k as String, (v as List).cast<String>())),
      );
}

class ShopCartController extends Notifier<List<ShopLine>> {
  static const _key = 'shop_cart:v1';
  static const maxLines = 30;
  static final _rand = Random();

  @override
  List<ShopLine> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return;
    try {
      state = (jsonDecode(raw) as List).map((e) => ShopLine.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      state = const [];
    }
  }

  Future<void> _save(List<ShopLine> lines) async {
    state = lines;
    await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(lines.map((e) => e.toJson()).toList()));
  }

  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_rand.nextInt(1 << 20).toRadixString(36)}';

  bool get full => state.length >= maxLines;

  Future<void> put(ShopLine line) async {
    final i = state.indexWhere((e) => e.id == line.id);
    if (i < 0 && full) return;
    await _save(i < 0 ? [...state, line] : [for (final e in state) e.id == line.id ? line : e]);
  }

  Future<void> remove(String id, {bool deletePhotos = true}) async {
    final line = state.where((e) => e.id == id).firstOrNull;
    await _save(state.where((e) => e.id != id).toList());
    if (deletePhotos && line != null) {
      for (final p in line.photoIds) {
        await PhotoStore.instance.delete(p);
      }
    }
  }

  /// Picks and stores photos on the device; returns their ids.
  static Future<List<String>> importPhotos({bool multiple = true}) async {
    final files = await pickImages(multiple: multiple);
    final ids = <String>[];
    for (final f in files) {
      try {
        final c = await compressPhoto(f);
        final id = 'shop_${newId()}';
        await PhotoStore.instance.put(id, full: c.full, preview: c.preview);
        ids.add(id);
      } catch (_) {
        // unreadable file: skipped, the caller shows how many arrived
      }
    }
    return ids;
  }
}

final shopCartProvider = NotifierProvider<ShopCartController, List<ShopLine>>(ShopCartController.new);

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/page_template.dart';
import '../models/product.dart';
import '../models/promo_banner.dart';
import '../models/public_settings.dart';

class CatalogRepository {
  CatalogRepository(this._db);
  final SupabaseClient _db;

  /// Active products, featured first. RLS already hides inactive ones.
  Future<List<Product>> products() async {
    final rows = await _db
        .from('products')
        .select(Product.columns)
        .eq('is_active', true)
        .order('is_featured', ascending: false)
        .order('sort_order');
    return rows.map(Product.fromJson).toList();
  }

  Future<Product?> productBySlug(String slug) async {
    final row = await _db
        .from('products')
        .select(Product.columns)
        .eq('slug', slug)
        .eq('is_active', true)
        .maybeSingle();
    return row == null ? null : Product.fromJson(row);
  }

  /// Live banners; RLS filters by is_active and schedule window.
  Future<List<PromoBanner>> banners() async {
    final rows = await _db.from('banners').select(PromoBanner.columns).order('sort_order');
    return rows.map(PromoBanner.fromJson).toList();
  }

  Future<PublicSettings> publicSettings() async {
    final res = await _db.rpc('get_public_settings');
    return PublicSettings.fromJson(Map<String, dynamic>.from(res as Map));
  }
}

final catalogRepositoryProvider =
    Provider((ref) => CatalogRepository(Supabase.instance.client));

final productsProvider =
    FutureProvider((ref) => ref.watch(catalogRepositoryProvider).products());

final productBySlugProvider = FutureProvider.family<Product?, String>(
    (ref, slug) => ref.watch(catalogRepositoryProvider).productBySlug(slug));

final bannersProvider =
    FutureProvider((ref) => ref.watch(catalogRepositoryProvider).banners());

final publicSettingsProvider =
    FutureProvider((ref) => ref.watch(catalogRepositoryProvider).publicSettings());

/// Page templates for a product, cover (page 0) first.
final templatesProvider = FutureProvider.family<List<PageTemplate>, String>((ref, slug) async {
  final db = Supabase.instance.client;
  final rows = await db
      .from('page_templates')
      .select('${PageTemplate.columns},product:products!inner(slug)')
      .eq('product.slug', slug)
      .order('page_number');
  return rows.map(PageTemplate.fromJson).toList();
});

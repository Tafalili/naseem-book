import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One designed book in the cart. The design itself lives in the local draft
/// (`draft:<slug>`); the cart only keeps the extras chosen at checkout.
class CartItem {
  const CartItem({required this.slug, this.giftWrap = false, this.extraCopies = 0});
  final String slug;
  final bool giftWrap;
  final int extraCopies;

  static const maxExtraCopies = 5;

  CartItem copyWith({bool? giftWrap, int? extraCopies}) => CartItem(
        slug: slug,
        giftWrap: giftWrap ?? this.giftWrap,
        extraCopies: (extraCopies ?? this.extraCopies).clamp(0, maxExtraCopies),
      );

  Map<String, dynamic> toJson() =>
      {'slug': slug, 'gift_wrap': giftWrap, 'extra_copies': extraCopies};

  factory CartItem.fromJson(Map<String, dynamic> j) => CartItem(
        slug: j['slug'] as String,
        giftWrap: j['gift_wrap'] as bool? ?? false,
        extraCopies: ((j['extra_copies'] as num?)?.toInt() ?? 0).clamp(0, maxExtraCopies),
      );
}

class CartController extends Notifier<List<CartItem>> {
  static const _key = 'cart:v1';

  @override
  List<CartItem> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return;
    try {
      state = (jsonDecode(raw) as List)
          .map((e) => CartItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      state = const [];
    }
  }

  Future<void> _save(List<CartItem> items) async {
    state = items;
    await (await SharedPreferences.getInstance())
        .setString(_key, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  bool contains(String slug) => state.any((e) => e.slug == slug);

  Future<void> add(String slug) async {
    if (contains(slug)) return;
    await _save([...state, CartItem(slug: slug)]);
  }

  Future<void> update(CartItem item) =>
      _save([for (final e in state) e.slug == item.slug ? item : e]);

  Future<void> remove(String slug) => _save(state.where((e) => e.slug != slug).toList());
}

final cartProvider = NotifierProvider<CartController, List<CartItem>>(CartController.new);

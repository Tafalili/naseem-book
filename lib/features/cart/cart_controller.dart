import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../editor/draft/book_draft.dart';

/// One designed book in the cart (one per child). The design itself lives in
/// the local draft (`draft:<book>`); the cart only keeps the extras chosen here.
class CartItem {
  const CartItem({required this.book, this.giftWrap = false});
  final String book;
  final bool giftWrap;

  String get slug => slugOfBook(book);

  CartItem copyWith({bool? giftWrap}) => CartItem(book: book, giftWrap: giftWrap ?? this.giftWrap);

  Map<String, dynamic> toJson() => {'book': book, 'gift_wrap': giftWrap};

  factory CartItem.fromJson(Map<String, dynamic> j) => CartItem(
        book: (j['book'] ?? j['slug']) as String,
        giftWrap: j['gift_wrap'] as bool? ?? false,
      );
}

class CartController extends Notifier<List<CartItem>> {
  static const _key = 'cart:v1';
  static const maxBooks = 5;

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

  bool contains(String book) => state.any((e) => e.book == book);
  bool get full => state.length >= maxBooks;

  Future<void> add(String book) async {
    if (contains(book) || full) return;
    await _save([...state, CartItem(book: book)]);
  }

  Future<void> update(CartItem item) => _save([for (final e in state) e.book == item.book ? item : e]);

  Future<void> remove(String book) => _save(state.where((e) => e.book != book).toList());
}

final cartProvider = NotifierProvider<CartController, List<CartItem>>(CartController.new);

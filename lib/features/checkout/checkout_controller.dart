import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/page_template.dart';
import '../cart/cart_page.dart' show CartBook, CartShopItem;
import '../cart/shop_cart.dart';
import '../../data/models/product.dart';
import '../../data/repositories/order_repository.dart';
import '../cart/cart_controller.dart';
import '../editor/draft/book_draft.dart';
import '../editor/draft/draft_controller.dart';
import '../editor/draft/photo_store.dart';

class CustomerInfo {
  const CustomerInfo({
    required this.name,
    required this.phone,
    required this.city,
    required this.address,
    this.notes = '',
  });
  final String name, phone, city, address, notes;
}

class CheckoutState {
  const CheckoutState({this.busy = false, this.uploaded = 0, this.toUpload = 0, this.error, this.stage = ''});
  final bool busy;
  final int uploaded, toUpload;
  final String? error;
  final String stage;
}

/// Uploads only the photos the book uses, then calls submit_order(); the
/// server re-validates every path and recomputes the price.
class CheckoutController extends Notifier<CheckoutState> {
  @override
  CheckoutState build() => const CheckoutState();

  Future<String?> submit(
      {required List<CartBook> books, List<CartShopItem> items = const [], required CustomerInfo customer}) async {
    final repo = ref.read(orderRepositoryProvider);
    state = const CheckoutState(busy: true, stage: 'نجهّز طلبك…');
    try {
      final uid = await repo.ensureSession();
      final batch = DateTime.now().millisecondsSinceEpoch.toRadixString(36);

      // Photo ids are unique per device, so one map serves every book.
      final used = <String>{
        for (final b in books) ...b.draft.usedPhotoIds.where((id) => b.draft.photos.any((p) => p.id == id)),
        for (final i in items) ...i.line.photoIds,
      }.toList();

      final paths = <String, String>{};
      state = CheckoutState(busy: true, toUpload: used.length, stage: 'نرفع صورك بأمان…');
      for (final id in used) {
        final bytes = await PhotoStore.instance.full(id);
        if (bytes == null) throw const OrderFailure('بعض الصور لم تعد موجودة على جهازك. افتحي التصميم وأعيدي إضافتها.');
        final path = '$uid/$batch/$id.jpg';
        await repo.uploadPhoto(path, bytes);
        paths[id] = path;
        state = CheckoutState(
            busy: true, uploaded: paths.length, toUpload: used.length, stage: 'نرفع صورك بأمان…');
      }

      state = const CheckoutState(busy: true, stage: 'نرسل الطلب…');
      final res = await repo.submit({
        'customer_name': customer.name,
        'phone': customer.phone,
        'city': customer.city,
        'address': customer.address,
        'notes': customer.notes,
        'books': [for (final b in books) _bookPayload(b, paths)],
        'items': [for (final i in items) _itemPayload(i, paths)],
      });

      for (final b in books) {
        await ref.read(cartProvider.notifier).remove(b.item.book);
        await ref.read(draftProvider.notifier).discard(b.item.book);
      }
      for (final i in items) {
        await ref.read(shopCartProvider.notifier).remove(i.line.id);
      }
      await rememberOrder(res.code);
      state = const CheckoutState();
      return res.code;
    } on OrderFailure catch (e) {
      state = CheckoutState(error: e.message);
    } catch (_) {
      state = const CheckoutState(error: 'تعذّر إرسال الطلب. تأكدي من الإنترنت وحاولي مرة أخرى، تصميمك محفوظ.');
    }
    return null;
  }
}

Map<String, dynamic> _bookPayload(CartBook b, Map<String, String> paths) {
  final draft = b.draft;
  final pagePayload = <Map<String, dynamic>>[];
  for (final p in b.pages.where((p) => !p.isCover)) {
    final slots = <String, dynamic>{
      for (final s in p.photoSlots)
        if (draft.placements[s.id] != null && paths[draft.placements[s.id]!.photoId] != null)
          s.id: {
            'photo_path': paths[draft.placements[s.id]!.photoId],
            'scale': draft.placements[s.id]!.scale,
            'dx': draft.placements[s.id]!.dx,
            'dy': draft.placements[s.id]!.dy,
          },
    };
    final texts = <String, dynamic>{
      for (final t in p.textSlots)
        if (t.kind == TextKind.memory && (draft.texts[t.id] ?? '').trim().isNotEmpty) t.id: draft.texts[t.id]!.trim(),
    };
    if (slots.isNotEmpty || texts.isNotEmpty) {
      pagePayload.add({'page_number': p.pageNumber, 'slots': slots, 'texts': texts});
    }
  }
  final c = draft.cover;
  final el = c.element;
  return {
    'product_slug': draft.productSlug,
    'gift_wrap': b.item.giftWrap,
    'cover': {
      'mode': c.mode == CoverMode.designer ? 'designer' : 'manual',
      'child_name': c.childName.trim(),
      'font': c.font,
      'color': c.color,
      'designer_notes': c.designerNotes,
      if (!c.namePos.isDefault) 'name_pos': c.namePos.toJson(),
      if (el != null && paths[el.photoId] != null)
        'element': {
          'photo_path': paths[el.photoId],
          'cx': el.cx,
          'cy': el.cy,
          'width': el.width,
          'rotation': el.rotation,
        },
    },
    'pages': pagePayload,
  };
}

Map<String, dynamic> _itemPayload(CartShopItem i, Map<String, String> paths) => {
      'product_slug': i.product.slug,
      'qty': i.line.qty,
      'fields': {
        for (final f in i.product.options.fields)
          if (f.type == FieldType.photos && (i.line.photos[f.id]?.isNotEmpty ?? false))
            f.id: [for (final id in i.line.photos[f.id]!) paths[id]!]
          else if (f.type != FieldType.photos && (i.line.texts[f.id] ?? '').trim().isNotEmpty)
            f.id: i.line.texts[f.id]!.trim(),
      },
    };

final checkoutProvider = NotifierProvider<CheckoutController, CheckoutState>(CheckoutController.new);

/// Order codes placed from this browser (shown on the tracking page).
const _ordersKey = 'orders:v1';
Future<void> rememberOrder(String code) async {
  final p = await SharedPreferences.getInstance();
  final list = p.getStringList(_ordersKey) ?? [];
  await p.setStringList(_ordersKey, [code, ...list.where((c) => c != code)].take(20).toList());
}

Future<List<String>> rememberedOrders() async =>
    (await SharedPreferences.getInstance()).getStringList(_ordersKey) ?? const [];

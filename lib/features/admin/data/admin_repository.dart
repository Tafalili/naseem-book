import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/models/order.dart';
import '../../../data/models/page_template.dart';
import '../../../data/models/product.dart';

/// A message ready to show in the admin UI.
class AdminFailure implements Exception {
  const AdminFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

enum AdminRole { owner, staff }

class AdminMe {
  const AdminMe({required this.userId, required this.email, required this.role, this.name});
  final String userId;
  final String email;
  final AdminRole role;
  final String? name;
  bool get isOwner => role == AdminRole.owner;
}

class TeamMember {
  const TeamMember({required this.userId, required this.email, required this.role, this.name});
  final String userId, email;
  final AdminRole role;
  final String? name;
}

/// One row in the orders list.
class AdminOrderRow {
  const AdminOrderRow({
    required this.id,
    required this.code,
    required this.status,
    required this.customerName,
    required this.phone,
    required this.city,
    required this.childName,
    required this.total,
    required this.depositAmount,
    required this.createdAt,
    required this.hasReceipt,
    this.bookCount = 1,
    this.itemCount = 0,
  });

  final String id, code, customerName, phone, city;
  final String? childName;
  final OrderStatus status;
  final int total, depositAmount;
  final DateTime createdAt;
  final bool hasReceipt;
  final int bookCount;
  final int itemCount;

  static const columns =
      'id,order_code,status,customer_name,phone,city,child_name,total,deposit_amount,created_at,receipt_path,book_count,item_count';

  factory AdminOrderRow.fromJson(Map<String, dynamic> j) => AdminOrderRow(
        id: j['id'] as String,
        code: j['order_code'] as String,
        status: OrderStatus.of(j['status'] as String?),
        customerName: (j['customer_name'] as String?) ?? '',
        phone: (j['phone'] as String?) ?? '',
        city: (j['city'] as String?) ?? '',
        childName: j['child_name'] as String?,
        total: (j['total'] as num?)?.toInt() ?? 0,
        depositAmount: (j['deposit_amount'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        hasReceipt: j['receipt_path'] != null,
        bookCount: (j['book_count'] as num?)?.toInt() ?? 1,
        itemCount: (j['item_count'] as num?)?.toInt() ?? 0,
      );
}

class AdminOrderPage {
  const AdminOrderPage({
    this.bookNo = 1,
    required this.pageNumber,
    required this.slots,
    required this.texts,
    this.transforms = const {},
  });
  final int bookNo;
  final int pageNumber;
  final Map<String, String> slots; // slotId -> storage path
  /// slotId -> placement inside the frame (scale >= 1, dx/dy as fractions of the frame).
  final Map<String, ({double scale, double dx, double dy})> transforms;
  final Map<String, String> texts; // textSlotId -> text
}

/// One book (one child) of an order.
class AdminBook {
  const AdminBook({
    required this.no,
    required this.productId,
    required this.coverMode,
    required this.cover,
    required this.giftWrap,
    required this.subtotal,
    required this.pages,
  });
  final int no;
  final String productId;
  final String coverMode;
  final Map<String, dynamic> cover;
  final bool giftWrap;
  final int subtotal;
  final List<AdminOrderPage> pages;

  String get childName => ((cover['child_name'] as String?) ?? '').trim();
}

/// One shop item of an order (frame, cards...), with what the customer filled in.
class AdminOrderItem {
  const AdminOrderItem({
    required this.no,
    required this.productId,
    required this.title,
    required this.qty,
    required this.unit,
    required this.subtotal,
    required this.fields,
    required this.photos,
    required this.fieldDefs,
  });
  final int no;
  final String productId, title;
  final int qty, unit, subtotal;
  final Map<String, dynamic> fields; // field id -> text, or list of photo paths
  final List<String> photos;
  final List<ItemField> fieldDefs; // the product's current fields (for labels)

  String labelOf(String id) => fieldDefs.where((f) => f.id == id).firstOrNull?.label ?? id;

  /// Text fields in the product's order, then any the product no longer has.
  List<(String, String)> get texts {
    final out = <(String, String)>[];
    final seen = <String>{};
    for (final f in fieldDefs) {
      final v = fields[f.id];
      if (v is String) out.add((f.label, v));
      seen.add(f.id);
    }
    fields.forEach((k, v) {
      if (!seen.contains(k) && v is String) out.add((k, v));
    });
    return out;
  }
}

class AdminOrder {
  AdminOrder({
    required this.row,
    required this.address,
    required this.notes,
    required this.books,
    this.items = const [],
    required this.lines,
    required this.receiptPath,
    required this.printedAt,
    required this.imagesPurgedAt,
    required this.history,
  });

  final AdminOrderRow row;
  final String address;
  final String? notes;
  final List<AdminBook> books;
  final List<AdminOrderItem> items;
  final List<Map<String, dynamic>> lines; // price_snapshot.lines (each has book_no on multi-book orders)
  final String? receiptPath;
  final DateTime? printedAt, imagesPurgedAt;
  final List<StatusEvent> history;

  /// Every private photo of this order (page photos and cover photos of every book).
  Iterable<String> get photoPaths sync* {
    for (final b in books) {
      for (final p in b.pages) {
        yield* p.slots.values;
      }
      final el = b.cover['element'];
      if (el is Map && el['photo_path'] is String) yield el['photo_path'] as String;
    }
    for (final i in items) {
      yield* i.photos;
    }
  }
}

class Settings {
  Settings({
    required this.prices,
    required this.depositPercent,
    required this.depositRound,
    required this.wallets,
    required this.notifyEmail,
    required this.purgeAfterPrintHours,
    required this.purgeMaxDays,
  });

  final Map<String, int> prices;
  final double depositPercent;
  final int depositRound;
  final Map<String, String> wallets;
  final String? notifyEmail;
  final int purgeAfterPrintHours, purgeMaxDays;

  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
        prices: ((j['prices'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, (v as num).toInt())),
        depositPercent: (j['deposit_percent'] as num?)?.toDouble() ?? 0,
        depositRound: (j['deposit_round'] as num?)?.toInt() ?? 1000,
        wallets: ((j['wallets'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, '${v ?? ''}')),
        notifyEmail: j['notify_email'] as String?,
        purgeAfterPrintHours: (j['purge_after_print_hours'] as num?)?.toInt() ?? 48,
        purgeMaxDays: (j['purge_max_days'] as num?)?.toInt() ?? 14,
      );
}

class AdminProduct {
  const AdminProduct({required this.id, required this.slug, required this.title, required this.basePrice, this.kind = 'book'});
  final String id, slug, title;
  final int basePrice;
  final String kind;
}

class AdminRepository {
  AdminRepository(this._db);
  final SupabaseClient _db;

  // ---------- auth ----------
  Future<void> signIn(String email, String password) async {
    try {
      await _db.auth.signInWithPassword(email: email.trim(), password: password);
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      if (m.contains('invalid')) throw const AdminFailure('البريد أو كلمة المرور غير صحيحة.');
      if (m.contains('confirm')) throw const AdminFailure('الحساب غير مفعّل بعد.');
      throw const AdminFailure('تعذّر تسجيل الدخول. تحقق من الاتصال وحاول مجدداً.');
    }
    if (await me() == null) {
      await _db.auth.signOut();
      throw const AdminFailure('هذا الحساب ليس له صلاحية على لوحة الإدارة.');
    }
  }

  Future<void> signOut() => _db.auth.signOut();

  Future<AdminMe?> me() async {
    final u = _db.auth.currentUser;
    if (u == null || u.isAnonymous) return null;
    final row = await _db.from('admins').select('role,display_name').eq('user_id', u.id).maybeSingle();
    if (row == null) return null;
    return AdminMe(
      userId: u.id,
      email: u.email ?? '',
      role: row['role'] == 'owner' ? AdminRole.owner : AdminRole.staff,
      name: row['display_name'] as String?,
    );
  }

  // ---------- orders ----------
  Future<List<AdminOrderRow>> orders({OrderStatus? status, String query = ''}) async {
    var q = _db.from('orders').select(AdminOrderRow.columns);
    if (status != null) q = q.eq('status', status.key);
    final s = query.trim();
    if (s.isNotEmpty) {
      final safe = s.replaceAll(RegExp(r'[,()%*\\]'), '');
      final digits = safe.replaceAll(RegExp(r'\D'), '');
      final parts = <String>[
        'order_code.ilike.%$safe%',
        'customer_name.ilike.%$safe%',
        'child_name.ilike.%$safe%',
        if (digits.length >= 4) 'phone.ilike.%${digits.length > 10 ? digits.substring(digits.length - 10) : digits}%',
      ];
      q = q.or(parts.join(','));
    }
    final rows = await q.order('created_at', ascending: false).limit(200);
    return rows.map(AdminOrderRow.fromJson).toList();
  }

  /// Count of orders per status (for the filter chips).
  Future<Map<OrderStatus, int>> counts() async {
    final rows = await _db.from('orders').select('status');
    final m = <OrderStatus, int>{};
    for (final r in rows) {
      final s = OrderStatus.of(r['status'] as String?);
      m[s] = (m[s] ?? 0) + 1;
    }
    return m;
  }

  Future<AdminOrder> order(String id) async {
    final o = await _db
        .from('orders')
        .select('${AdminOrderRow.columns},address,notes,product_id,cover_mode,cover_config,price_snapshot,printed_at,images_purged_at')
        .eq('id', id)
        .single();
    final pageRows = await _db
        .from('order_pages')
        .select('book_no,page_number,slots,texts')
        .eq('order_id', id)
        .order('book_no')
        .order('page_number');
    final bookRows = await _db
        .from('order_books')
        .select('book_no,product_id,cover_mode,cover_config,gift_wrap,subtotal')
        .eq('order_id', id)
        .order('book_no');
    final itemRows = await _db
        .from('order_items')
        .select('item_no,product_id,qty,unit,subtotal,fields,photos,product:products(title,options)')
        .eq('order_id', id)
        .order('item_no');
    final hist = await _db.from('order_status_history').select('to_status,note,at').eq('order_id', id).order('at');
    DateTime? dt(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();
    final pages = pageRows
        .map((p) => AdminOrderPage(
              bookNo: (p['book_no'] as num?)?.toInt() ?? 1,
              pageNumber: (p['page_number'] as num).toInt(),
              slots: ((p['slots'] as Map?) ?? const {})
                  .map((k, v) => MapEntry(k as String, ((v as Map)['photo_path'] as String?) ?? '')),
              texts: ((p['texts'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, '$v')),
              transforms: ((p['slots'] as Map?) ?? const {}).map((k, v) {
                final m = v as Map;
                double n(Object? x, double d) => (x as num?)?.toDouble() ?? d;
                return MapEntry(k as String, (scale: n(m['scale'], 1), dx: n(m['dx'], 0), dy: n(m['dy'], 0)));
              }),
            ))
        .toList();
    Map<String, dynamic> map(Object? v) => Map<String, dynamic>.from((v as Map?) ?? const {});
    final books = bookRows.isEmpty && ((o['book_count'] as num?)?.toInt() ?? 1) == 0
        ? <AdminBook>[]
        : bookRows.isEmpty
        // orders placed before multi-book orders: one book on the order row
        ? [
            AdminBook(
              no: 1,
              productId: o['product_id'] as String,
              coverMode: (o['cover_mode'] as String?) ?? 'manual',
              cover: map(o['cover_config']),
              giftWrap: false,
              subtotal: (o['total'] as num?)?.toInt() ?? 0,
              pages: pages,
            ),
          ]
        : [
            for (final b in bookRows)
              AdminBook(
                no: (b['book_no'] as num).toInt(),
                productId: b['product_id'] as String,
                coverMode: (b['cover_mode'] as String?) ?? 'manual',
                cover: map(b['cover_config']),
                giftWrap: b['gift_wrap'] == true,
                subtotal: (b['subtotal'] as num?)?.toInt() ?? 0,
                pages: pages.where((p) => p.bookNo == (b['book_no'] as num).toInt()).toList(),
              ),
          ];
    return AdminOrder(
      row: AdminOrderRow.fromJson(o),
      address: (o['address'] as String?) ?? '',
      notes: o['notes'] as String?,
      books: books,
      items: [
        for (final r in itemRows)
          AdminOrderItem(
            no: (r['item_no'] as num).toInt(),
            productId: r['product_id'] as String,
            title: ((r['product'] as Map?)?['title'] as String?) ?? '',
            qty: (r['qty'] as num).toInt(),
            unit: (r['unit'] as num).toInt(),
            subtotal: (r['subtotal'] as num).toInt(),
            fields: map(r['fields']),
            photos: ((r['photos'] as List?) ?? const []).whereType<String>().toList(),
            fieldDefs: ItemOptions.fromJson(map((r['product'] as Map?)?['options'])).fields,
          ),
      ],
      lines: (((o['price_snapshot'] as Map?)?['lines'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      receiptPath: o['receipt_path'] as String?,
      printedAt: dt(o['printed_at']),
      imagesPurgedAt: dt(o['images_purged_at']),
      history: hist.map(StatusEvent.fromJson).toList(),
    );
  }

  Future<void> setStatus(String orderId, OrderStatus status, {String? note}) async {
    try {
      await _db.rpc('admin_set_status', params: {'p_order_id': orderId, 'p_status': status.key, 'p_note': note});
    } on PostgrestException catch (e) {
      throw AdminFailure(switch (e.message) {
        'note_required' => 'اكتب سبب رفض الوصل حتى يظهر للزبون.',
        'forbidden' => 'ليست لديك صلاحية لهذا الإجراء.',
        _ => 'تعذّر تحديث الحالة. حاول مجدداً.',
      });
    }
  }

  /// Short-lived links for private files (photos: order-photos, receipt: receipts).
  Future<Map<String, String>> signedUrls(String bucket, Iterable<String> paths, {int seconds = 3600}) async {
    final list = paths.where((p) => p.isNotEmpty).toSet().toList();
    if (list.isEmpty) return const {};
    final res = await _db.storage.from(bucket).createSignedUrlsResult(list, seconds);
    return {for (final r in res.whereType<SignedUrlSuccess>()) r.path: r.signedUrl};
  }

  // ---------- settings ----------
  Future<Settings> settings() async {
    final r = await _db
        .from('app_settings')
        .select('prices,deposit_percent,deposit_round,wallets,notify_email,purge_after_print_hours,purge_max_days')
        .single();
    return Settings.fromJson(r);
  }

  Future<void> saveSettings(Map<String, dynamic> patch) async {
    try {
      await _db.from('app_settings').update(patch).eq('id', true);
    } on PostgrestException catch (e) {
      throw AdminFailure(e.message.contains('notify_email') ? 'البريد غير صحيح.' : 'تعذّر الحفظ. حاول مجدداً.');
    }
  }

  Future<List<AdminProduct>> products() async {
    final rows = await _db.from('products').select('id,slug,title,base_price,kind').order('sort_order');
    return rows
        .map((r) => AdminProduct(
              id: r['id'] as String,
              slug: r['slug'] as String,
              title: r['title'] as String,
              basePrice: (r['base_price'] as num?)?.toInt() ?? 0,
              kind: (r['kind'] as String?) ?? 'book',
            ))
        .toList();
  }

  // ---------- shop products ----------
  /// Shop items, inactive ones included (admins see every product).
  Future<List<(Product, bool)>> shopProducts() async {
    final rows = await _db
        .from('products')
        .select('${Product.columns},is_active,sort_order')
        .eq('kind', 'item')
        .order('sort_order');
    return [for (final r in rows) (Product.fromJson(r), r['is_active'] == true)];
  }

  Future<void> saveProduct(String? id, Map<String, dynamic> row) async {
    try {
      if (id == null) {
        await _db.from('products').insert({...row, 'kind': 'item', 'page_count': 1, 'photo_capacity': 1});
      } else {
        await _db.from('products').update(row).eq('id', id);
      }
    } on PostgrestException catch (e) {
      throw AdminFailure(e.code == '23505' ? 'الرابط المختصر مستخدم لمنتج آخر.' : 'تعذّر حفظ المنتج. حاول مجدداً.');
    }
  }

  /// Uploads a product photo to the public templates bucket; returns its path.
  Future<String> uploadProductImage(String slug, Uint8List bytes, String contentType) async {
    final ext = contentType.contains('png') ? 'png' : contentType.contains('webp') ? 'webp' : 'jpg';
    final path = 'shop/$slug-${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _db.storage.from('templates').uploadBinary(path, bytes,
        fileOptions: FileOptions(contentType: contentType, upsert: false, cacheControl: '31536000'));
    return path;
  }

  Future<void> setBasePrice(String productId, int price) =>
      _db.from('products').update({'base_price': price}).eq('id', productId);

  // ---------- templates ----------
  Future<void> saveTemplate(String templateId, List<PhotoSlot> photos, List<TextSlot> texts,
      {String? backgroundPath}) async {
    try {
      await _db.from('page_templates').update({
        'photo_slots': photos.map((s) => s.toJson()).toList(),
        'text_slots': texts.map((s) => s.toJson()).toList(),
        'background_path': ?backgroundPath,
      }).eq('id', templateId);
    } on PostgrestException {
      throw const AdminFailure('تعذّر حفظ القالب. حاول مجدداً.');
    }
  }

  /// Uploads a page design to the public templates bucket and returns its path.
  Future<String> uploadBackground(String slug, int page, Uint8List bytes, String contentType) async {
    final ext = contentType.contains('png') ? 'png' : contentType.contains('webp') ? 'webp' : 'jpg';
    final path = '$slug/p${page.toString().padLeft(2, '0')}-${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _db.storage.from('templates').uploadBinary(path, bytes,
        fileOptions: FileOptions(contentType: contentType, upsert: false, cacheControl: '31536000'));
    return path;
  }

  // ---------- print files ----------
  /// Templates of a product with their print files (admin read).
  Future<List<PageTemplate>> printTemplates(String productId) async {
    final rows = await _db
        .from('page_templates')
        .select('${PageTemplate.columns},print_path')
        .eq('product_id', productId)
        .order('page_number');
    return rows.map(PageTemplate.fromJson).toList();
  }

  Future<List<PageTemplate>> printTemplatesBySlug(String slug) async {
    final rows = await _db
        .from('page_templates')
        .select('${PageTemplate.columns},print_path,product:products!inner(slug)')
        .eq('product.slug', slug)
        .order('page_number');
    return rows.map(PageTemplate.fromJson).toList();
  }

  Future<String> productSlug(String productId) async =>
      (await _db.from('products').select('slug').eq('id', productId).single())['slug'] as String;

  Future<Uint8List> download(String bucket, String path) => _db.storage.from(bucket).download(path);

  /// Uploads a 300 DPI page design and links it to its template.
  Future<void> uploadPrintFile(PageTemplate t, String slug, Uint8List bytes, String contentType) async {
    final ext = contentType.contains('png') ? 'png' : 'jpg';
    final name = t.isCover ? 'cover' : 'p${t.pageNumber.toString().padLeft(2, '0')}';
    final path = '$slug/$name-${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _db.storage.from('print-files').uploadBinary(path, bytes,
        fileOptions: FileOptions(contentType: contentType, upsert: false));
    await _db.from('page_templates').update({'print_path': path}).eq('id', t.id);
    if (t.printPath != null) {
      try {
        await _db.storage.from('print-files').remove([t.printPath!]);
      } catch (_) {}
    }
  }

  // ---------- team (owner) ----------
  Future<List<TeamMember>> team() async {
    final rows = await _db.rpc('admin_list') as List;
    return rows
        .map((r) => TeamMember(
              userId: r['user_id'] as String,
              email: (r['email'] as String?) ?? '',
              role: r['role'] == 'owner' ? AdminRole.owner : AdminRole.staff,
              name: r['display_name'] as String?,
            ))
        .toList();
  }

  Future<void> addMember({required String email, required String password, required AdminRole role, String? name}) =>
      _invokeTeam({'action': 'create', 'email': email, 'password': password, 'role': role.name, 'display_name': name});

  Future<void> removeMember(String userId) => _invokeTeam({'action': 'remove', 'user_id': userId});

  Future<void> _invokeTeam(Map<String, dynamic> body) async {
    try {
      await _db.functions.invoke('admin-users', body: body);
    } on FunctionException catch (e) {
      final code = e.details is Map ? (e.details as Map)['error'] : null;
      throw AdminFailure(switch (code) {
        'invalid_email' => 'البريد غير صحيح.',
        'weak_password' => 'كلمة المرور قصيرة: 8 أحرف على الأقل.',
        'email_exists' => 'هذا البريد مسجّل مسبقاً.',
        'cannot_remove_self' => 'لا يمكنك حذف حسابك.',
        'forbidden' => 'هذا الإجراء للمالك فقط.',
        _ => 'تعذّر تنفيذ الطلب. حاول مجدداً.',
      });
    }
  }

  // ---------- notifications ----------
  Future<void> savePush(String endpoint, String p256dh, String auth) async {
    await _db.from('admin_push_subscriptions').upsert({
      'user_id': _db.auth.currentUser!.id,
      'endpoint': endpoint,
      'keys': {'p256dh': p256dh, 'auth': auth},
    }, onConflict: 'user_id,endpoint');
  }

  Future<bool> hasPush() async {
    final u = _db.auth.currentUser;
    if (u == null) return false;
    final r = await _db.from('admin_push_subscriptions').select('id').eq('user_id', u.id).limit(1);
    return r.isNotEmpty;
  }
}

final adminRepositoryProvider = Provider((ref) => AdminRepository(Supabase.instance.client));

/// Re-evaluated on every auth change.
final adminMeProvider = StreamProvider<AdminMe?>((ref) async* {
  final repo = ref.watch(adminRepositoryProvider);
  yield await repo.me();
  await for (final _ in Supabase.instance.client.auth.onAuthStateChange) {
    yield await repo.me();
  }
});

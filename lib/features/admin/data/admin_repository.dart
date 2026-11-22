import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/models/order.dart';
import '../../../data/models/page_template.dart';

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
  });

  final String id, code, customerName, phone, city;
  final String? childName;
  final OrderStatus status;
  final int total, depositAmount;
  final DateTime createdAt;
  final bool hasReceipt;

  static const columns =
      'id,order_code,status,customer_name,phone,city,child_name,total,deposit_amount,created_at,receipt_path';

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
      );
}

class AdminOrderPage {
  const AdminOrderPage({required this.pageNumber, required this.slots, required this.texts});
  final int pageNumber;
  final Map<String, String> slots; // slotId -> storage path
  final Map<String, String> texts; // textSlotId -> text
}

class AdminOrder {
  AdminOrder({
    required this.row,
    required this.address,
    required this.notes,
    required this.coverMode,
    required this.cover,
    required this.lines,
    required this.receiptPath,
    required this.printedAt,
    required this.imagesPurgedAt,
    required this.pages,
    required this.history,
  });

  final AdminOrderRow row;
  final String address;
  final String? notes;
  final String coverMode;
  final Map<String, dynamic> cover;
  final List<Map<String, dynamic>> lines; // price_snapshot.lines
  final String? receiptPath;
  final DateTime? printedAt, imagesPurgedAt;
  final List<AdminOrderPage> pages;
  final List<StatusEvent> history;

  /// Every private file of this order (photos, cover photo, receipt).
  Iterable<String> get photoPaths sync* {
    for (final p in pages) {
      yield* p.slots.values;
    }
    final el = cover['element'];
    if (el is Map && el['photo_path'] is String) yield el['photo_path'] as String;
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
  const AdminProduct({required this.id, required this.slug, required this.title, required this.basePrice});
  final String id, slug, title;
  final int basePrice;
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
        .select('${AdminOrderRow.columns},address,notes,cover_mode,cover_config,price_snapshot,printed_at,images_purged_at')
        .eq('id', id)
        .single();
    final pages = await _db.from('order_pages').select('page_number,slots,texts').eq('order_id', id).order('page_number');
    final hist = await _db.from('order_status_history').select('to_status,note,at').eq('order_id', id).order('at');
    DateTime? dt(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();
    return AdminOrder(
      row: AdminOrderRow.fromJson(o),
      address: (o['address'] as String?) ?? '',
      notes: o['notes'] as String?,
      coverMode: (o['cover_mode'] as String?) ?? 'manual',
      cover: Map<String, dynamic>.from((o['cover_config'] as Map?) ?? const {}),
      lines: (((o['price_snapshot'] as Map?)?['lines'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      receiptPath: o['receipt_path'] as String?,
      printedAt: dt(o['printed_at']),
      imagesPurgedAt: dt(o['images_purged_at']),
      pages: pages
          .map((p) => AdminOrderPage(
                pageNumber: (p['page_number'] as num).toInt(),
                slots: ((p['slots'] as Map?) ?? const {}).map(
                    (k, v) => MapEntry(k as String, ((v as Map)['photo_path'] as String?) ?? '')),
                texts: ((p['texts'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, '$v')),
              ))
          .toList(),
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
    final rows = await _db.from('products').select('id,slug,title,base_price').order('sort_order');
    return rows
        .map((r) => AdminProduct(
              id: r['id'] as String,
              slug: r['slug'] as String,
              title: r['title'] as String,
              basePrice: (r['base_price'] as num?)?.toInt() ?? 0,
            ))
        .toList();
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

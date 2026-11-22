import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/order.dart';

/// Thrown with a message ready to show the customer.
class OrderFailure implements Exception {
  const OrderFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class OrderRepository {
  OrderRepository(this._db);
  final SupabaseClient _db;

  /// Guests order without an account: an anonymous session ties the order,
  /// its photos and its receipt to this browser.
  Future<String> ensureSession() async {
    final s = _db.auth.currentSession;
    if (s != null) return s.user.id;
    try {
      final res = await _db.auth.signInAnonymously();
      return res.user!.id;
    } on AuthException catch (e) {
      if (e.message.toLowerCase().contains('anonymous')) {
        throw const OrderFailure('استقبال الطلبات متوقف مؤقتاً. حاولي بعد قليل أو تواصلي معنا.');
      }
      throw const OrderFailure('تعذّر الاتصال. تأكدي من الإنترنت وحاولي مرة أخرى.');
    }
  }

  String? get uid => _db.auth.currentUser?.id;

  Future<void> uploadPhoto(String path, Uint8List bytes) => _db.storage.from('order-photos').uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
      );

  Future<({String id, String code})> submit(Map<String, dynamic> payload) async {
    try {
      final r = Map<String, dynamic>.from(await _db.rpc('submit_order', params: {'p': payload}) as Map);
      return (id: r['order_id'] as String, code: r['order_code'] as String);
    } on PostgrestException catch (e) {
      throw OrderFailure(_message(e.message));
    }
  }

  Future<OrderView?> myOrder(String code) async {
    if (uid == null) return null;
    final row = await _db
        .from('orders')
        .select(OrderView.ownColumns)
        .eq('order_code', code.toUpperCase())
        .maybeSingle();
    if (row == null) return null;
    final hist = await _db
        .from('order_status_history')
        .select('to_status,note,at')
        .eq('order_id', row['id'] as String)
        .order('at');
    return OrderView.fromRow(row, hist.map(StatusEvent.fromJson).toList());
  }

  Future<List<OrderView>> myOrders() async {
    if (uid == null) return const [];
    final rows = await _db
        .from('orders')
        .select(OrderView.ownColumns)
        .order('created_at', ascending: false)
        .limit(20);
    return rows.map((r) => OrderView.fromRow(r, const [])).toList();
  }

  Future<OrderView?> track(String code, String phone) async {
    final r = await _db.rpc('track_order', params: {'p_code': code, 'p_phone': phone});
    if (r == null) return null;
    return OrderView.fromTrack(Map<String, dynamic>.from(r as Map));
  }

  Future<Wallets> wallets() async {
    final r = await _db.rpc('get_payment_wallets');
    if (r == null) return const Wallets({});
    return Wallets(Map<String, dynamic>.from(r as Map).map((k, v) => MapEntry(k, '${v ?? ''}')));
  }

  Future<void> uploadReceipt(String orderId, Uint8List bytes, {required String ext, required String contentType}) async {
    final id = await ensureSession();
    final path = '$id/$orderId-${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _db.storage.from('receipts').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    try {
      await _db.rpc('attach_receipt', params: {'p_order_id': orderId, 'p_path': path});
    } on PostgrestException catch (e) {
      throw OrderFailure(_message(e.message));
    }
  }

  Future<void> savePushSubscription(String orderId, String endpoint, String p256dh, String auth) async {
    await _db.from('push_subscriptions').upsert({
      'guest_uid': uid,
      'order_id': orderId,
      'endpoint': endpoint,
      'keys': {'p256dh': p256dh, 'auth': auth},
    }, onConflict: 'order_id,endpoint');
  }

  static String _message(String code) => switch (code) {
        'too_many_orders' => 'وصلتِ للحد اليومي للطلبات من هذا الجهاز. تواصلي معنا إن احتجتِ طلباً إضافياً.',
        'invalid_child_name' => 'اسم الطفل على الغلاف طويل (حتى 20 حرفاً).',
        'invalid_photo' => 'لم يكتمل رفع بعض الصور. حاولي إرسال الطلب مرة أخرى.',
        'product_not_found' => 'هذا المنتج غير متوفر حالياً.',
        'order_not_awaiting_deposit' => 'هذا الطلب لا ينتظر إيصال عربون الآن.',
        'invalid_receipt' => 'تعذّر رفع الإيصال. حاولي مرة أخرى.',
        _ when code.contains('phone') => 'رقم الهاتف غير صحيح.',
        _ when code.contains('check constraint') => 'تأكدي من صحة البيانات المدخلة.',
        _ => 'حدث خطأ غير متوقع. حاولي مرة أخرى.',
      };
}

final orderRepositoryProvider = Provider((ref) => OrderRepository(Supabase.instance.client));

/// Order status, in the order the customer sees them on the timeline.
enum OrderStatus {
  pendingDeposit('pending_deposit', '🧾', 'استلمنا طلبك'),
  depositReview('deposit_review', '💳', 'نراجع العربون'),
  confirmed('confirmed', '✅', 'تم تأكيد طلبك'),
  designing('designing', '🎨', 'نصمم كتابك'),
  printing('printing', '🖨️', 'قيد الطباعة والتجليد'),
  shipped('shipped', '🚚', 'في الطريق إليك'),
  delivered('delivered', '🎁', 'تم التسليم'),
  cancelled('cancelled', '❌', 'ملغي');

  const OrderStatus(this.key, this.emoji, this.label);
  final String key;
  final String emoji;
  final String label;

  static OrderStatus of(String? k) =>
      values.firstWhere((s) => s.key == k, orElse: () => OrderStatus.pendingDeposit);

  /// Steps shown on the timeline (cancelled is shown only when it happens).
  static const flow = [
    pendingDeposit, depositReview, confirmed, designing, printing, shipped, delivered,
  ];
}

class StatusEvent {
  const StatusEvent({required this.status, required this.at, this.note});
  final OrderStatus status;
  final DateTime at;
  final String? note;

  factory StatusEvent.fromJson(Map<String, dynamic> j) => StatusEvent(
        status: OrderStatus.of(j['to_status'] as String?),
        at: DateTime.parse(j['at'] as String).toLocal(),
        note: j['note'] as String?,
      );
}

/// What the customer sees about one order. [id] is null when the order was
/// looked up from another device (code + phone): read-only, no payment actions.
class OrderView {
  const OrderView({
    required this.code,
    required this.status,
    required this.total,
    required this.depositAmount,
    required this.depositPercent,
    required this.createdAt,
    required this.history,
    this.id,
    this.childName,
    this.imagesPurgedAt,
    this.hasReceipt = false,
  });

  final String? id;
  final String code;
  final OrderStatus status;
  final String? childName;
  final int total, depositAmount;
  final double depositPercent;
  final DateTime createdAt;
  final DateTime? imagesPurgedAt;
  final List<StatusEvent> history;
  final bool hasReceipt;

  bool get isOwn => id != null;

  /// Latest note left by the store (e.g. why a receipt was rejected).
  String? get latestNote {
    for (final e in history.reversed) {
      if (e.note != null && e.note!.trim().isNotEmpty) return e.note;
    }
    return null;
  }

  static const ownColumns =
      'id,order_code,status,child_name,total,deposit_amount,deposit_percent,created_at,'
      'images_purged_at,receipt_path';

  factory OrderView.fromRow(Map<String, dynamic> j, List<StatusEvent> history) => OrderView(
        id: j['id'] as String?,
        code: j['order_code'] as String,
        status: OrderStatus.of(j['status'] as String?),
        childName: j['child_name'] as String?,
        total: (j['total'] as num?)?.toInt() ?? 0,
        depositAmount: (j['deposit_amount'] as num?)?.toInt() ?? 0,
        depositPercent: (j['deposit_percent'] as num?)?.toDouble() ?? 0,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        imagesPurgedAt: j['images_purged_at'] == null
            ? null
            : DateTime.parse(j['images_purged_at'] as String).toLocal(),
        history: history,
        hasReceipt: j['receipt_path'] != null,
      );

  factory OrderView.fromTrack(Map<String, dynamic> j) => OrderView.fromRow(
        j,
        ((j['history'] as List?) ?? const [])
            .map((e) => StatusEvent.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

/// Payment wallets the owner set in admin (empty string = not set).
class Wallets {
  const Wallets(this.items);
  final Map<String, String> items;

  static const labels = {'zaincash': 'زين كاش', 'qicard': 'سوبر كي', 'fib': 'مصرف العراق الأول (FIB)'};

  Iterable<MapEntry<String, String>> get filled =>
      labels.entries.where((e) => (items[e.key] ?? '').trim().isNotEmpty)
          .map((e) => MapEntry(e.value, items[e.key]!.trim()));
}

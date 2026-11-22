import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:web/web.dart' as web;

import '../../core/format/money.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/order.dart';
import 'admin_orders_page.dart';
import 'admin_shell.dart';
import 'data/admin_repository.dart';

final adminOrderProvider =
    FutureProvider.autoDispose.family<AdminOrder, String>((ref, id) => ref.watch(adminRepositoryProvider).order(id));

/// Signed links for the order's photos and receipt (valid 1 hour).
final _filesProvider = FutureProvider.autoDispose
    .family<({Map<String, String> photos, Map<String, String> receipt}), String>((ref, id) async {
  final o = await ref.watch(adminOrderProvider(id).future);
  final repo = ref.watch(adminRepositoryProvider);
  if (o.imagesPurgedAt != null) return (photos: const <String, String>{}, receipt: const <String, String>{});
  final photos = await repo.signedUrls('order-photos', o.photoPaths);
  final receipt = o.receiptPath == null ? const <String, String>{} : await repo.signedUrls('receipts', [o.receiptPath!]);
  return (photos: photos, receipt: receipt);
});

const _lineLabels = {
  'book': 'الكتاب',
  'child_name': 'اسم الطفل على الغلاف',
  'photos': 'الصور داخل الكتاب',
  'printed_text': 'نص مطبوع',
  'designer_cover': 'الغلاف من تصميمنا',
  'gift_wrap': 'تغليف هدية',
  'extra_copy': 'نسخة إضافية',
};

class AdminOrderPage extends ConsumerWidget {
  const AdminOrderPage({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(adminOrderProvider(id));
    return order.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('تعذّر تحميل الطلب.'),
          TextButton(onPressed: () => ref.invalidate(adminOrderProvider(id)), child: const Text('إعادة المحاولة')),
          TextButton(onPressed: () => context.go(AdminRoutes.orders), child: const Text('رجوع للطلبات')),
        ]),
      ),
      data: (o) => _Details(order: o),
    );
  }
}

class _Details extends ConsumerWidget {
  const _Details({required this.order});
  final AdminOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final r = order.row;
    final wide = MediaQuery.sizeOf(context).width >= 1100;

    final left = [
      _StatusCard(order: order),
      const SizedBox(height: NSpace.md),
      if (order.receiptPath != null || r.status == OrderStatus.pendingDeposit) ...[
        _ReceiptCard(order: order),
        const SizedBox(height: NSpace.md),
      ],
      _CustomerCard(order: order),
      const SizedBox(height: NSpace.md),
      _PriceCard(order: order),
    ];
    final multi = order.books.length > 1;
    final right = [
      for (final b in order.books) ...[
        _BookCard(
          order: order,
          book: b,
          title: multi ? 'الكتاب ${b.no} من ${order.books.length}${b.childName.isEmpty ? '' : ' · ${b.childName}'}' : 'الكتاب',
        ),
        const SizedBox(height: NSpace.md),
      ],
      _HistoryCard(order: order),
    ];

    return ListView(
      padding: const EdgeInsets.all(NSpace.md),
      children: [
        Row(children: [
          IconButton(
            tooltip: 'رجوع',
            onPressed: () => context.go(AdminRoutes.orders),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          Text('طلب ${r.code}', style: t.headlineSmall?.copyWith(letterSpacing: 1)),
          const SizedBox(width: NSpace.sm),
          IconButton(
            tooltip: 'نسخ الرمز',
            onPressed: () => _copy(context, r.code),
            icon: const Icon(Icons.copy_rounded, size: 18),
          ),
          const Spacer(),
          Text(shortDate(r.createdAt), style: t.bodySmall),
        ]),
        const SizedBox(height: NSpace.md),
        if (wide)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 5, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: left)),
            const SizedBox(width: NSpace.md),
            Expanded(flex: 6, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right)),
          ])
        else
          ...[...left, const SizedBox(height: NSpace.md), ...right],
      ],
    );
  }
}

void _copy(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم النسخ: $text')));
}

/// 07701234567 -> 9647701234567 (WhatsApp international format).
String waNumber(String phone) {
  final d = phone.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('964')) return d;
  if (d.startsWith('0')) return '964${d.substring(1)}';
  return '964$d';
}

String waMessage(AdminOrder o, {String? note}) {
  final r = o.row;
  final origin = Uri.base.origin;
  final b = StringBuffer('مرحباً ${r.customerName}، معك كتاب نسيم.\n')
    ..write('طلبك رقم ${r.code}: ${r.status.emoji} ${r.status.label}.');
  if (r.status == OrderStatus.pendingDeposit) {
    b.write('\nالعربون المطلوب ${formatIqd(r.depositAmount)}، ويمكنك رفع صورة الوصل من صفحة الطلب.');
  }
  final n = note ?? (o.history.isEmpty ? null : o.history.last.note);
  if (n != null && n.trim().isNotEmpty) b.write('\n$n');
  b.write('\nتتبع الطلب: $origin/order/${r.code}');
  return b.toString();
}

void openWhatsApp(AdminOrder o) {
  final url = 'https://wa.me/${waNumber(o.row.phone)}?text=${Uri.encodeComponent(waMessage(o))}';
  web.window.open(url, '_blank');
}

// ---------------------------------------------------------------------------

class _StatusCard extends ConsumerStatefulWidget {
  const _StatusCard({required this.order});
  final AdminOrder order;
  @override
  ConsumerState<_StatusCard> createState() => _StatusCardState();
}

class _StatusCardState extends ConsumerState<_StatusCard> {
  bool _busy = false;

  Future<void> _set(OrderStatus s, {String? note}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(adminRepositoryProvider).setStatus(widget.order.row.id, s, note: note);
      ref.invalidate(adminOrderProvider(widget.order.row.id));
      ref.invalidate(adminOrdersProvider);
      ref.invalidate(adminCountsProvider);
      messenger.showSnackBar(SnackBar(
        content: Text('صارت الحالة: ${s.emoji} ${adminStatus(s)}'),
        action: SnackBarAction(label: 'إرسال واتساب', onPressed: () async {
          final fresh = await ref.read(adminOrderProvider(widget.order.row.id).future);
          openWhatsApp(fresh);
        }),
      ));
    } on AdminFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick() async {
    final cur = widget.order.row.status;
    final note = TextEditingController();
    var chosen = cur;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('تغيير الحالة'),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              RadioGroup<OrderStatus>(
                groupValue: chosen,
                onChanged: (v) => set(() => chosen = v ?? chosen),
                child: Column(children: [
                  for (final s in OrderStatus.values)
                    RadioListTile<OrderStatus>(
                      dense: true,
                      value: s,
                      title: Text('${s.emoji} ${adminStatus(s)}'),
                    ),
                ]),
              ),
              TextField(
                controller: note,
                maxLength: 500,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'ملاحظة تظهر للزبون (اختياري)'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (ok == true && chosen != cur) await _set(chosen, note: note.text);
  }

  OrderStatus? get _next => switch (widget.order.row.status) {
        OrderStatus.confirmed => OrderStatus.designing,
        OrderStatus.designing => OrderStatus.printing,
        OrderStatus.printing => OrderStatus.shipped,
        OrderStatus.shipped => OrderStatus.delivered,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = widget.order.row.status;
    final c = statusColor(s.key);
    final next = _next;
    return AdminCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: NSpace.md, vertical: NSpace.xs),
            decoration: BoxDecoration(
              color: c.withValues(alpha: .12),
              borderRadius: const BorderRadius.all(NRadius.pill),
            ),
            child: Text('${s.emoji} ${adminStatus(s)}', style: t.titleSmall?.copyWith(color: c)),
          ),
          const Spacer(),
          if (_busy) const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        const SizedBox(height: NSpace.md),
        Wrap(spacing: NSpace.sm, runSpacing: NSpace.sm, children: [
          if (next != null)
            FilledButton.icon(
              onPressed: _busy ? null : () => _set(next),
              icon: Text(next.emoji),
              label: Text('نقل إلى «${adminStatus(next)}»'),
            ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.swap_horiz_rounded),
            label: const Text('تغيير الحالة'),
          ),
          OutlinedButton.icon(
            onPressed: () => openWhatsApp(widget.order),
            icon: const Icon(Icons.chat_rounded, color: Color(0xFF25D366)),
            label: const Text('رسالة واتساب'),
          ),
        ]),
      ]),
    );
  }
}

class _ReceiptCard extends ConsumerStatefulWidget {
  const _ReceiptCard({required this.order});
  final AdminOrder order;
  @override
  ConsumerState<_ReceiptCard> createState() => _ReceiptCardState();
}

class _ReceiptCardState extends ConsumerState<_ReceiptCard> {
  bool _busy = false;

  Future<void> _approve() => _run(OrderStatus.confirmed, null);

  Future<void> _reject() async {
    final note = TextEditingController(text: 'لم نتمكن من التحقق من الوصل. ارفع صورة أوضح أو تواصل معنا.');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('رفض الوصل'),
        content: SizedBox(
          width: 380,
          child: TextField(
            controller: note,
            maxLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'السبب (يظهر للزبون)'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NColors.danger),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('رفض وإرجاع للزبون'),
          ),
        ],
      ),
    );
    if (ok == true) await _run(OrderStatus.pendingDeposit, note.text);
  }

  Future<void> _run(OrderStatus s, String? note) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(adminRepositoryProvider).setStatus(widget.order.row.id, s, note: note);
      ref.invalidate(adminOrderProvider(widget.order.row.id));
      ref.invalidate(adminOrdersProvider);
      ref.invalidate(adminCountsProvider);
      messenger.showSnackBar(SnackBar(
        content: Text(s == OrderStatus.confirmed ? 'تم تأكيد العربون.' : 'أُرجع الطلب للزبون لرفع وصل جديد.'),
      ));
    } on AdminFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final o = widget.order;
    final files = ref.watch(_filesProvider(o.row.id));
    final path = o.receiptPath;
    final url = path == null ? null : files.value?.receipt[path];
    final isPdf = path?.toLowerCase().endsWith('.pdf') ?? false;
    final review = o.row.status == OrderStatus.depositReview;

    return AdminCard(
      title: 'وصل العربون · ${formatIqd(o.row.depositAmount)}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (path == null)
          Text('لم يرفع الزبون الوصل بعد.', style: t.bodyMedium)
        else if (files.isLoading)
          const Padding(padding: EdgeInsets.all(NSpace.md), child: Center(child: CircularProgressIndicator()))
        else if (url == null)
          Text('الملف غير متاح.', style: t.bodyMedium)
        else if (isPdf)
          OutlinedButton.icon(
            onPressed: () => web.window.open(url, '_blank'),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('فتح الوصل (PDF)'),
          )
        else
          InkWell(
            onTap: () => web.window.open(url, '_blank'),
            child: ClipRRect(
              borderRadius: const BorderRadius.all(NRadius.sm),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: Image.network(url, fit: BoxFit.contain),
              ),
            ),
          ),
        if (review) ...[
          const SizedBox(height: NSpace.md),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _approve,
                icon: const Icon(Icons.check_rounded),
                label: const Text('تأكيد العربون'),
              ),
            ),
            const SizedBox(width: NSpace.sm),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: NColors.danger),
                onPressed: _busy ? null : _reject,
                icon: const Icon(Icons.close_rounded),
                label: const Text('رفض الوصل'),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.order});
  final AdminOrder order;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = order.row;
    Widget row(IconData i, String v, {VoidCallback? onCopy}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(i, size: 18, color: NColors.inkMuted),
            const SizedBox(width: NSpace.sm),
            Expanded(child: SelectableText(v, style: t.bodyMedium)),
            if (onCopy != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'نسخ',
                onPressed: onCopy,
                icon: const Icon(Icons.copy_rounded, size: 16),
              ),
          ]),
        );
    return AdminCard(
      title: 'الزبون',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        row(Icons.person_outline_rounded, r.customerName),
        row(Icons.phone_outlined, r.phone, onCopy: () => _copy(context, r.phone)),
        row(Icons.location_on_outlined, '${r.city} · ${order.address}',
            onCopy: () => _copy(context, '${r.city} - ${order.address}')),
        if ((order.notes ?? '').isNotEmpty) row(Icons.sticky_note_2_outlined, order.notes!),
      ]),
    );
  }
}

class _PriceCard extends StatelessWidget {
  const _PriceCard({required this.order});
  final AdminOrder order;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget line(String a, String b, {TextStyle? style}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [Expanded(child: Text(a, style: style ?? t.bodyMedium)), Text(b, style: style ?? t.bodyMedium)]),
        );
    return AdminCard(
      title: 'الحساب',
      child: Column(children: [
        for (final (i, l) in order.lines.indexed) ...[
          if (order.books.length > 1 && l['key'] == 'book')
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : NSpace.sm),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(_bookLabel(order, (l['book_no'] as num?)?.toInt() ?? 1),
                    style: t.labelLarge?.copyWith(color: NColors.sageDark)),
              ),
            ),
          line(
            '${_lineLabels[l['key']] ?? l['key']}'
            '${l['filled'] != null ? ' (${l['filled']} صورة)' : ''}'
            '${((l['qty'] as num?) ?? 1) > 1 ? ' × ${l['qty']}' : ''}',
            l['free'] == true
                ? 'مجاناً (بدل ${formatIqd((l['list_unit'] as num?) ?? 0)})'
                : formatIqd(((l['unit'] as num?) ?? 0) * ((l['qty'] as num?) ?? 1)),
          ),
        ],
        const Divider(color: NColors.line),
        line('الإجمالي', formatIqd(order.row.total), style: t.titleSmall),
        line('العربون', formatIqd(order.row.depositAmount)),
        line('المتبقي عند الاستلام', formatIqd(order.row.total - order.row.depositAmount)),
      ]),
    );
  }
}

String _bookLabel(AdminOrder o, int no) {
  final b = o.books.where((b) => b.no == no).firstOrNull;
  final name = b?.childName ?? '';
  return name.isEmpty ? 'الكتاب $no' : 'الكتاب $no · $name';
}

class _BookCard extends ConsumerWidget {
  const _BookCard({required this.order, required this.book, required this.title});
  final AdminOrder order;
  final AdminBook book;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final files = ref.watch(_filesProvider(order.row.id));
    final photos = files.value?.photos ?? const {};
    final cover = book.cover;
    final name = (cover['child_name'] as String?) ?? '';
    final designerNotes = (cover['designer_notes'] as String?) ?? '';
    final el = cover['element'];
    final coverPhoto = el is Map ? photos[el['photo_path']] : null;
    final photoCount = book.pages.fold(0, (n, p) => n + p.slots.length);

    Widget thumb(String? url, String label) => Column(children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: const BorderRadius.all(NRadius.sm),
              child: url == null
                  ? const ColoredBox(color: NColors.surfaceAlt, child: Icon(Icons.image_not_supported_outlined))
                  : InkWell(
                      onTap: () => web.window.open(url, '_blank'),
                      child: Image.network(url, fit: BoxFit.cover),
                    ),
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: t.labelSmall),
        ]);

    return AdminCard(
      title: title,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(name.isEmpty ? 'بدون اسم على الغلاف' : 'الاسم على الغلاف: $name', style: t.titleSmall),
        if (book.giftWrap) Text('🎁 تغليف هدية', style: t.bodyMedium),
        Text(book.coverMode == 'designer' ? 'الغلاف: «اتركه لذوقكم»' : 'الغلاف: من تصميم الزبون', style: t.bodyMedium),
        if ((cover['font'] as String? ?? '').isNotEmpty) Text('الخط: ${cover['font']}', style: t.bodySmall),
        if (designerNotes.isNotEmpty) Text('ملاحظات للمصمم: $designerNotes', style: t.bodyMedium),
        if (coverPhoto != null) ...[
          const SizedBox(height: NSpace.sm),
          SizedBox(width: 120, child: thumb(coverPhoto, 'صورة الغلاف')),
        ],
        const SizedBox(height: NSpace.md),
        if (order.imagesPurgedAt != null)
          Text('🔒 حُذفت الصور من السيرفر في ${shortDate(order.imagesPurgedAt!)}', style: t.bodyMedium)
        else ...[
          Text('الصور: $photoCount', style: t.titleSmall),
          const SizedBox(height: NSpace.sm),
          if (files.isLoading) const LinearProgressIndicator(),
          LayoutBuilder(builder: (context, c) {
            final cols = (c.maxWidth / 120).floor().clamp(2, 8);
            final items = [
              for (final p in book.pages)
                for (final e in p.slots.entries) (url: photos[e.value], label: 'ص ${p.pageNumber}'),
            ];
            return GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: NSpace.sm,
              crossAxisSpacing: NSpace.sm,
              childAspectRatio: .82,
              children: [for (final i in items) thumb(i.url, i.label)],
            );
          }),
        ],
        if (book.pages.any((p) => p.texts.isNotEmpty)) ...[
          const SizedBox(height: NSpace.md),
          Text('النصوص المطبوعة', style: t.titleSmall),
          for (final p in book.pages)
            for (final e in p.texts.entries)
              Padding(
                padding: const EdgeInsets.only(top: NSpace.xs),
                child: SelectableText('ص ${p.pageNumber}: ${e.value}', style: t.bodyMedium),
              ),
        ],
      ]),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.order});
  final AdminOrder order;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AdminCard(
      title: 'سجل الحالات',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final e in order.history.reversed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: NSpace.xs),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.status.emoji),
              const SizedBox(width: NSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(adminStatus(e.status), style: t.bodyMedium),
                  if ((e.note ?? '').isNotEmpty) Text(e.note!, style: t.bodySmall),
                ]),
              ),
              Text(shortDate(e.at), style: t.bodySmall),
            ]),
          ),
      ]),
    );
  }
}

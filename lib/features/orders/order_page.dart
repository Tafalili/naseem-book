import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/format/money.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/order.dart';
import '../../data/repositories/order_repository.dart';
import '../../shared/widgets/layout.dart';
import '../../shared/widgets/privacy_badge.dart';
import '../editor/draft/image_tools.dart';
import 'order_timeline.dart';
import 'web_push.dart';

final myOrderProvider = FutureProvider.autoDispose.family<OrderView?, String>(
    (ref, code) => ref.watch(orderRepositoryProvider).myOrder(code));

final walletsProvider =
    FutureProvider.autoDispose((ref) => ref.watch(orderRepositoryProvider).wallets());

/// The customer's order: payment step while awaiting the deposit, then the timeline.
/// Opened from another device it falls back to code + phone lookup.
class OrderPage extends ConsumerWidget {
  const OrderPage({super.key, required this.code});
  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(myOrderProvider(code));
    return ContentWidth(
      vertical: NSpace.xl,
      child: order.when(
        loading: () => const Padding(
            padding: EdgeInsets.all(NSpace.xxl), child: Center(child: CircularProgressIndicator())),
        error: (_, _) => LoadError(onRetry: () => ref.invalidate(myOrderProvider(code))),
        data: (o) => o == null
            ? TrackLookup(initialCode: code)
            : OrderDetails(order: o, onRefresh: () => ref.invalidate(myOrderProvider(code))),
      ),
    );
  }
}

class OrderDetails extends StatelessWidget {
  const OrderDetails({super.key, required this.order, this.onRefresh});
  final OrderView order;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final head = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: NSpace.sm, children: [
        Text('طلب رقم', style: t.headlineSmall),
        SelectableText(order.code,
            style: t.headlineSmall?.copyWith(letterSpacing: 2, color: NColors.sageDark)),
        IconButton(
          tooltip: 'نسخ رقم الطلب',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: order.code));
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('نُسخ رقم الطلب')));
          },
          icon: const Icon(Icons.copy_rounded, size: 20),
        ),
      ]),
      Text(
        order.childName == null || order.childName!.isEmpty
            ? 'احتفظي برقم الطلب لتتبعه من أي جهاز.'
            : 'كتاب ${order.childName} · احتفظي برقم الطلب لتتبعه من أي جهاز.',
        style: t.bodyMedium,
      ),
    ]);

    final side = Column(children: [
      if (order.isOwn && order.status == OrderStatus.pendingDeposit)
        _DepositCard(order: order, onDone: onRefresh),
      if (order.status == OrderStatus.depositReview)
        _InfoCard(
          icon: Icons.hourglass_top_rounded,
          title: 'استلمنا إيصال العربون',
          text: 'نراجعه الآن، وسيتحدّث الطلب هنا بعد التأكيد.',
        ),
      if (order.isOwn && order.status != OrderStatus.cancelled && order.status != OrderStatus.delivered) ...[
        const SizedBox(height: NSpace.lg),
        _PushCard(order: order),
      ],
      const SizedBox(height: NSpace.lg),
      _AmountsCard(order: order),
    ]);

    final timeline = Container(
      padding: const EdgeInsets.all(NSpace.lg),
      decoration: _card,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('حالة الطلب', style: t.titleMedium)),
          if (onRefresh != null)
            IconButton(tooltip: 'تحديث', onPressed: onRefresh, icon: const Icon(Icons.refresh_rounded)),
        ]),
        const SizedBox(height: NSpace.sm),
        OrderTimeline(order: order),
        const SizedBox(height: NSpace.md),
        const PrivacyBadge(dense: true),
      ]),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      head,
      const SizedBox(height: NSpace.lg),
      if (wide)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: timeline),
          const SizedBox(width: NSpace.lg),
          SizedBox(width: 400, child: side),
        ])
      else ...[
        side,
        const SizedBox(height: NSpace.lg),
        timeline,
      ],
    ]);
  }
}

const _card = BoxDecoration(
  color: NColors.surface,
  borderRadius: BorderRadius.all(NRadius.lg),
  boxShadow: NShadow.soft,
);

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title, text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(NSpace.lg),
      decoration: _card,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: NColors.sage),
        const SizedBox(width: NSpace.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: t.titleMedium),
            const SizedBox(height: 4),
            Text(text, style: t.bodyMedium),
          ]),
        ),
      ]),
    );
  }
}

class _AmountsCard extends StatelessWidget {
  const _AmountsCard({required this.order});
  final OrderView order;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget line(String a, String b) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [Expanded(child: Text(a, style: t.bodyMedium)), Text(b, style: t.bodyMedium)]),
        );
    return Container(
      padding: const EdgeInsets.all(NSpace.lg),
      decoration: _card,
      child: Column(children: [
        line('الإجمالي', order.total > 0 ? formatIqd(order.total) : 'يُحدد عند التأكيد'),
        if (order.depositAmount > 0)
          line('العربون', formatIqd(order.depositAmount)),
        if (order.depositAmount > 0)
          line('المتبقي عند الاستلام', formatIqd(order.total - order.depositAmount)),
      ]),
    );
  }
}

class _DepositCard extends ConsumerStatefulWidget {
  const _DepositCard({required this.order, this.onDone});
  final OrderView order;
  final VoidCallback? onDone;

  @override
  ConsumerState<_DepositCard> createState() => _DepositCardState();
}

class _DepositCardState extends ConsumerState<_DepositCard> {
  bool _busy = false;
  String? _error;

  Future<void> _upload() async {
    final files = await pickFiles(accept: 'image/jpeg,image/png,image/webp,image/heic,application/pdf');
    if (files.isEmpty) return;
    final f = files.first;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final isPdf = f.type == 'application/pdf';
      if (isPdf && f.size > 5 * 1024 * 1024) {
        throw const OrderFailure('ملف PDF أكبر من 5 ميغابايت. أرسلي صورة للإيصال بدلاً منه.');
      }
      final bytes = isPdf ? await blobBytes(f) : await blobBytes((await compressPhoto(f)).full);
      await ref.read(orderRepositoryProvider).uploadReceipt(
            widget.order.id!,
            bytes,
            ext: isPdf ? 'pdf' : 'jpg',
            contentType: isPdf ? 'application/pdf' : 'image/jpeg',
          );
      widget.onDone?.call();
    } on OrderFailure catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'تعذّر رفع الإيصال. تأكدي من الإنترنت وحاولي مرة أخرى.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final o = widget.order;
    final wallets = ref.watch(walletsProvider);
    final rejected = o.history.length > 1 ? o.latestNote : null;

    return Container(
      padding: const EdgeInsets.all(NSpace.lg),
      decoration: _card.copyWith(border: Border.all(color: NColors.sand, width: 1.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('الخطوة التالية: دفع العربون', style: t.titleMedium),
        const SizedBox(height: NSpace.xs),
        Text(
          o.depositAmount > 0
              ? 'حوّلي ${formatIqd(o.depositAmount)} إلى أحد الحسابات التالية، ثم ارفعي صورة الإيصال.'
              : 'حوّلي العربون إلى أحد الحسابات التالية، ثم ارفعي صورة الإيصال.',
          style: t.bodyMedium,
        ),
        if (rejected != null)
          Container(
            margin: const EdgeInsets.only(top: NSpace.md),
            padding: const EdgeInsets.all(NSpace.md),
            decoration: BoxDecoration(
              color: NColors.danger.withValues(alpha: .08),
              borderRadius: const BorderRadius.all(NRadius.md),
            ),
            child: Text('ملاحظة من المتجر: $rejected', style: t.bodyMedium),
          ),
        const SizedBox(height: NSpace.md),
        wallets.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => Text('تعذّر تحميل أرقام الدفع.', style: t.bodySmall),
          data: (w) => w.filled.isEmpty
              ? Text('أرقام الدفع تُضاف قريباً. سنتواصل معكِ على رقم هاتفك.', style: t.bodySmall)
              : Column(children: [
                  for (final e in w.filled)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.account_balance_wallet_outlined, color: NColors.sage),
                      title: Text(e.key),
                      subtitle: Text(e.value, textDirection: TextDirection.ltr, textAlign: TextAlign.right),
                      trailing: IconButton(
                        tooltip: 'نسخ',
                        icon: const Icon(Icons.copy_rounded, size: 20),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: e.value));
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text('نُسخ رقم ${e.key}')));
                        },
                      ),
                    ),
                ]),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: NSpace.sm),
            child: Text(_error!, style: t.bodySmall?.copyWith(color: NColors.danger)),
          ),
        const SizedBox(height: NSpace.md),
        FilledButton.icon(
          onPressed: _busy ? null : _upload,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.upload_file_rounded),
          label: Text(_busy ? 'جارٍ رفع الإيصال…' : 'ارفعي صورة الإيصال'),
        ),
      ]),
    );
  }
}

class _PushCard extends ConsumerStatefulWidget {
  const _PushCard({required this.order});
  final OrderView order;

  @override
  ConsumerState<_PushCard> createState() => _PushCardState();
}

class _PushCardState extends ConsumerState<_PushCard> {
  bool _busy = false, _done = false;

  Future<void> _enable() async {
    setState(() => _busy = true);
    try {
      final sub = await WebPush.subscribe();
      if (sub == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('لم تُفعّل الإشعارات. يمكنك تفعيلها من إعدادات المتصفح.')));
        }
        return;
      }
      await ref
          .read(orderRepositoryProvider)
          .savePushSubscription(widget.order.id!, sub.endpoint, sub.p256dh, sub.auth);
      if (mounted) setState(() => _done = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تعذّر تفعيل الإشعارات على هذا المتصفح.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (!WebPush.supported) {
      return _InfoCard(
        icon: Icons.notifications_none_rounded,
        title: 'تابعي طلبك من هنا',
        text: 'متصفحك لا يدعم الإشعارات. على آيفون: أضيفي الموقع إلى الشاشة الرئيسية لتصلك الإشعارات. '
            'وسنراسلك على واتساب في الخطوات المهمة.',
      );
    }
    return Container(
      padding: const EdgeInsets.all(NSpace.lg),
      decoration: _card,
      child: Row(children: [
        Icon(_done ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
            color: NColors.sage),
        const SizedBox(width: NSpace.md),
        Expanded(
          child: Text(
            _done ? 'ستصلك إشعارات عند كل تحديث لطلبك.' : 'فعّلي الإشعارات ليصلك كل تحديث لطلبك.',
            style: t.bodyMedium,
          ),
        ),
        if (!_done)
          OutlinedButton(onPressed: _busy || WebPush.denied ? null : _enable, child: const Text('تفعيل')),
      ]),
    );
  }
}

/// Code + phone lookup (works on any device, read-only).
class TrackLookup extends ConsumerStatefulWidget {
  const TrackLookup({super.key, this.initialCode});
  final String? initialCode;

  @override
  ConsumerState<TrackLookup> createState() => _TrackLookupState();
}

class _TrackLookupState extends ConsumerState<TrackLookup> {
  late final _code = TextEditingController(text: widget.initialCode ?? '');
  final _phone = TextEditingController();
  bool _busy = false;
  String? _error;
  OrderView? _result;

  @override
  void dispose() {
    _code.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final o = await ref.read(orderRepositoryProvider).track(_code.text.trim(), _phone.text.trim());
      setState(() {
        _result = o;
        if (o == null) _error = 'لم نجد طلباً بهذا الرقم وهذا الهاتف. تأكدي منهما وحاولي مرة أخرى.';
      });
    } catch (_) {
      setState(() => _error = 'تعذّر الاتصال. حاولي مرة أخرى.');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (_result != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        OrderDetails(order: _result!, onRefresh: _find),
        const SizedBox(height: NSpace.md),
        Text('للدفع ورفع الإيصال افتحي الطلب من الجهاز الذي أرسلتِه منه.',
            textAlign: TextAlign.center, style: t.bodySmall),
      ]);
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Container(
          padding: const EdgeInsets.all(NSpace.lg),
          decoration: _card,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('تتبّعي طلبك', style: t.headlineSmall),
            const SizedBox(height: NSpace.xs),
            Text('اكتبي رقم الطلب ورقم الهاتف الذي سجّلتِه في الطلب.', style: t.bodyMedium),
            const SizedBox(height: NSpace.lg),
            TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(labelText: 'رقم الطلب'),
            ),
            const SizedBox(height: NSpace.md),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(labelText: 'رقم الهاتف'),
              onSubmitted: (_) => _find(),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: NSpace.sm),
                child: Text(_error!, style: t.bodySmall?.copyWith(color: NColors.danger)),
              ),
            const SizedBox(height: NSpace.lg),
            FilledButton(onPressed: _busy ? null : _find, child: Text(_busy ? 'نبحث…' : 'عرض حالة الطلب')),
          ]),
        ),
      ),
    );
  }
}

/// /track: orders from this browser + lookup form.
class TrackPage extends ConsumerWidget {
  const TrackPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(_myOrdersProvider);
    final t = Theme.of(context).textTheme;
    return ContentWidth(
      vertical: NSpace.xl,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ...mine.maybeWhen(
          data: (list) => list.isEmpty
              ? const <Widget>[]
              : [
                  Text('طلباتك من هذا الجهاز', style: t.titleMedium),
                  const SizedBox(height: NSpace.sm),
                  for (final o in list)
                    Card(
                      color: NColors.surface,
                      child: ListTile(
                        title: Text('${o.code}${o.childName == null ? '' : ' · ${o.childName}'}'),
                        subtitle: Text('${o.status.emoji} ${o.status.label}'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.go(Routes.order(o.code)),
                      ),
                    ),
                  const SizedBox(height: NSpace.xl),
                ],
          orElse: () => const <Widget>[],
        ),
        const TrackLookup(),
      ]),
    );
  }
}

final _myOrdersProvider =
    FutureProvider.autoDispose((ref) => ref.watch(orderRepositoryProvider).myOrders());
